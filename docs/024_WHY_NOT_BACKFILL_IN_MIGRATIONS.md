# Why Not to Backfill Data in Migrations

## The Problem

Backfilling data in database migrations is a **critical anti-pattern** that can cause serious production issues. Here's why:

---

## Problems with Backfilling in Migrations

### 1. **Deployment Blocking**

**Issue:**
- Migrations run synchronously during deployment
- Long-running backfills (5-15+ minutes) block the entire deployment
- Team members cannot deploy until migration completes
- CI/CD pipelines timeout waiting for migration

**Impact:**
- ❌ Blocks all deployments
- ❌ Prevents hotfixes from being deployed
- ❌ Creates deployment bottlenecks
- ❌ Delays releases

### 2. **Database Locking**

**Issue:**
- Backfilling operations can lock tables
- Long-running queries hold locks for extended periods
- Other database operations queue up waiting for locks
- Can cause application downtime

**Impact:**
- ❌ Application becomes unresponsive
- ❌ Read queries timeout
- ❌ Write operations blocked
- ❌ Potential deadlocks

### 3. **Migration Failures**

**Issue:**
- If backfill fails mid-way, migration is in inconsistent state
- Partial data updates leave system in invalid state
- Rollback may not fully restore previous state
- Requires manual intervention to fix

**Impact:**
- ❌ Inconsistent data state
- ❌ Difficult to rollback
- ❌ Requires manual cleanup
- ❌ Potential data corruption

### 4. **Production Risk**

**Issue:**
- Production databases are typically much larger than development
- Backfill time scales with data size
- Can take hours on large production databases
- No easy way to monitor progress

**Impact:**
- ❌ Extended production downtime
- ❌ Unpredictable migration times
- ❌ Higher risk of failure
- ❌ Difficult to estimate completion time

### 5. **Resource Consumption**

**Issue:**
- Backfills consume significant CPU, memory, and I/O
- Can impact application performance
- Database connection pool may be exhausted
- Can cause cascading failures

**Impact:**
- ❌ Degraded application performance
- ❌ Database resource exhaustion
- ❌ Potential OOM (Out of Memory) errors
- ❌ Connection pool exhaustion

### 6. **No Rollback Strategy**

**Issue:**
- Backfills are typically one-way operations
- Difficult to reverse if migration needs to rollback
- May require manual cleanup
- Data may be in inconsistent state after rollback

**Impact:**
- ❌ Cannot easily rollback migration
- ❌ Requires manual intervention
- ❌ Risk of data loss
- ❌ Complex recovery procedures

---

## Real-World Example

### What We Almost Did (Wrong Approach)

```ruby
class AddCounterCachesToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :followers_count, :integer, default: 0

    # ❌ BAD: Backfilling in migration
    execute <<-SQL
      UPDATE users
      SET followers_count = (
        SELECT COUNT(*)
        FROM follows
        WHERE follows.followed_id = users.id
      )
    SQL
  end
end
```

**With 1,091,000 users:**
- Estimated time: 5-15 minutes
- Blocks all deployments
- Locks database tables
- High risk of failure
- No easy rollback

---

## The Right Approach

### 1. **Migration Only Adds Structure**

```ruby
class AddCounterCachesToUsers < ActiveRecord::Migration[8.1]
  def up
    # ✅ GOOD: Only add columns and indexes
    add_column :users, :followers_count, :integer, default: 0, null: false
    add_column :users, :following_count, :integer, default: 0, null: false
    add_column :users, :posts_count, :integer, default: 0, null: false

    add_index :users, :followers_count
    add_index :users, :following_count
  end
end
```

**Benefits:**
- ✅ Fast migration (<1 second)
- ✅ No blocking
- ✅ Safe to deploy
- ✅ Easy to rollback

### 2. **Separate Backfill Script (Background Processing)**

```ruby
# script/backfill_counter_caches.rb
# Run this separately: rails runner script/backfill_counter_caches.rb

class BackfillCounterCaches
  BATCH_SIZE = 10_000

  def self.perform
    # Process in batches
    User.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      # Update counters for batch
      # Can be run in background, monitored, and resumed if interrupted
    end
  end
end
```

**Benefits:**
- ✅ Can run independently
- ✅ Can be monitored and resumed
- ✅ Doesn't block deployments
- ✅ Can be run during low-traffic periods
- ✅ Can be throttled to avoid resource exhaustion

---

## Best Practices

### 1. **Migrations Should Be Fast**

- Migrations should complete in <1 second when possible
- Maximum acceptable time: <10 seconds
- Anything longer should be split or done separately

### 2. **Structure First, Data Later**

- Add columns/indexes in migration
- Backfill data separately
- Enable feature gradually (feature flags)

### 3. **Background Processing**

- Use background jobs for long-running operations
- Process in batches
- Add monitoring and progress tracking
- Allow resumption if interrupted

### 4. **Gradual Rollout**

- Add counter cache columns (migration)
- Backfill data (background script)
- Enable feature gradually (feature flag)
- Monitor for issues
- Remove feature flag once stable

### 5. **Monitoring & Safety**

- Track progress of backfill
- Add logging and error handling
- Can pause/resume if needed
- Alert on failures

---

## Alternative: Two-Phase Migration

### Phase 1: Add Columns (Migration)
```ruby
# Fast migration - adds structure only
add_column :users, :followers_count, :integer, default: 0
```

### Phase 2: Backfill (Background Script)
```ruby
# Run separately - can be monitored and resumed
rails runner script/backfill_counter_caches.rb
```

### Phase 3: Enable Feature (Code Deployment)
```ruby
# Once backfill is complete, deploy code that uses counters
@followers_count = @user.followers_count
```

---

## Summary

**Never backfill in migrations because:**
1. ❌ Blocks deployments
2. ❌ Locks database
3. ❌ Risk of failure
4. ❌ No easy rollback
5. ❌ Resource intensive
6. ❌ Unpredictable timing

**Instead:**
1. ✅ Add structure in migration (fast)
2. ✅ Backfill with separate script (monitored)
3. ✅ Enable feature gradually (safe)
4. ✅ Monitor and adjust (controlled)

---

## References

- [Rails Guides: Migrations](https://guides.rubyonrails.org/active_record_migrations.html)
- [Heroku: Zero-Downtime Deploys](https://devcenter.heroku.com/articles/postgres-migrations)
- [Thoughtbot: Avoiding DDL in Migrations](https://thoughtbot.com/blog/avoid-migrations-with-data-in-rails)

