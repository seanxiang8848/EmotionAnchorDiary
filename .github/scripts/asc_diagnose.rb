#!/usr/bin/env ruby
# 只读诊断：打印 App、测试组、最近构建及其所属测试组，用来判断
# 「上传成功但手机上 TestFlight 看不到」到底卡在哪一环。
# 不修改任何数据。环境变量同 asc_auto_distribute.rb。

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

def get(path)
  uri = URI('https://api.appstoreconnect.apple.com' + path)
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 60) { |h| h.request(req) }
  [res.code.to_i, res.body.to_s]
end

puts '=== 1. 定位 App ==='
code, body = get("/v1/apps?filter%5BbundleId%5D=#{BUNDLE_ID}")
abort("查询 App 失败 HTTP #{code}: #{body[0, 400]}") unless code == 200
app = (JSON.parse(body)['data'] || []).first
abort("没有 bundleId=#{BUNDLE_ID} 的 App") if app.nil?
app_id = app['id']
puts "App: #{app.dig('attributes', 'name')} / #{app.dig('attributes', 'bundleId')} / id=#{app_id}"
puts "SKU: #{app.dig('attributes', 'sku')}, 主语言: #{app.dig('attributes', 'primaryLocale')}"

puts "\n=== 2. 测试组 (betaGroups) ==="
code, body = get("/v1/apps/#{app_id}/betaGroups?limit=50")
if code == 200
  groups = JSON.parse(body)['data'] || []
  puts "共 #{groups.size} 个组"
  groups.each do |g|
    a = g['attributes']
    puts "  - #{a['name']} | 内部组=#{a['isInternalGroup']} | 创建于 #{a['createdDate']} | id=#{g['id']}"
    c1, b1 = get("/v1/betaGroups/#{g['id']}/betaTesters?limit=200")
    emails = c1 == 200 ? (JSON.parse(b1)['data'] || []).map { |t| t.dig('attributes', 'email') } : ["查询失败 HTTP #{c1}"]
    puts "      组内测试员(#{emails.size}): #{emails.empty? ? '（空）' : emails.join(', ')}"
    c2, b2 = get("/v1/betaGroups/#{g['id']}/builds?limit=5")
    build_nums = c2 == 200 ? (JSON.parse(b2)['data'] || []).map { |b| b.dig('attributes', 'version') } : []
    puts "      组内构建: #{build_nums.empty? ? '（无）' : build_nums.join(', ')}"
  end
  puts '  ⚠️ 没有任何测试组，构建无法出现在手机 TestFlight' if groups.empty?
else
  puts "查询失败 HTTP #{code}: #{body[0, 400]}"
end

puts "\n=== 3. 最近构建及所属测试组 ==="
# apps/{id}/builds 不允许 include/sort，改用 builds 集合 + filter[app]
code, body = get("/v1/builds?filter%5Bapp%5D=#{app_id}&limit=10&sort=-uploadedDate&include=betaGroups,buildBetaDetail,preReleaseVersion")
if code == 200
  json = JSON.parse(body)
  included = (json['included'] || []).each_with_object({}) { |i, h| h[i['id']] = i }
  builds = (json['data'] || []).sort_by { |b| b.dig('attributes', 'uploadedDate').to_s }.reverse
  builds.each do |b|
    a = b['attributes']
    ids = (b.dig('relationships', 'betaGroups', 'data') || []).map { |x| x['id'] }
    names = ids.map { |i| included.dig(i, 'attributes', 'name') || i }
    detail_id = b.dig('relationships', 'buildBetaDetail', 'data', 'id')
    external_state = included.dig(detail_id, 'attributes', 'externalBuildState')
    internal_state = included.dig(detail_id, 'attributes', 'internalBuildState')
    pre_id = b.dig('relationships', 'preReleaseVersion', 'data', 'id')
    marketing = included.dig(pre_id, 'attributes', 'version') || '?'
    puts "  build #{a['version']} | 营销版本 #{marketing} | #{a['processingState']} | 上传 #{a['uploadedDate']} | 过期=#{a['expired']}"
    puts "      内部状态=#{internal_state || '?'} 外部状态=#{external_state || '?'}"
    puts "      测试组: #{names.empty? ? '（未加入任何组）' : names.join('、')}"
  end
else
  puts "查询失败 HTTP #{code}: #{body[0, 400]}"
end

puts "\n=== 4. 测试员数量 ==="
code, body = get('/v1/betaTesters?limit=5')
if code == 200
  json = JSON.parse(body)
  puts "前 5 位测试员: #{(json['data'] || []).map { |t| t.dig('attributes', 'email') }.join(', ')}"
else
  puts "查询失败 HTTP #{code}"
end
