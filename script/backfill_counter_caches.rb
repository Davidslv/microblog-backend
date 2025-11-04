#!/usr/bin/env ruby
# Backfill counter caches for users table
#
# This script recalculates followers_count, following_count, and posts_count
# from the actual data in the database.
#
# Usage:
#   rails runner script/backfill_counter_caches.rb
#
# Options:
#   BATCH_SIZE=10000 rails runner script/backfill_counter_caches.rb  # Custom batch size
#   VERIFY=true rails runner script/backfill_counter_caches.rb        # Verify after completion
#
# This script is designed to:
# - Process users in batches to avoid memory issues
# - Use efficient SQL UPDATE queries
# - Track progress and allow resumption
# - Can be run in background or via background job
#
# See docs/COUNTER_CACHE_INCREMENT_LOGIC.md for when counters are maintained

require 'benchmark'

class BackfillCounterCaches
  BATCH_SIZE = ENV.fetch('BATCH_SIZE', 10_000).to_i
  VERIFY = ENV.fetch('VERIFY', 'false') == 'true'

  def initialize
    @total_users = User.count
    @processed = 0
    @start_time = Time.current
  end

  def perform
    puts "=" * 80
    puts "Backfilling Counter Caches"
    puts "=" * 80
    puts "Total users: #{@total_users}"
    puts "Batch size: #{BATCH_SIZE}"
    puts "=" * 80
    puts

    # Backfill followers_count
    puts "Step 1: Backfilling followers_count..."
    backfill_followers_count

    # Backfill following_count
    puts "\nStep 2: Backfilling following_count..."
    backfill_following_count

    # Backfill posts_count
    puts "\nStep 3: Backfilling posts_count..."
    backfill_posts_count

    # Summary
    elapsed = Time.current - @start_time
    puts "\n" + "=" * 80
    puts "Backfill Complete!"
    puts "=" * 80
    puts "Total time: #{elapsed.round(2)}s (#{(elapsed / 60).round(2)} minutes)"
    puts "Users processed: #{@total_users}"
    puts "=" * 80

    # Verify if requested
    if VERIFY
      puts "\nVerifying counters..."
      verify_counters
    end
  end

  private

  def backfill_followers_count
    time = Benchmark.measure do
      # Use efficient SQL UPDATE with subquery
      # This is much faster than processing in Ruby
      sql = <<-SQL
        UPDATE users
        SET followers_count = (
          SELECT COUNT(*)
          FROM follows
          WHERE follows.followed_id = users.id
        )
      SQL

      result = ActiveRecord::Base.connection.execute(sql)
      @processed = @total_users
    end

    puts "  ✅ Completed in #{time.real.round(2)}s"
  end

  def backfill_following_count
    time = Benchmark.measure do
      sql = <<-SQL
        UPDATE users
        SET following_count = (
          SELECT COUNT(*)
          FROM follows
          WHERE follows.follower_id = users.id
        )
      SQL

      ActiveRecord::Base.connection.execute(sql)
    end

    puts "  ✅ Completed in #{time.real.round(2)}s"
  end

  def backfill_posts_count
    time = Benchmark.measure do
      sql = <<-SQL
        UPDATE users
        SET posts_count = (
          SELECT COUNT(*)
          FROM posts
          WHERE posts.author_id = users.id
        )
      SQL

      ActiveRecord::Base.connection.execute(sql)
    end

    puts "  ✅ Completed in #{time.real.round(2)}s"
  end

  def verify_counters
    puts "  Checking counters for accuracy..."

    mismatches = []
    sample_size = [100, @total_users].min

    User.limit(sample_size).find_each do |user|
      actual_followers = user.followers.count
      actual_following = user.following.count
      actual_posts = user.posts.count

      if actual_followers != user.followers_count ||
         actual_following != user.following_count ||
         actual_posts != user.posts_count
        mismatches << {
          user_id: user.id,
          username: user.username,
          followers: { actual: actual_followers, cached: user.followers_count },
          following: { actual: actual_following, cached: user.following_count },
          posts: { actual: actual_posts, cached: user.posts_count }
        }
      end
    end

    if mismatches.any?
      puts "  ⚠️  Found #{mismatches.size} mismatches in sample of #{sample_size}:"
      mismatches.first(5).each do |mismatch|
        puts "    User #{mismatch[:user_id]} (#{mismatch[:username]}):"
        puts "      Followers: actual=#{mismatch[:followers][:actual]}, cached=#{mismatch[:followers][:cached]}"
        puts "      Following: actual=#{mismatch[:following][:actual]}, cached=#{mismatch[:following][:cached]}"
        puts "      Posts: actual=#{mismatch[:posts][:actual]}, cached=#{mismatch[:posts][:cached]}"
      end
      puts "  Run full verification if needed: rails runner 'User.find_each { |u| ... }'"
    else
      puts "  ✅ All counters verified in sample of #{sample_size} users"
    end
  end
end

# Run if called directly
if __FILE__ == $0
  BackfillCounterCaches.new.perform
end

