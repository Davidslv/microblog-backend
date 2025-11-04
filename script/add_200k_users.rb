#!/usr/bin/env ruby
# Fast script to add 200,000 users with follow relationships
# Usage: rails runner script/add_200k_users.rb
#
# This script is optimized for large-scale bulk insertion:
# - Uses bulk inserts (insert_all) for maximum performance
# - Pre-generates password hash to avoid repeated bcrypt calls
# - Batches operations for efficiency
# - All new users follow User.first

require 'securerandom'

puts "Starting bulk user creation (200,000 users)..."
puts "This may take several minutes..."
start_time = Time.current

# Get the first user (all new users will follow this user)
target_user = User.first
if target_user.nil?
  puts "❌ Error: No users exist. Please create at least one user first."
  exit 1
end

puts "Target user: #{target_user.username} (ID: #{target_user.id})"
puts "All new users will follow this user"

# Get existing users for random follows (excluding target_user)
puts "Loading existing users..."
existing_user_ids = User.where.not(id: target_user.id).pluck(:id)
puts "Existing users to follow: #{existing_user_ids.count}"

# Configuration
NEW_USERS_COUNT = 200_000
BATCH_SIZE = 2000  # Larger batch size for better performance
MIN_FOLLOWS_PER_USER = 10
MAX_FOLLOWS_PER_USER = 100

# Pre-generate password hash once (all users get same password)
puts "\nPre-generating password hash..."
password_hash = BCrypt::Password.create('password123', cost: 4)
current_time = Time.current

# Create users in batches
puts "\nCreating #{NEW_USERS_COUNT} users in batches of #{BATCH_SIZE}..."
puts "This will create #{NEW_USERS_COUNT / BATCH_SIZE} batches\n"

users_created = 0
new_user_ids = []
max_existing_id = User.maximum(:id) || 0
batch_start_time = Time.current

(NEW_USERS_COUNT.to_f / BATCH_SIZE).ceil.times do |batch|
  batch_size = [BATCH_SIZE, NEW_USERS_COUNT - users_created].min
  
  # Generate user data
  users_data = []
  batch_size.times do |i|
    global_index = users_created + i
    username = "bulk_user_#{global_index}_#{SecureRandom.hex(6)}"
    
    users_data << {
      username: username,
      password_digest: password_hash,
      description: nil, # Skip description for speed
      created_at: current_time,
      updated_at: current_time
    }
  end
  
  # Bulk insert users
  User.insert_all(users_data)
  
  # Get the IDs efficiently (they're sequential)
  first_id = max_existing_id + 1
  batch_ids = (first_id..(first_id + batch_size - 1)).to_a
  max_existing_id += batch_size
  
  new_user_ids.concat(batch_ids)
  users_created += batch_size
  
  # Progress update
  elapsed = Time.current - batch_start_time
  rate = users_created / elapsed
  remaining = (NEW_USERS_COUNT - users_created) / rate rescue 0
  
  print "  Batch #{batch + 1}: #{users_created}/#{NEW_USERS_COUNT} users (#{rate.round(0)} users/sec, ETA: #{remaining.round(0)}s)\r"
  $stdout.flush
end

puts "\n✅ Created #{users_created} users"
puts "   User IDs range: #{new_user_ids.min} - #{new_user_ids.max}"

# Create follow relationships
puts "\nCreating follow relationships..."

# All new users follow User.first
puts "  Step 1: All new users follow User.first (#{target_user.id})..."
puts "  This will create #{new_user_ids.count} follow relationships..."

follows_to_target = new_user_ids.map do |user_id|
  {
    follower_id: user_id,
    followed_id: target_user.id,
    created_at: current_time,
    updated_at: current_time
  }
end

# Insert in batches to avoid memory issues
FOLLOW_BATCH_SIZE = 10_000
follows_to_target.each_slice(FOLLOW_BATCH_SIZE).with_index do |batch, index|
  Follow.insert_all(batch)
  print "  Inserted batch #{index + 1}: #{(index + 1) * FOLLOW_BATCH_SIZE}/#{follows_to_target.count}\r"
  $stdout.flush
end

puts "\n  ✅ Created #{follows_to_target.count} follows to User.first"

# Random follows among new users and existing users
puts "  Step 2: Adding random follows (10-100 per user)..."
puts "  This may take a while..."
total_follows = 0
follows_batch = []
INSERT_BATCH_SIZE = 10_000  # Larger batch for better performance

# Pre-build all available user IDs (excluding target_user for now, will add separately)
all_available_ids = (new_user_ids + existing_user_ids).freeze
puts "  Available users to follow: #{all_available_ids.count}"

# Progress tracking
follows_start_time = Time.current
processed_users = 0

new_user_ids.each do |follower_id|
  # Random number of follows for this user
  num_follows = rand(MIN_FOLLOWS_PER_USER..MAX_FOLLOWS_PER_USER)
  
  # Randomly select users to follow (excluding self)
  available_users = all_available_ids.reject { |id| id == follower_id }
  followed_users = available_users.sample([num_follows, available_users.size].min)
  
  followed_users.each do |followed_id|
    follows_batch << {
      follower_id: follower_id,
      followed_id: followed_id,
      created_at: current_time,
      updated_at: current_time
    }
    
    # Insert in batches
    if follows_batch.size >= INSERT_BATCH_SIZE
      Follow.insert_all(follows_batch)
      total_follows += follows_batch.size
      follows_batch = []
      
      # Progress update
      processed_users += 1
      elapsed = Time.current - follows_start_time
      rate = total_follows / elapsed rescue 0
      remaining_users = new_user_ids.count - processed_users
      avg_follows_per_user = total_follows.to_f / processed_users rescue 0
      estimated_remaining = (remaining_users * avg_follows_per_user) / rate rescue 0
      
      print "    Processed #{processed_users}/#{new_user_ids.count} users, #{total_follows} follows (#{rate.round(0)}/sec, ETA: #{estimated_remaining.round(0)}s)\r"
      $stdout.flush
    end
  end
  
  processed_users += 1
end

# Insert remaining follows
if follows_batch.any?
  Follow.insert_all(follows_batch)
  total_follows += follows_batch.size
end

puts "\n  ✅ Created #{total_follows} random follows"

# Summary
end_time = Time.current
duration = end_time - start_time

puts "\n" + "="*70
puts "Summary:"
puts "="*70
puts "Users created:          #{users_created}"
puts "Follows to User.first: #{follows_to_target.count}"
puts "Random follows:         #{total_follows}"
puts "Total follows created:  #{follows_to_target.count + total_follows}"
puts "Execution time:         #{duration.round(2)}s (#{(duration / 60).round(2)} minutes)"
puts "Users per second:       #{(users_created / duration).round(2)}"
puts "Follows per second:     #{((follows_to_target.count + total_follows) / duration).round(2)}"
puts "="*70

# Verify
puts "\nVerification:"
target_user.reload
puts "User.first followers:    #{target_user.followers.count}"
puts "User.first following:   #{target_user.following.count}"
puts "Total users in DB:      #{User.count}"
puts "Total follows in DB:    #{Follow.count}"
puts "\n✅ Done!"

