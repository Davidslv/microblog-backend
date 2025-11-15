#!/usr/bin/env ruby
# Script to test HTTP compression
# Usage: bin/rails runner script/test_compression.rb

require 'net/http'
require 'uri'

def test_compression(endpoint, description)
  uri = URI(endpoint)
  http = Net::HTTP.new(uri.host, uri.port)

  # Request with compression support
  request = Net::HTTP::Get.new(uri.path)
  request['Accept-Encoding'] = 'gzip, deflate'

  response = http.request(request)

  puts "\n#{description}"
  puts "=" * 60
  puts "Endpoint: #{endpoint}"
  puts "Status: #{response.code}"
  puts "Content-Encoding: #{response['Content-Encoding'] || 'none'}"
  puts "Content-Type: #{response['Content-Type']}"
  puts "Content-Length: #{response['Content-Length'] || 'chunked'}"
  puts "Vary: #{response['Vary'] || 'not set'}"

  if response['Content-Encoding'] == 'gzip'
    puts "✅ Compression: ENABLED"

    # Calculate compression ratio if Content-Length is available
    if response['Content-Length']
      compressed_size = response['Content-Length'].to_i
      # Note: We can't easily get uncompressed size without decompressing
      puts "   Compressed size: #{compressed_size} bytes"
    end
  else
    puts "❌ Compression: NOT ENABLED"
    puts "   Possible reasons:"
    puts "   - Response too small (<860 bytes, Rack::Deflater default)"
    puts "   - Content type not in compressible list"
    puts "   - Health check endpoint (/up) excluded"
  end

  puts "-" * 60
end

# Test various endpoints
base_url = ENV.fetch('API_URL', 'http://localhost:3000')

puts "\n🔍 Testing HTTP Compression"
puts "=" * 60
puts "Base URL: #{base_url}"
puts "Make sure the Rails server is running!"
puts "=" * 60

# Test health check (should NOT be compressed - small response)
test_compression("#{base_url}/up", "Health Check Endpoint")

# Test API endpoint (should be compressed if response is large enough)
test_compression("#{base_url}/api/v1/posts", "API Posts Endpoint")

# Test with authentication if needed
# You may need to add a JWT token for authenticated endpoints
# test_compression("#{base_url}/api/v1/me", "Authenticated Endpoint")

puts "\n💡 Tips:"
puts "- Compression only works for responses >860 bytes (Rack::Deflater default)"
puts "- Check browser DevTools Network tab: look for 'Content-Encoding: gzip'"
puts "- Compare 'Size' vs 'Transferred' columns in browser DevTools"
puts "- Use: curl -H 'Accept-Encoding: gzip' -v #{base_url}/api/v1/posts"
puts "\n"
