#!/usr/bin/env ruby
# Fast script to add 15,000 users with follow relationships
# Usage: rails runner script/add_15k_users.rb

require 'securerandom'

puts "Starting bulk user creation..."
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
existing_user_ids = User.where.not(id: target_user.id).pluck(:id)
puts "Existing users to follow: #{existing_user_ids.count}"

# Configuration
NEW_USERS_COUNT = 15_000
BATCH_SIZE = 1000
MIN_FOLLOWS_PER_USER = 10
MAX_FOLLOWS_PER_USER = 100

# Pre-generate password hash once (all users get same password)
password_hash = BCrypt::Password.create('password123', cost: 4)
current_time = Time.current

# Create users in batches
puts "\nCreating #{NEW_USERS_COUNT} users in batches of #{BATCH_SIZE}..."

users_created = 0
new_user_ids = []
max_existing_id = User.maximum(:id) || 0

(NEW_USERS_COUNT.to_f / BATCH_SIZE).ceil.times do |batch|
  batch_size = [BATCH_SIZE, NEW_USERS_COUNT - users_created].min
  
  # Generate user data
  users_data = []
  batch_size.times do |i|
    global_index = users_created + i
    username = "bulk_user_#{global_index}_#{SecureRandom.hex(4)}"
    
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
  
  print "  Created batch #{batch + 1}: #{users_created}/#{NEW_USERS_COUNT} users\r"
  $stdout.flush
end

puts "\n✅ Created #{users_created} users"
puts "   User IDs range: #{new_user_ids.min} - #{new_user_ids.max}"

# Create follow relationships
puts "\nCreating follow relationships..."

# All new users follow User.first
puts "  Step 1: All new users follow User.first (#{target_user.id})..."
follows_to_target = new_user_ids.map do |user_id|
  {
    follower_id: user_id,
    followed_id: target_user.id,
    created_at: Time.current,
    updated_at: Time.current
  }
end

Follow.insert_all(follows_to_target)
puts "  ✅ Created #{follows_to_target.count} follows to User.first"

# Random follows among new users and existing users
puts "  Step 2: Adding random follows (10-100 per user)..."
total_follows = 0
follows_batch = []
INSERT_BATCH_SIZE = 5000

# Pre-build all available user IDs (excluding target_user for now, will add separately)
all_available_ids = (new_user_ids + existing_user_ids).freeze

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
      print "    Created #{total_follows} random follows...\r"
      $stdout.flush
    end
  end
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

puts "\n" + "="*60
puts "Summary:"
puts "="*60
puts "Users created:      #{users_created}"
puts "Follows to User.first: #{follows_to_target.count}"
puts "Random follows:     #{total_follows}"
puts "Total follows:      #{follows_to_target.count + total_follows}"
puts "Execution time:     #{duration.round(2)}s"
puts "Users per second:   #{(users_created / duration).round(2)}"
puts "Follows per second: #{((follows_to_target.count + total_follows) / duration).round(2)}"
puts "="*60

# Verify
puts "\nVerification:"
target_user.reload
puts "User.first followers: #{target_user.followers.count}"
puts "User.first following: #{target_user.following.count}"
puts "\n✅ Done!"

