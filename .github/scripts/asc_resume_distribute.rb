#!/usr/bin/env ruby
# 续跑分发：不重新上传构建，只对已上传的构建补做
#   1) 等待 Apple 处理完成（VALID）
#   2) 加入测试组（404/5xx 自动重试——构建刚处理完时索引可能尚未就绪）
#   3) 指派个人测试员
#   4) 提交 Beta 审核（外部测试员必需）
# 用途：ios-testflight.yml 在「自动把构建加入测试组」一步因 ASC API 404 失败后，
#       无需重新打包上传（重传会消耗新的 build number），手动跑本工作流即可恢复。
# 环境变量：
#   ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH   必填
#   ASC_BUNDLE_ID          默认 com.emotionanchor.diary
#   ASC_BUILD_NUMBER       构建号；留空取最新构建
#   ASC_BETA_GROUP         指定测试组名；留空自动选内部组
#   ASC_WAIT_MINUTES       等待处理的最长分钟数，默认 20
#   ASC_SUBMIT_REVIEW      是否提交 Beta 审核，默认 true

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
BUILD_NO   = ENV['ASC_BUILD_NUMBER'].to_s.strip
GROUP_NAME = ENV['ASC_BETA_GROUP'].to_s.strip
WAIT_MIN   = (ENV['ASC_WAIT_MINUTES'] || '20').to_i
SUBMIT     = ENV['ASC_SUBMIT_REVIEW'].to_s.strip != 'false'
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

def to_fixed32(bn)
  bytes = bn.to_s(2).bytes
  return bytes.last(32).pack('C*') if bytes.size >= 32

  ("\x00" * (32 - bytes.size)) + bytes.pack('C*')
end

def make_token
  pem = File.read(KEY_PATH)
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

TOKEN = make_token

def asc(verb, path, body = nil)
  uri = URI('https://api.appstoreconnect.apple.com' + path)
  req = verb == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  req['Content-Type']  = 'application/json'
  req.body = JSON.generate(body) unless body.nil?
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 90) do |http|
    http.request(req)
  end
  [res.code.to_i, res.body.to_s]
rescue StandardError => e
  [-1, e.message]
end

# 404/5xx 自动重试：构建刚处理完时 ASC 索引/关系端点可能短暂 404
def asc_with_retry(verb, path, body = nil, attempts: 6, wait: 30)
  (1..attempts).each do |i|
    code, resp = asc(verb, path, body)
    return [code, resp] if code >= 200 && code < 300 || code == 409

    transient = code == 404 || code == -1 || code >= 500
    log "  第 #{i}/#{attempts} 次请求失败: HTTP #{code}#{transient ? '（临时性错误，稍后重试）' : '（不重试）'}"
    return [code, resp] unless transient
    sleep wait unless i == attempts
  end
  [-1, '重试次数用尽']
end

# ---- 找到 App 与构建 ----
code, body = asc(:get, "/v1/apps?filter%5BbundleId%5D=#{BUNDLE_ID}")
abort("查询 App 失败: HTTP #{code}") unless code == 200
app = (JSON.parse(body)['data'] || []).first
abort('没有找到 App') if app.nil?
app_id = app['id']
log "App: #{app.dig('attributes', 'name')} (#{app_id})"

# ---- 选测试组 ----
code, body = asc(:get, "/v1/apps/#{app_id}/betaGroups?limit=50")
abort("查询测试组失败: HTTP #{code}") unless code == 200
groups = JSON.parse(body)['data'] || []
group = if !GROUP_NAME.empty?
          groups.find { |g| g.dig('attributes', 'name') == GROUP_NAME }
        else
          groups.find { |g| g.dig('attributes', 'isInternalGroup') == true } || groups.first
        end
abort('没有找到测试组，请先在 App Store Connect 创建') if group.nil?
log "目标测试组: #{group.dig('attributes', 'name')}"

# ---- 等构建 VALID ----
started  = Time.now
deadline = started + WAIT_MIN * 60
build    = nil
last     = nil
while Time.now < deadline
  code, body = asc(:get, "/v1/apps/#{app_id}/builds?limit=20")
  if code == 200
    list = (JSON.parse(body)['data'] || []).sort_by { |b| b.dig('attributes', 'uploadedDate').to_s }.reverse
    cand = BUILD_NO.empty? ? list.first : list.find { |b| b.dig('attributes', 'version').to_s == BUILD_NO }
    if cand
      state = cand.dig('attributes', 'processingState')
      if state != last
        log "构建 #{BUILD_NO.empty? ? '最新' : BUILD_NO} 状态: #{state} (已等待 #{((Time.now - started) / 60).round} 分钟)"
        last = state
      end
      build = cand if state == 'VALID'
      break if build || %w[FAILED INVALID PROCESSING_EXCEPTION].include?(state)
    end
  end
  break if build
  sleep 30
end
abort('构建未就绪或处理失败，请稍后重试') if build.nil?
abort("Apple 处理失败: #{last}") if %w[FAILED INVALID PROCESSING_EXCEPTION].include?(last)

build_id   = build['id']
build_no   = build.dig('attributes', 'version')
log "目标构建: #{build_no} (#{build_id})"

# ---- 加入测试组（带重试；Apple 偶发 404/500，失败不致命：
#      内部组自动可见全部构建，外部测试员靠下面的个人指派 + Beta 审核）----
code, body = asc_with_retry(:post, "/v1/betaGroups/#{group['id']}/relationships/builds",
                            [{ 'type' => 'builds', 'id' => build_id }])
case code
when 200..299
  log "构建 #{build_no} 已加入 #{group.dig('attributes', 'name')}。"
when 409
  log '构建已在该测试组中，无需重复添加。'
else
  log "⚠️ 加入测试组失败: HTTP #{code}（继续执行个人指派与 Beta 审核）\n#{body[0, 400]}"
end

# ---- 指派个人测试员（带重试）----
code, body = asc(:get, '/v1/betaTesters?limit=200')
if code == 200
  tester_ids = (JSON.parse(body)['data'] || []).map { |t| t['id'] }
  unless tester_ids.empty?
    c, b = asc_with_retry(:post, "/v1/builds/#{build_id}/relationships/individualTesters",
                          tester_ids.map { |i| { 'type' => 'betaTesters', 'id' => i } })
    log(c >= 200 && c < 300 ? "已指派 #{tester_ids.size} 位测试员。" :
        c == 409 ? '测试员此前已指派，无需重复。' :
        "指派个人测试员失败: HTTP #{c} #{b[0, 300]}")
  end
end

# ---- 提交 Beta 审核 ----
if SUBMIT
  code, body = asc_with_retry(:post, '/v1/betaAppReviewSubmissions',
                              { 'data' => {
                                'type' => 'betaAppReviewSubmissions',
                                'relationships' => { 'build' => { 'data' => { 'type' => 'builds', 'id' => build_id } } }
                              } }, attempts: 3)
  if code >= 200 && code < 300
    log "构建 #{build_no} 已提交 Beta 审核。审核通过后手机 TestFlight 会收到更新。"
  elsif code == 409
    log '构建已在审核流程中或已通过，无需重复提交。'
  else
    log "提交 Beta 审核失败: HTTP #{code}\n#{body[0, 600]}"
    exit 1
  end
end

log '续跑分发完成。'
