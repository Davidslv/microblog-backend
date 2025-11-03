#!/usr/bin/env ruby
# Load test data seeding script
# Creates realistic test data for load testing
#
# Usage:
#   rails runner script/load_test_seed.rb
#
# Environment variables:
#   NUM_USERS=1000 rails runner script/load_test_seed.rb
#   POSTS_PER_USER=50 rails runner script/load_test_seed.rb

require 'securerandom'

# Configuration
NUM_USERS = ENV.fetch('NUM_USERS', '1000').to_i
POSTS_PER_USER = ENV.fetch('POSTS_PER_USER', '150').to_i
MIN_FOLLOWS = 10
MAX_FOLLOWS = 5000
MIN_REPLIES = 0
MAX_REPLIES = 30
REPLY_PROBABILITY = 0.3  # 30% of posts are replies

puts "=" * 80
puts "Load Test Data Seeding"
puts "=" * 80
puts "Users: #{NUM_USERS}"
puts "Posts per user: #{POSTS_PER_USER}"
puts "Following range: #{MIN_FOLLOWS} to #{MAX_FOLLOWS}"
puts "Replies range: #{MIN_REPLIES} to #{MAX_REPLIES}"
puts "=" * 80
puts ""

# Clear existing data (optional - comment out if you want to keep existing)
puts "Clearing existing data..."
Follow.delete_all
Post.delete_all
User.delete_all
puts "Done.\n\n"

# Create users
puts "Creating #{NUM_USERS} users..."
users = []
NUM_USERS.times do |i|
  user = User.create!(
    username: "user#{i + 1}",
    description: i % 3 == 0 ? "Test user #{i + 1} description" : nil,
    password: "password123",
    password_confirmation: "password123"
  )
  users << user

  if (i + 1) % 100 == 0
    puts "  Created #{i + 1} users..."
  end
end
puts "✓ Created #{users.size} users\n\n"

# Create posts
total_posts = NUM_USERS * POSTS_PER_USER
puts "Creating #{total_posts} posts..."
posts_created = 0
top_level_posts = []

users.each_with_index do |user, user_index|
  rand(POSTS_PER_USER).times do |post_index|
    # Determine if this is a reply
    is_reply = (post_index > 0 && rand < REPLY_PROBABILITY && top_level_posts.any?)

    parent_id = nil
    if is_reply
      # Reply to a random existing post
      parent_post = top_level_posts.sample
      parent_id = parent_post.id
    end

    # Create post with realistic content
    content = if is_reply
      "Reply to post #{parent_id}: This is reply #{post_index} from #{user.username}"
    else
      "Post #{post_index + 1} from #{user.username}: #{SecureRandom.alphanumeric(50)}"
    end

    # Ensure content is within limit
    content = content[0..199]

    post = Post.create!(
      author: user,
      content: content,
      parent_id: parent_id,
      created_at: rand(365.days).seconds.ago  # Random time in last year
    )

    top_level_posts << post unless is_reply
    posts_created += 1

    if posts_created % 1000 == 0
      puts "  Created #{posts_created} posts..."
    end
  end
end
puts "✓ Created #{posts_created} posts\n\n"

# Create follow relationships
puts "Creating follow relationships..."
total_follows = 0

users.each_with_index do |follower, follower_index|
  # Each user follows a random number of other users
  num_follows = rand(MIN_FOLLOWS..MAX_FOLLOWS)

  # Get random users to follow (excluding self)
  users_to_follow = (users - [follower]).sample(num_follows)

  users_to_follow.each do |followed|
    begin
      Follow.create!(
        follower_id: follower.id,
        followed_id: followed.id,
        created_at: rand(365.days).seconds.ago
      )
      total_follows += 1
    rescue ActiveRecord::RecordNotUnique
      # Already following, skip
    end
  end

  if (follower_index + 1) % 100 == 0
    puts "  Processed #{follower_index + 1} users, created #{total_follows} follows..."
  end
end
puts "✓ Created #{total_follows} follow relationships\n\n"

# Print summary
puts "=" * 80
puts "Summary"
puts "=" * 80
puts "Users: #{User.count}"
puts "Posts: #{Post.count} (#{Post.top_level.count} top-level, #{Post.replies.count} replies)"
puts "Follows: #{Follow.count}"
puts "Average follows per user: #{Follow.count.to_f / User.count}"
puts "Average posts per user: #{Post.count.to_f / User.count}"
puts "Average replies per top-level post: #{Post.top_level.count > 0 ? (Post.replies.count.to_f / Post.top_level.count).round(2) : 0}"
puts "=" * 80
puts ""
puts "Database size:"
puts `du -sh storage/#{Rails.env}.sqlite3` if File.exist?("storage/#{Rails.env}.sqlite3")
puts ""
puts "✓ Seeding complete!"
puts ""
puts "You can now run load tests:"
puts "  k6 run load_test/k6_baseline.js"
puts "  k6 run load_test/k6_comprehensive.js"

