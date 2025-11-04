#!/usr/bin/env ruby
# Script to backfill feed entries for existing users and posts
# This is used during the initial migration to fan-out on write
#
# Usage:
#   rails runner script/backfill_existing_feeds.rb
#   rails runner script/backfill_existing_feeds.rb --batch-size 1000
#   rails runner script/backfill_existing_feeds.rb --user-id 123
#   rails runner script/backfill_existing_feeds.rb --dry-run
#
# Options:
#   --batch-size N    Process users in batches of N (default: 100)
#   --user-id ID      Only backfill for specific user
#   --dry-run         Show what would be done without actually doing it
#   --verbose         Show progress details

require 'optparse'
require 'benchmark'

options = {
  batch_size: 100,
  user_id: nil,
  dry_run: false,
  verbose: false
}

OptionParser.new do |opts|
  opts.banner = "Usage: rails runner script/backfill_existing_feeds.rb [options]"

  opts.on("--batch-size N", Integer, "Process users in batches of N (default: 100)") do |n|
    options[:batch_size] = n
  end

  opts.on("--user-id ID", Integer, "Only backfill for specific user") do |id|
    options[:user_id] = id
  end

  opts.on("--dry-run", "Show what would be done without actually doing it") do
    options[:dry_run] = true
  end

  opts.on("--verbose", "Show progress details") do
    options[:verbose] = true
  end
end.parse!

puts "=" * 60
puts "Feed Entries Backfill Script"
puts "=" * 60
puts
puts "Options:"
puts "  Batch size: #{options[:batch_size]}"
puts "  User ID: #{options[:user_id] || 'all users'}"
puts "  Dry run: #{options[:dry_run] ? 'YES' : 'NO'}"
puts "  Verbose: #{options[:verbose] ? 'YES' : 'NO'}"
puts

# Statistics
stats = {
  users_processed: 0,
  posts_processed: 0,
  feed_entries_created: 0,
  errors: 0
}

# Process users
users_to_process = if options[:user_id]
  User.where(id: options[:user_id])
else
  User.all
end

total_users = users_to_process.count
puts "Processing #{total_users} users..."
puts

start_time = Time.current

users_to_process.find_in_batches(batch_size: options[:batch_size]) do |batch|
  batch.each do |user|
    begin
      stats[:users_processed] += 1

      if options[:verbose]
        puts "Processing user #{user.id} (#{stats[:users_processed]}/#{total_users})..."
      end

      # Get all users this user follows
      followed_users = user.following

      if followed_users.empty?
        puts "  User #{user.id}: No follows, skipping" if options[:verbose]
        next
      end

      # For each followed user, backfill their recent posts
      followed_users.each do |followed|
        # Get recent top-level posts (last 50)
        posts = Post.where(author_id: followed.id, parent_id: nil)
                    .order(created_at: :desc)
                    .limit(50)

        next if posts.empty?

        if options[:dry_run]
          puts "  Would create #{posts.count} feed entries for user #{user.id} from author #{followed.id}" if options[:verbose]
          stats[:feed_entries_created] += posts.count
        else
          # Create feed entries
          entries = posts.map do |post|
            {
              user_id: user.id,
              post_id: post.id,
              author_id: followed.id,
              created_at: post.created_at,
              updated_at: post.created_at
            }
          end

          # Bulk insert in batches
          entries.each_slice(1000) do |batch|
            begin
              FeedEntry.insert_all(batch) if batch.any?
              stats[:feed_entries_created] += batch.size
              stats[:posts_processed] += batch.size
            rescue ActiveRecord::RecordNotUnique
              # Ignore duplicates
              stats[:feed_entries_created] += batch.size
            end
          end
        end
      end

      # Progress update
      if stats[:users_processed] % 10 == 0
        puts "Progress: #{stats[:users_processed]}/#{total_users} users, #{stats[:feed_entries_created]} entries created"
      end

    rescue => e
      stats[:errors] += 1
      puts "ERROR processing user #{user.id}: #{e.message}"
      puts e.backtrace.first(3).join("\n") if options[:verbose]
    end
  end
end

elapsed = Time.current - start_time

puts
puts "=" * 60
puts "Backfill Complete!"
puts "=" * 60
puts
puts "Statistics:"
puts "  Users processed: #{stats[:users_processed]}"
puts "  Posts processed: #{stats[:posts_processed]}"
puts "  Feed entries created: #{stats[:feed_entries_created]}"
puts "  Errors: #{stats[:errors]}"
puts "  Time elapsed: #{elapsed.round(2)}s"
puts "  Average: #{(elapsed / stats[:users_processed]).round(2)}s per user" if stats[:users_processed] > 0
puts

if options[:dry_run]
  puts "DRY RUN - No changes were made"
  puts "Run without --dry-run to actually create feed entries"
else
  puts "Feed entries have been created!"
  puts "Users can now use the fast feed query path."
end

puts
puts "Next steps:"
puts "1. Verify feed entries: SELECT COUNT(*) FROM feed_entries;"
puts "2. Test feed queries: rails runner 'puts User.first.feed_posts.count'"
puts "3. Monitor performance improvements"
