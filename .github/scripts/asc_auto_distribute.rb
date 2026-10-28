#!/usr/bin/env ruby
# 上传到 TestFlight 后，自动把新构建加入测试组（内部组优先）。
# 只用 Ruby 标准库，macOS runner 自带，无需 gem install。
#
# 环境变量：
#   ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH   必填（流水线已提供）
#   ASC_BUNDLE_ID          默认 com.emotionanchor.diary
#   ASC_MARKETING_VERSION  默认 1.0
#   ASC_BETA_GROUP         指定测试组名；留空则自动选内部组
#   ASC_WAIT_MINUTES       等待 Apple 处理的超时分钟数，默认 40

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'time'
require 'uri'

KEY_ID     = ENV.fetch('ASC_KEY_ID')
ISSUER_ID  = ENV.fetch('ASC_ISSUER_ID')
KEY_PATH   = ENV.fetch('ASC_KEY_PATH')
BUNDLE_ID  = ENV['ASC_BUNDLE_ID'] || 'com.emotionanchor.diary'
VERSION    = ENV['ASC_MARKETING_VERSION'] || '1.0'
GROUP_NAME = ENV['ASC_BETA_GROUP'].to_s.strip
WAIT_MIN   = (ENV['ASC_WAIT_MINUTES'] || '40').to_i
SUMMARY    = ENV['GITHUB_STEP_SUMMARY'].to_s

def log(msg)
  puts msg
  File.open(SUMMARY, 'a') { |f| f.puts(msg) } unless SUMMARY.empty?
rescue StandardError
  nil
end

def b64url(data)
  Base64.urlsafe_encode64(data, padding: false)
end

# JWS 签名段要求定长 32 字节的 r 拼接 s，而不是 DER 里的可变长整数
def to_fixed32(bn)
  bytes = bn.to_s(2).bytes
  return bytes.last(32).pack('C*') if bytes.size >= 32

  ("\x00" * (32 - bytes.size)) + bytes.pack('C*')
end

def make_token
  pem = File.read(KEY_PATH)
  # Apple 的 .p8 是 PKCS#8 PEM；OpenSSL::PKey::EC.new 在部分 Ruby 版本下读不了 PKCS#8，
  # 用 PKey.read 自动识别格式更稳，失败再退回 EC.new
  ec = begin
    OpenSSL::PKey.read(pem)
  rescue StandardError
    OpenSSL::PKey::EC.new(pem)
  end
  now    = Time.now.to_i
  header  = { 'alg' => 'ES256', 'kid' => KEY_ID, 'typ' => 'JWT' }
  payload = { 'iss' => ISSUER_ID, 'iat' => now, 'exp' => now + 1200, 'aud' => 'appstoreconnect-v1' }
  signing_input = b64url(JSON.generate(header)) + '.' + b64url(JSON.generate(payload))
  der = ec.sign(OpenSSL::Digest.new('SHA256'), signing_input)
  seq = OpenSSL::ASN1.decode(der)
  raw = seq.value.map { |node| to_fixed32(node.value) }.join
  signing_input + '.' + b64url(raw)
end

def asc(verb, path, token, body = nil)
  uri = URI('https://api.appstoreconnect.apple.com' + path)
  req = verb == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
  req['Authorization'] = "Bearer #{token}"
  req['Content-Type']  = 'application/json'
  req.body = JSON.generate(body) unless body.nil?
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 90) do |http|
    http.request(req)
  end
  [res.code.to_i, res.body.to_s]
rescue StandardError => e
  [-1, e.message]
end

begin
  token = make_token
rescue StandardError => e
  log "生成 JWT 失败: #{e.message}"
  exit 1
end

code, body = asc(:get, "/v1/apps?filter%5BbundleId%5D=#{BUNDLE_ID}", token)
unless code == 200
  log "查询 App 失败: HTTP #{code}\n#{body[0, 800]}"
  exit 1
end

apps = (JSON.parse(body)['data'] || [])
if apps.empty?
  log "未找到 bundleId=#{BUNDLE_ID} 的 App，请确认 App Store Connect 里已创建"
  exit 1
end

app_id = apps[0]['id']
log "App: #{apps[0].dig('attributes', 'name')} (#{app_id})"

code, body = asc(:get, "/v1/apps/#{app_id}/betaGroups?limit=50", token)
unless code == 200
  log "查询测试组失败: HTTP #{code}\n#{body[0, 600]}"
  exit 1
end

groups = (JSON.parse(body)['data'] || [])
if groups.empty?
  log '该 App 还没有测试组。请先在 App Store Connect 网页创建: TestFlight -> 新建组(内部组无需审核)'
  exit 0
end

group = nil
if !GROUP_NAME.empty?
  group = groups.find { |g| g.dig('attributes', 'name') == GROUP_NAME }
  if group.nil?
    names = groups.map { |g| g.dig('attributes', 'name') }.join('、')
    log "未找到名为 #{GROUP_NAME} 的测试组。现有组: #{names}"
    exit 1
  end
else
  group = groups.find { |g| g.dig('attributes', 'isInternalGroup') == true } || groups[0]
end

group_name     = group.dig('attributes', 'name')
group_internal = group.dig('attributes', 'isInternalGroup') == true
log "目标测试组: #{group_name} (#{group_internal ? '内部组' : '外部组'})"

started  = Time.now
deadline = started + WAIT_MIN * 60
last     = nil
build    = nil

while Time.now < deadline
  code, body = asc(:get, "/v1/apps/#{app_id}/builds?limit=10&sort=-uploadedDate", token)
  if code == 200
    list = (JSON.parse(body)['data'] || [])
    cand = list.find { |b| b.dig('attributes', 'version') == VERSION }
    if cand
      state = cand.dig('attributes', 'processingState')
      # 只在状态变化时输出，避免每 30 秒刷一行日志
      if state != last
        elapsed = ((Time.now - started) / 60).round
        log "构建 #{VERSION} (#{cand.dig('attributes', 'buildNumber')}) 状态: #{state} (已等待 #{elapsed} 分钟)"
        last = state
      end
      if state == 'VALID'
        build = cand
        break
      elsif %w[FAILED INVALID PROCESSING_EXCEPTION].include?(state)
        log "Apple 处理失败: #{state}。常见原因: 缺少 Info.plist 加密合规声明, 或 App Store Connect 该 App 权限不足"
        exit 1
      end
    elsif last != 'MISSING'
      log "构建尚未出现在 App Store Connect 索引中, 继续等待..."
      last = 'MISSING'
    end
  else
    log "查询构建列表失败: HTTP #{code}, 稍后重试"
  end
  sleep 30
end

if build.nil?
  log "等待 #{WAIT_MIN} 分钟后构建仍未处理完成。请稍后在 App Store Connect -> TestFlight 手动把该构建加入 #{group_name}"
  exit 0
end

code, body = asc(:post, "/v1/betaGroups/#{group['id']}/relationships/builds", token,
                 { 'data' => [{ 'type' => 'builds', 'id' => build['id'] }] })

if code >= 200 && code < 300
  log "构建 #{VERSION} (#{build.dig('attributes', 'buildNumber')}) 已加入 #{group_name}。打开手机 TestFlight 即可看到更新。"
elsif code == 409
  log "构建已在该测试组中, 无需重复添加。"
else
  log "加入测试组失败: HTTP #{code}\n#{body[0, 800]}"
  exit 1
end
