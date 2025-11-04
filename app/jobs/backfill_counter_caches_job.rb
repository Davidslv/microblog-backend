class BackfillCounterCachesJob < ApplicationJob
  queue_as :default

  # This job triggers a full backfill of all counter caches
  # It enqueues BackfillCounterCacheJob for each counter type
  # which then processes users in batches
  def perform
    Rails.logger.info "Starting periodic counter cache backfill..."

    # Enqueue initial jobs for each counter type
    # These will then enqueue batch jobs for all users
    BackfillCounterCacheJob.perform_later("followers_count")
    BackfillCounterCacheJob.perform_later("following_count")
    BackfillCounterCacheJob.perform_later("posts_count")

    Rails.logger.info "Enqueued counter cache backfill jobs for all counter types"
  end
end

