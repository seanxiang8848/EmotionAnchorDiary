#!/usr/bin/env ruby
# 把指定构建提交 Beta 审核（外部测试必需）。
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
  req = verb == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
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
puts "目标构建: #{build.dig('attributes', 'version')} (#{build.dig('attributes', 'processingState')})"

code, body = call(:post, '/v1/betaAppReviewSubmissions',
                  { 'data' => {
                    'type' => 'betaAppReviewSubmissions',
                    'relationships' => { 'build' => { 'data' => { 'type' => 'builds', 'id' => build['id'] } } }
                  } })
if code >= 200 && code < 300
  puts '已提交 Beta 审核。审核通过后手机 TestFlight 会收到更新。'
elsif code == 409
  puts '该构建已在审核流程中或已通过，无需重复提交。'
  puts body[0, 400]
else
  puts "提交失败 HTTP #{code}\n#{body[0, 800]}"
end
