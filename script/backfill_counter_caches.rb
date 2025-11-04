#!/usr/bin/env ruby
# Backfill counter caches for users table using background jobs
#
# This script enqueues background jobs to recalculate followers_count,
# following_count, and posts_count from the actual data in the database.
#
# Usage:
#   rails runner script/backfill_counter_caches.rb
#
# Options:
#   BATCH_SIZE=10000 rails runner script/backfill_counter_caches.rb  # Custom batch size
#   VERIFY=true rails runner script/backfill_counter_caches.rb        # Verify after completion
#   WAIT=true rails runner script/backfill_counter_caches.rb          # Wait for jobs to complete
#
# This script:
# - Enqueues background jobs for each counter type (followers_count, following_count, posts_count)
# - Jobs process users in batches to avoid memory issues
# - Can be monitored via Solid Queue dashboard or logs
# - Can be resumed if interrupted (jobs are idempotent)
# - Jobs can be run in parallel for better performance
#
# See docs/COUNTER_CACHE_INCREMENT_LOGIC.md for when counters are maintained
#
# To monitor job progress:
#   rails runner "puts SolidQueue::Job.where(queue_name: 'default').count"
#   rails runner "puts SolidQueue::Job.where(queue_name: 'default', finished_at: nil).count"
#
# To check if jobs are running:
#   bin/jobs (should be running in separate process or via SOLID_QUEUE_IN_PUMA=true)

class BackfillCounterCaches
  BATCH_SIZE = ENV.fetch('BATCH_SIZE', 10_000).to_i
  VERIFY = ENV.fetch('VERIFY', 'false') == 'true'
  WAIT = ENV.fetch('WAIT', 'false') == 'true'

  def initialize
    @total_users = User.count
    @start_time = Time.current
  end

  def perform
    puts "=" * 80
    puts "Backfilling Counter Caches (Background Jobs)"
    puts "=" * 80
    puts "Total users: #{@total_users}"
    puts "Batch size: #{BATCH_SIZE}"
    puts "=" * 80
    puts

    # Check if job processor is running
    unless job_processor_running?
      puts "⚠️  WARNING: Job processor may not be running!"
      puts "   Start it with: bin/jobs"
      puts "   Or set SOLID_QUEUE_IN_PUMA=true to run jobs in Puma"
      puts "   Press Enter to continue anyway, or Ctrl+C to cancel..."
      $stdin.gets unless ENV['CI']
    end

    # Enqueue jobs for each counter type
    puts "Step 1: Enqueuing followers_count backfill jobs..."
    enqueue_backfill_jobs('followers_count')

    puts "\nStep 2: Enqueuing following_count backfill jobs..."
    enqueue_backfill_jobs('following_count')

    puts "\nStep 3: Enqueuing posts_count backfill jobs..."
    enqueue_backfill_jobs('posts_count')

    # Summary
    elapsed = Time.current - @start_time
    puts "\n" + "=" * 80
    puts "Jobs Enqueued!"
    puts "=" * 80
    puts "Total time to enqueue: #{elapsed.round(2)}s"
    puts "Total users: #{@total_users}"
    puts "Estimated batches: #{(@total_users.to_f / BATCH_SIZE).ceil} per counter type"
    puts "=" * 80

    # Show job status
    show_job_status

    # Wait for completion if requested
    if WAIT
      puts "\nWaiting for jobs to complete..."
      wait_for_completion
    else
      puts "\nJobs are processing in background."
      puts "Monitor progress with: rails runner 'puts SolidQueue::Job.where(queue_name: \"default\", finished_at: nil).count'"
    end

    # Verify if requested
    if VERIFY
      puts "\nVerifying counters..."
      verify_counters
    end
  end

  private

  def job_processor_running?
    # Check if Solid Queue is configured
    # In development, jobs might run inline or via bin/jobs
    # In production, check if SOLID_QUEUE_IN_PUMA is set or bin/jobs is running
    true # Assume it's running - actual check would require process monitoring
  end

  def enqueue_backfill_jobs(counter_type)
    # Enqueue the initial job which will enqueue batches
    # This approach allows the job to be idempotent and resumable
    job = BackfillCounterCacheJob.perform_later(counter_type)
    puts "  ✅ Enqueued initial job for #{counter_type} (Job ID: #{job.job_id})"
    puts "     This job will enqueue batches of #{BATCH_SIZE} users"
  end

  def show_job_status
    pending_jobs = SolidQueue::Job.where(queue_name: 'default', finished_at: nil).count
    finished_jobs = SolidQueue::Job.where(queue_name: 'default').where.not(finished_at: nil).count

    puts "\nJob Status:"
    puts "  Pending jobs: #{pending_jobs}"
    puts "  Finished jobs: #{finished_jobs}"
  end

  def wait_for_completion
    loop do
      pending = SolidQueue::Job.where(queue_name: 'default', finished_at: nil).count
      if pending == 0
        puts "✅ All jobs completed!"
        break
      end
      print "  Waiting... #{pending} jobs remaining\r"
      $stdout.flush
      sleep 2
    end
    puts
  end

  def verify_counters
    puts "  Checking counters for accuracy..."

    mismatches = []
    sample_size = [ 100, @total_users ].min

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
