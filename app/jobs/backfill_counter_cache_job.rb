class BackfillCounterCacheJob < ApplicationJob
  queue_as :default

  # Process users in batches to avoid memory issues
  # Each job processes one counter type for a batch of users
  BATCH_SIZE = 10_000

  def perform(counter_type, user_ids = nil)
    case counter_type.to_s
    when "followers_count"
      backfill_followers_count(user_ids)
    when "following_count"
      backfill_following_count(user_ids)
    when "posts_count"
      backfill_posts_count(user_ids)
    else
      raise ArgumentError, "Unknown counter type: #{counter_type}"
    end
  end

  private

  def backfill_followers_count(user_ids = nil)
    if user_ids
      # Process specific user IDs (batch)
      # Use ActiveRecord's sanitize_sql to prevent SQL injection
      sanitized_ids = user_ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(",")
      sql = <<-SQL
        UPDATE users
        SET followers_count = (
          SELECT COUNT(*)
          FROM follows
          WHERE follows.followed_id = users.id
        )
        WHERE users.id IN (#{sanitized_ids})
      SQL

      ActiveRecord::Base.connection.execute(sql)
      Rails.logger.info "Backfilled followers_count for #{user_ids.size} users"
    else
      # Enqueue batches for all users
      total_batches = (User.count.to_f / BATCH_SIZE).ceil
      batch_num = 0

      User.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        batch_num += 1
        user_ids = batch.pluck(:id)
        BackfillCounterCacheJob.perform_later("followers_count", user_ids)
        Rails.logger.info "Enqueued followers_count batch #{batch_num}/#{total_batches}"
      end
      Rails.logger.info "Enqueued #{total_batches} followers_count backfill jobs"
    end
  end

  def backfill_following_count(user_ids = nil)
    if user_ids
      # Process specific user IDs (batch)
      sanitized_ids = user_ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(",")
      sql = <<-SQL
        UPDATE users
        SET following_count = (
          SELECT COUNT(*)
          FROM follows
          WHERE follows.follower_id = users.id
        )
        WHERE users.id IN (#{sanitized_ids})
      SQL

      ActiveRecord::Base.connection.execute(sql)
      Rails.logger.info "Backfilled following_count for #{user_ids.size} users"
    else
      # Enqueue batches for all users
      total_batches = (User.count.to_f / BATCH_SIZE).ceil
      batch_num = 0

      User.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        batch_num += 1
        user_ids = batch.pluck(:id)
        BackfillCounterCacheJob.perform_later("following_count", user_ids)
        Rails.logger.info "Enqueued following_count batch #{batch_num}/#{total_batches}"
      end
      Rails.logger.info "Enqueued #{total_batches} following_count backfill jobs"
    end
  end

  def backfill_posts_count(user_ids = nil)
    if user_ids
      # Process specific user IDs (batch)
      sanitized_ids = user_ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(",")
      sql = <<-SQL
        UPDATE users
        SET posts_count = (
          SELECT COUNT(*)
          FROM posts
          WHERE posts.author_id = users.id
        )
        WHERE users.id IN (#{sanitized_ids})
      SQL

      ActiveRecord::Base.connection.execute(sql)
      Rails.logger.info "Backfilled posts_count for #{user_ids.size} users"
    else
      # Enqueue batches for all users
      total_batches = (User.count.to_f / BATCH_SIZE).ceil
      batch_num = 0

      User.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        batch_num += 1
        user_ids = batch.pluck(:id)
        BackfillCounterCacheJob.perform_later("posts_count", user_ids)
        Rails.logger.info "Enqueued posts_count batch #{batch_num}/#{total_batches}"
      end
      Rails.logger.info "Enqueued #{total_batches} posts_count backfill jobs"
    end
  end
end
