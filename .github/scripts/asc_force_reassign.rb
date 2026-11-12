#!/usr/bin/env ruby
# 强制重新指派个人测试员（外部状态卡在 BETA_APPROVED 不动时用）。
# 背景：测试员在 Beta 审核前就指派到构建，审核通过后 Apple 不一定触发分发，
#       外部状态停在 BETA_APPROVED，手机 TestFlight 收不到。
# 做法：把现有测试员从构建上移除，再重新指派。重新指派发生在审核已通过之后，
#       Apple 会立即分发并给测试员发通知邮件，状态走成 IN_BETA_TESTING。
# 环境变量：ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH / ASC_BUNDLE_ID / ASC_BUILD_NUMBER

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'time'
require 'uri'

KEY_ID    = ENV.fetch('ASC_KEY_ID')
ISSUER_ID = ENV.fetch('ASC_ISSUER_ID')
KEY_PATH  = ENV.fetch('ASC_KEY_PATH')
BUNDLE_ID = ENV['ASC_BUNDLE_ID'] || 'com.emotionanchor.diary'
BUILD_NO  = ENV['ASC_BUILD_NUMBER'].to_s.strip

def b64url(data)
  Base64.urlsafe_encode64(data, padding: false)
end

def to_fixed32(bn)
  bytes = bn.to_s(2).bytes
  return bytes.last(32).pack('C*') if bytes.size >= 32

  ("\x00" * (32 - bytes.size)) + bytes.pack('C*')
end

def make_token
  ec = begin
    OpenSSL::PKey.read(File.read(KEY_PATH))
  rescue StandardError
    OpenSSL::PKey::EC.new(File.read(KEY_PATH))
  end
  now = Time.now.to_i
  header = { 'alg' => 'ES256', 'kid' => KEY_ID, 'typ' => 'JWT' }
  payload = { 'iss' => ISSUER_ID, 'iat' => now, 'exp' => now + 600, 'aud' => 'appstoreconnect-v1' }
  signing_input = b64url(JSON.generate(header)) + '.' + b64url(JSON.generate(payload))
  der = ec.sign(OpenSSL::Digest.new('SHA256'), signing_input)
  raw = OpenSSL::ASN1.decode(der).value.map { |n| to_fixed32(n.value) }.join
  signing_input + '.' + b64url(raw)
end

TOKEN = make_token

def call(verb, path, body = nil)
  uri = URI('https://api.appstoreconnect.apple.com' + path)
  req = Net::HTTP.new(uri.hostname, uri.port).tap { |h| h.use_ssl = true }
  req = verb == :get ? Net::HTTP::Get.new(uri) : verb == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Delete.new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  req['Content-Type'] = 'application/json'
  req.body = JSON.generate(body) unless body.nil?
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 90) { |h| h.request(req) }
  [res.code.to_i, res.body.to_s]
end

code, body = call(:get, "/v1/apps?filter%5BbundleId%5D=#{BUNDLE_ID}")
abort("查询 App 失败 HTTP #{code}") unless code == 200
app = (JSON.parse(body)['data'] || []).first
abort('没有找到 App') if app.nil?

code, body = call(:get, "/v1/apps/#{app['id']}/builds?limit=20")
abort("查询构建失败 HTTP #{code}") unless code == 200
builds = (JSON.parse(body)['data'] || []).sort_by { |b| b.dig('attributes', 'uploadedDate').to_s }.reverse
build = if BUILD_NO.empty?
          builds.first
        else
          builds.find { |b| b.dig('attributes', 'version').to_s == BUILD_NO }
        end
abort("没有找到构建 #{BUILD_NO}") if build.nil?
build_id = build['id']
puts "目标构建: #{build.dig('attributes', 'version')} (#{build.dig('attributes', 'processingState')})"

code, body = call(:get, "/v1/betaTesters?limit=200")
abort("查询测试员失败 HTTP #{code}") unless code == 200
testers = JSON.parse(body)['data'] || []
abort('账号下没有测试员') if testers.empty?
emails = testers.map { |t| t.dig('attributes', 'email') }
puts "账号测试员: #{emails.join(', ')}"
tester_ids = testers.map { |t| t['id'] }

# 1. 先看当前构建已指派的测试员
code, body = call(:get, "/v1/builds/#{build_id}/betaTesters?limit=200")
assigned = code == 200 ? (JSON.parse(body)['data'] || []).map { |t| t['id'] } : []
puts "构建当前已指派: #{assigned.empty? ? '（无）' : assigned.inspect}"

# 2. 如果已有指派，先移除（触发 Apple 重新登记分发状态）
unless assigned.empty?
  code, body = call(:delete, "/v1/builds/#{build_id}/relationships/betaTesters",
                    { 'data' => assigned.map { |i| { 'type' => 'betaTesters', 'id' => i } } })
  puts code >= 200 && code < 300 ? "已从构建移除 #{assigned.size} 位测试员（准备重新指派）" : "移除失败 HTTP #{code} #{body[0, 300]}"
  sleep 3
end

# 3. 重新指派（审核已通过，Apple 此时会立即分发并发通知邮件）
code, body = call(:post, "/v1/builds/#{build_id}/relationships/betaTesters",
                  { 'data' => tester_ids.map { |i| { 'type' => 'betaTesters', 'id' => i } } })
if code >= 200 && code < 300
  puts "已重新指派 #{tester_ids.size} 位测试员到构建 #{build.dig('attributes', 'version')}，Apple 会立即分发并邮件通知。"
else
  puts "重新指派失败 HTTP #{code}\n#{body[0, 600]}"
end

# 4. 回读外部状态
sleep 5
code, body = call(:get, "/v1/builds/#{build_id}?include=buildBetaDetail")
if code == 200
  json = JSON.parse(body)
  inc = (json['included'] || []).each_with_object({}) { |i, h| h[i['id']] = i }
  detail_id = json.dig('data', 'relationships', 'buildBetaDetail', 'data', 'id')
  puts "外部状态=#{inc.dig(detail_id, 'attributes', 'externalBuildState') || '?'}"
end
