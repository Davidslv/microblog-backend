#!/usr/bin/env ruby
# Script to purge Rack::Attack cache
# Usage: rails runner script/purge_rack_attack_cache.rb [options]
#
# Options:
#   --all          Clear all Rack::Attack cache entries
#   --ip IP        Clear cache for specific IP address
#   --user USER_ID Clear cache for specific user ID
#   --throttle NAME Clear cache for specific throttle (e.g., 'posts/create')

require 'optparse'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: rails runner script/purge_rack_attack_cache.rb [options]"

  opts.on("--all", "Clear all Rack::Attack cache entries") do
    options[:all] = true
  end

  opts.on("--ip IP", "Clear cache for specific IP address") do |ip|
    options[:ip] = ip
  end

  opts.on("--user USER_ID", "Clear cache for specific user ID") do |user_id|
    options[:user_id] = user_id
  end

  opts.on("--throttle NAME", "Clear cache for specific throttle") do |name|
    options[:throttle] = name
  end
end.parse!

puts "=" * 60
puts "Rack::Attack Cache Purge"
puts "=" * 60
puts

# Helper to delete cache keys
# Note: delete_matched was removed from Rails 8
# We can only delete specific keys or clear all cache
def delete_cache_keys(pattern)
  # Pattern matching not supported - delete specific keys or clear all
  puts "  Note: Pattern matching not supported (delete_matched removed from Rails 8)"
  puts "  Clearing all cache entries..."
  Rails.cache.clear
  puts "  ✅ All cache cleared"
  true
rescue => e
  puts "  ❌ Error: #{e.message}"
  false
end

# Main logic
if options[:all]
  puts "Clearing ALL Rack::Attack cache entries..."
  puts

  # Clear all cache (since Rack::Attack uses Rails.cache)
  Rails.cache.clear
  puts "✅ All cache cleared (including Rack::Attack)"

elsif options[:ip]
  puts "Clearing cache for IP: #{options[:ip]}"
  puts

  # Clear all throttles for this IP
  throttles = [ 'req/ip', 'posts/create', 'feed/requests', 'api/requests' ]
  throttles.each do |throttle|
    key = "rack::attack:#{throttle}:#{options[:ip]}"
    Rails.cache.delete(key)
    puts "  Deleted: #{key}"
  end
  puts "✅ Cache cleared for IP: #{options[:ip]}"

elsif options[:user_id]
  puts "Clearing cache for user: #{options[:user_id]}"
  puts

  # Clear user-specific throttles
  throttles = [ 'posts/create', 'follows/action', 'feed/requests' ]
  throttles.each do |throttle|
    key = "rack::attack:#{throttle}:#{options[:user_id]}"
    Rails.cache.delete(key)
    puts "  Deleted: #{key}"
  end
  puts "✅ Cache cleared for user: #{options[:user_id]}"

elsif options[:throttle]
  puts "Clearing cache for throttle: #{options[:throttle]}"
  puts

  # Note: This would clear all entries for this throttle
  # Since we can't pattern match, we'll need to clear all cache
  # or use a different approach
  puts "  Note: Cannot clear specific throttle without pattern matching"
  puts "  Use --all to clear all cache, or specify --ip or --user"

else
  puts "No options specified. Available options:"
  puts
  puts "  --all                    Clear all Rack::Attack cache"
  puts "  --ip IP                   Clear cache for specific IP"
  puts "  --user USER_ID            Clear cache for specific user"
  puts "  --throttle NAME           Clear cache for specific throttle"
  puts
  puts "Examples:"
  puts "  rails runner script/purge_rack_attack_cache.rb --all"
  puts "  rails runner script/purge_rack_attack_cache.rb --ip 127.0.0.1"
  puts "  rails runner script/purge_rack_attack_cache.rb --user 123"
end

puts
puts "=" * 60
puts "Done!"
puts "=" * 60
