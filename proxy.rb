#!/usr/bin/env ruby
require "webrick"
require "net/http"

PORT = (ARGV[0] || 8080).to_i
TARGET_HOST = ENV.fetch("TARGET_HOST", "localhost")
TARGET_PORT = (ENV.fetch("TARGET_PORT", "4567")).to_i

server = WEBrick::HTTPServer.new(
  Port: PORT,
  Logger: WEBrick::Log.new($stderr, WEBrick::Log::INFO),
  AccessLog: [[$stderr, WEBrick::AccessLog::COMMON_LOG_FORMAT]],
)

server.mount_proc "/" do |req, res|
  target_path = req.path
  target_path += "?#{req.query_string}" if req.query_string && !req.query_string.empty?

  target_uri = URI("http://#{TARGET_HOST}:#{TARGET_PORT}#{target_path}")

  http = Net::HTTP.new(target_uri.host, target_uri.port)
  http.open_timeout = 10
  http.read_timeout = 30

  headers = {}
  req.each do |key, val|
    next if %w[host connection].include?(key.downcase)
    headers[key] = val
  end
  headers["X-Forwarded-For"] = req.peeraddr[3]

  http_req = Net::HTTPGenericRequest.new(
    req.request_method,
    !!req.body,
    true,
    target_uri.request_uri,
    headers,
  )
  http_req.body = req.body if req.body

  http_res = http.request(http_req)

  res.status = http_res.code.to_i
  res.body = http_res.body
  http_res.each_header do |key, val|
    next if %w[transfer-encoding connection].include?(key.downcase)
    res[key] = val
  end
end

trap("INT") { server.shutdown }
trap("TERM") { server.shutdown }
server.start
