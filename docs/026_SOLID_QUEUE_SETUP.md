# Solid Queue Setup and Troubleshooting

## Overview

Solid Queue is configured as the background job processor for this application, used for tasks like backfilling counter caches.

## Configuration

### Development Environment

Solid Queue is configured to run in development using the Puma plugin:

> macOS fork safety warning (fixed with OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES)

```bash
SOLID_QUEUE_IN_PUMA=true OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES rails s
```

### Production Environment

In production, Solid Queue can run either:
1. **Via Puma plugin** (single server): Set `SOLID_QUEUE_IN_PUMA=true`
2. **Separate process** (recommended for production): Run `bin/jobs` as a separate service

## Known Issues and Solutions

### macOS Fork Safety Warning

**Problem**: Workers crash with error:
```
objc[PID]: +[NSNumber initialize] may have been in progress in another thread when fork() was called
```

**Solution**: Set environment variable:
```bash
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
```

Or run Rails server with:
```bash
OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES rails s
```

### PostgreSQL Connection Segfault

**Problem**: Workers crash with segmentation fault in `pg` gem when connecting to PostgreSQL.

**Solution**: Disable prepared statements in `config/database.yml`:
```yaml
prepared_statements: false
```

This is a known compatibility issue with Ruby 3.4.7 (PRISM) and the `pg` gem.

### Workers Not Starting

**Problem**: Only supervisors are running, no workers or dispatchers.

**Check**:
1. Verify Solid Queue is configured in environment:
   ```ruby
   config.active_job.queue_adapter = :solid_queue
   config.solid_queue.connects_to = { database: { writing: :primary } }
   ```

2. Check queue configuration in `config/queue.yml`:
   ```yaml
   development:
     dispatchers:
       - polling_interval: 1
         batch_size: 500
     workers:
       - queues: "*"
         threads: 1
         processes: 1
         polling_interval: 0.1
   ```

3. Ensure Puma plugin is enabled:
   ```ruby
   plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]
   ```

### Jobs Not Processing

**Check**:
1. Workers are running: `rails runner "puts SolidQueue::Process.count"`
2. Jobs are enqueued: `rails runner "puts SolidQueue::Job.where(finished_at: nil).count"`
3. Jobs are ready: `rails runner "puts SolidQueue::ReadyExecution.count"`

## Monitoring

### Check Job Status

```ruby
rails runner "
  puts 'Pending: ' + SolidQueue::Job.where(finished_at: nil).count.to_s
  puts 'Finished: ' + SolidQueue::Job.where.not(finished_at: nil).count.to_s
  puts 'Total: ' + SolidQueue::Job.count.to_s
"
```

### Check Process Status

```ruby
rails runner "
  SolidQueue::Process.all.each { |p|
    puts \"#{p.kind}: #{p.name} (pid=#{p.pid}, last_heartbeat=#{p.last_heartbeat_at})\"
  }
"
```

### View Job Logs

Jobs log to `log/development.log` (or `log/production.log` in production).

## Running Backfill

To run the counter cache backfill:

```bash
rails runner script/backfill_counter_caches.rb
```

Monitor progress:
```bash
rails runner "puts SolidQueue::Job.where(finished_at: nil).count"
```

## Configuration Files

- `config/environments/development.rb` - Active Job adapter configuration
- `config/queue.yml` - Solid Queue worker/dispatcher configuration
- `config/database.yml` - Database connection (prepared_statements: false)
- `config/puma.rb` - Puma plugin configuration

## References

- [Solid Queue Documentation](https://github.com/rails/solid_queue)
- [Active Job Documentation](https://guides.rubyonrails.org/active_job_basics.html)

