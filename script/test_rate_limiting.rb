#!/usr/bin/env ruby
# Script to test rate limiting functionality
# Usage: rails runner script/test_rate_limiting.rb

require 'net/http'
require 'uri'

puts "=" * 60
puts "Rate Limiting Test"
puts "=" * 60
puts

# Test configuration
base_url = ENV['BASE_URL'] || 'http://localhost:3000'
test_ip = '127.0.0.1'

puts "Testing rate limits against: #{base_url}"
puts "Test IP: #{test_ip}"
puts

# Helper to make HTTP request
def make_request(url, headers = {})
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Get.new(uri.path)

  headers.each { |key, value| request[key] = value }

  begin
    response = http.request(request)
    {
      code: response.code.to_i,
      headers: response.to_hash,
      rate_limit_limit: response['X-RateLimit-Limit'],
      rate_limit_remaining: response['X-RateLimit-Remaining'],
      rate_limit_reset: response['X-RateLimit-Reset'],
      retry_after: response['Retry-After']
    }
  rescue => e
    { error: e.message }
  end
end

# Test 1: General IP rate limit (300 requests per 5 minutes)
puts "1. Testing General IP Rate Limit (300 req/5min)"
puts "-" * 60
puts "Making 5 rapid requests to test throttling..."
puts

(1..5).each do |i|
  result = make_request("#{base_url}/", { 'X-Forwarded-For' => test_ip })
  if result[:error]
    puts "  Request #{i}: ERROR - #{result[:error]}"
  else
    puts "  Request #{i}: Status #{result[:code]} | Remaining: #{result[:rate_limit_remaining] || 'N/A'}"
    if result[:code] == 429
      puts "    ⚠️  Rate limit exceeded!"
      puts "    Retry-After: #{result[:retry_after]} seconds"
    end
  end
  sleep 0.1
end
puts

# Test 2: Feed request rate limit (100 req/min)
puts "2. Testing Feed Request Rate Limit (100 req/min)"
puts "-" * 60
puts "Making 5 feed requests..."
puts

(1..5).each do |i|
  result = make_request("#{base_url}/posts", { 'X-Forwarded-For' => test_ip })
  if result[:error]
    puts "  Feed Request #{i}: ERROR - #{result[:error]}"
  else
    puts "  Feed Request #{i}: Status #{result[:code]}"
    if result[:code] == 429
      puts "    ⚠️  Feed rate limit exceeded!"
    end
  end
  sleep 0.1
end
puts

# Test 3: Verify rate limit headers
puts "3. Checking Rate Limit Headers"
puts "-" * 60
result = make_request("#{base_url}/", { 'X-Forwarded-For' => test_ip })
if result[:error]
  puts "  ERROR: #{result[:error]}"
else
  puts "  X-RateLimit-Limit: #{result[:rate_limit_limit] || 'Not set'}"
  puts "  X-RateLimit-Remaining: #{result[:rate_limit_remaining] || 'Not set'}"
  puts "  X-RateLimit-Reset: #{result[:rate_limit_reset] || 'Not set'}"
  puts "  Retry-After: #{result[:retry_after] || 'Not set'}"
end
puts

# Test 4: Check Rack::Attack configuration
puts "4. Rack::Attack Configuration"
puts "-" * 60
begin
  puts "  Enabled: #{Rack::Attack.enabled}"
  puts "  Cache Store: #{Rack::Attack.cache.store.class.name}"
  puts "  ✅ Rack::Attack is configured"
rescue => e
  puts "  ❌ Error checking configuration: #{e.message}"
end
puts

puts "=" * 60
puts "Test Complete!"
puts "=" * 60
puts
puts "Note: To test rate limiting properly:"
puts "1. Start your Rails server: rails server"
puts "2. Run this script: rails runner script/test_rate_limiting.rb"
puts "3. Make many rapid requests to trigger rate limits"
puts "4. Check for 429 responses with rate limit headers"

