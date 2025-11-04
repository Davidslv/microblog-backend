# Backfilling Counter Caches

## Overview

Counter caches (`followers_count`, `following_count`, `posts_count`) are automatically maintained by ActiveRecord callbacks when records are created/destroyed through normal application flow. However, counters may become stale if:

- Data is inserted via bulk operations (`insert_all`)
- Direct SQL operations bypass ActiveRecord callbacks
- Counters were not initialized when the migration ran

This document explains how to backfill counter caches using background jobs.

---

## Background Job Processing

We use **Solid Queue** (Rails 8's built-in job processor) to backfill counters in the background. This approach offers:

- ✅ **Non-blocking**: Doesn't block deployments or database operations
- ✅ **Resumable**: Can be interrupted and resumed
- ✅ **Monitorable**: Track progress via job status
- ✅ **Scalable**: Can process in parallel batches
- ✅ **Safe**: Uses parameterized queries to prevent SQL injection

---

## Prerequisites

### 1. Ensure Job Processor is Running

**Option A: Run jobs in Puma (Development/Production)**
```bash
# Set in environment or config
export SOLID_QUEUE_IN_PUMA=true
```

**Option B: Run jobs in separate process**
```bash
# In a separate terminal
bin/jobs
```

### 2. Verify Migration is Applied

```bash
rails db:migrate:status
# Should show: 20251104093111 AddCounterCachesToUsers migrated
```

---

## Running the Backfill

### Basic Usage

```bash
rails runner script/backfill_counter_caches.rb
```

This will:
1. Enqueue 3 initial jobs (one per counter type)
2. Each initial job will enqueue batches of 10,000 users
3. Jobs process in the background
4. Progress is logged to Rails logs

### Options

**Custom Batch Size:**
```bash
BATCH_SIZE=5000 rails runner script/backfill_counter_caches.rb
```

**Wait for Completion:**
```bash
WAIT=true rails runner script/backfill_counter_caches.rb
```

**Verify After Completion:**
```bash
VERIFY=true rails runner script/backfill_counter_caches.rb
```

**All Options:**
```bash
BATCH_SIZE=5000 WAIT=true VERIFY=true rails runner script/backfill_counter_caches.rb
```

---

## Monitoring Progress

### Check Job Status

```ruby
# In Rails console
# Total pending jobs
SolidQueue::Job.where(queue_name: 'default', finished_at: nil).count

# Total finished jobs
SolidQueue::Job.where(queue_name: 'default').where.not(finished_at: nil).count

# Failed jobs
SolidQueue::Job.where(queue_name: 'default', finished_at: nil, failed_at: nil).where.not(failed_at: nil).count
```

### Check Rails Logs

```bash
tail -f log/development.log | grep "Backfilled"
```

### Estimate Progress

For 1,091,000 users with BATCH_SIZE=10,000:
- Batches per counter: ~110 batches
- Total batches: ~330 batches
- Each batch processes ~10,000 users

---

## How It Works

### 1. Initial Job Enqueuing

The script enqueues 3 initial jobs:
- `BackfillCounterCacheJob.perform_later('followers_count')`
- `BackfillCounterCacheJob.perform_later('following_count')`
- `BackfillCounterCacheJob.perform_later('posts_count')`

### 2. Batch Enqueuing

Each initial job:
1. Finds all users in batches of 10,000
2. Enqueues a job for each batch with specific user IDs
3. Logs progress

### 3. Batch Processing

Each batch job:
1. Receives a list of user IDs
2. Executes SQL UPDATE to recalculate counters for those users
3. Logs completion

### 4. Completion

Once all jobs finish:
- All users have accurate counter caches
- Application can use counter caches instead of `.count()`

---

## Performance

### Expected Time

For 1,091,000 users:
- **Enqueuing**: ~5-10 seconds (just creating job records)
- **Processing**: ~5-15 minutes (depends on database and job concurrency)
- **Total**: ~5-15 minutes

### Optimization Tips

1. **Increase Job Concurrency:**
   ```yaml
   # config/queue.yml
   workers:
     - processes: 3  # Process 3 jobs in parallel
   ```

2. **Increase Batch Size:**
   ```bash
   BATCH_SIZE=20000 rails runner script/backfill_counter_caches.rb
   ```
   Larger batches = fewer jobs, but more memory per job

3. **Run During Low Traffic:**
   - Process jobs during off-peak hours
   - Monitor database load

---

## Troubleshooting

### Jobs Not Processing

**Check if job processor is running:**
```bash
# Check if bin/jobs is running
ps aux | grep "bin/jobs"

# Or check if SOLID_QUEUE_IN_PUMA is set
echo $SOLID_QUEUE_IN_PUMA
```

**Start job processor:**
```bash
# Option 1: Run in separate process
bin/jobs

# Option 2: Set environment variable (requires Puma restart)
export SOLID_QUEUE_IN_PUMA=true
```

### Jobs Failing

**Check failed jobs:**
```ruby
# In Rails console
SolidQueue::Job.where.not(failed_at: nil).order(failed_at: :desc).limit(10)
```

**Common issues:**
- Database connection timeout: Increase `pool` size in `database.yml`
- Memory issues: Reduce `BATCH_SIZE`
- SQL errors: Check logs for specific error messages

### Counters Still Stale

**Verify counters are being updated:**
```ruby
# In Rails console
user = User.first
puts "Followers: actual=#{user.followers.count}, cached=#{user.followers_count}"
```

**If stale, re-run backfill:**
```bash
rails runner script/backfill_counter_caches.rb
```

---

## Resuming After Interruption

If the backfill is interrupted:

1. **Check remaining jobs:**
   ```ruby
   SolidQueue::Job.where(queue_name: 'default', finished_at: nil).count
   ```

2. **If jobs are still pending:**
   - Jobs will automatically resume when job processor restarts
   - No action needed

3. **If jobs were lost:**
   - Re-run the script: `rails runner script/backfill_counter_caches.rb`
   - Jobs are idempotent (safe to re-run)

---

## After Backfill Completes

Once backfill is complete:

1. **Verify counters:**
   ```bash
   VERIFY=true rails runner script/backfill_counter_caches.rb
   ```

2. **Update application code:**
   - Change `UsersController#show` to use `@user.followers_count` instead of `@user.followers.count`
   - Change view to use `@user.posts_count` instead of `@posts.count`
   - Deploy code changes

3. **Monitor performance:**
   - Check user profile page response times
   - Should see 7-14x improvement (729ms → <100ms)

---

## Production Deployment

### Step 1: Deploy Migration (No Code Changes)
```bash
git push origin main
# Deploy migration only
```

### Step 2: Run Backfill Script
```bash
# SSH into production server
rails runner script/backfill_counter_caches.rb
```

### Step 3: Monitor Jobs
```bash
# Monitor job progress
rails runner "puts SolidQueue::Job.where(queue_name: 'default', finished_at: nil).count"
```

### Step 4: Deploy Code Changes (After Backfill)
```bash
# Once backfill is complete, deploy code that uses counter caches
git push origin main
```

---

## Summary

- ✅ Use background jobs for backfilling (non-blocking)
- ✅ Process in batches (10,000 users per batch)
- ✅ Monitor via job status or logs
- ✅ Safe to re-run if interrupted
- ✅ Update application code after backfill completes

For more details, see:
- `docs/COUNTER_CACHE_INCREMENT_LOGIC.md` - When counters are maintained
- `docs/WHY_NOT_BACKFILL_IN_MIGRATIONS.md` - Why we don't backfill in migrations

