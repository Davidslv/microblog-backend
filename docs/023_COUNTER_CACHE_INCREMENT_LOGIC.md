# Counter Cache Increment Logic

## Overview

This document explains when and how counter caches are incremented/decremented for the `users` table.

---

## Counter Cache Columns

The `users` table has three counter cache columns:

1. **`followers_count`** - Number of users following this user
2. **`following_count`** - Number of users this user is following
3. **`posts_count`** - Number of posts authored by this user

---

## How Counters Are Incremented

### 1. `followers_count` and `following_count`

**When Follow is Created:**
- `Follow#after_create` callback triggers
- Calls `User.increment_counter(:following_count, follower_id)`
- Calls `User.increment_counter(:followers_count, followed_id)`

**Location:** `app/models/follow.rb`

```ruby
after_create :increment_counters

def increment_counters
  User.increment_counter(:following_count, follower_id)
  User.increment_counter(:followers_count, followed_id)
end
```

**When Follow is Destroyed:**
- `Follow#after_destroy` callback triggers
- Calls `User.decrement_counter(:following_count, follower_id)`
- Calls `User.decrement_counter(:followers_count, followed_id)`

**Location:** `app/models/follow.rb`

```ruby
after_destroy :decrement_counters

def decrement_counters
  User.decrement_counter(:following_count, follower_id)
  User.decrement_counter(:followers_count, followed_id)
end
```

**Important Notes:**
- Uses `User.increment_counter` / `User.decrement_counter` (Rails atomic methods)
- These methods use SQL `UPDATE` with `SET column = column + 1` (atomic)
- Works even with concurrent requests
- Callbacks are triggered by:
  - `Follow.create` / `Follow.save`
  - `Follow.destroy` / `Follow.destroy_all`
  - **NOT** triggered by `Follow.delete` / `Follow.delete_all` (bypasses callbacks)

**User Model Methods:**
- `User#follow(other_user)` - Creates Follow record, triggers callbacks
- `User#unfollow(other_user)` - Uses `destroy_all` to trigger callbacks

---

### 2. `posts_count`

**When Post is Created:**
- Rails `counter_cache: true` automatically increments `posts_count`
- Triggered by `Post.create` / `Post.save` with `author_id` set

**Location:** `app/models/user.rb`

```ruby
has_many :posts, foreign_key: 'author_id', dependent: :nullify, counter_cache: true
```

**When Post is Destroyed:**
- Rails `counter_cache: true` automatically decrements `posts_count`
- Triggered by `Post.destroy` / `Post.destroy_all`
- **NOT** triggered by `Post.delete` / `Post.delete_all` (bypasses callbacks)

**When Post Author Changes:**
- If `author_id` is updated, Rails automatically:
  - Decrements `posts_count` for old author
  - Increments `posts_count` for new author

**When Post Author is Set to NULL:**
- If `author_id` is set to `NULL`, Rails automatically decrements `posts_count`

**Important Notes:**
- Rails handles this automatically via `counter_cache: true`
- Uses atomic SQL `UPDATE` statements
- Works with concurrent requests
- Only triggered by ActiveRecord callbacks (not SQL `DELETE`)

---

## Edge Cases

### 1. Direct SQL Inserts

**Problem:** If Follow records are created via SQL `INSERT` (bypassing ActiveRecord):
- Callbacks are NOT triggered
- Counters are NOT updated
- Counters become stale

**Solution:** Backfill script must account for this

### 2. Bulk Inserts

**Problem:** If using `Follow.insert_all` or `Post.insert_all`:
- Callbacks are NOT triggered
- Counters are NOT updated
- Counters become stale

**Solution:** After bulk inserts, run backfill script

### 3. Direct SQL Deletes

**Problem:** If using SQL `DELETE` or `delete_all`:
- Callbacks are NOT triggered
- Counters are NOT updated
- Counters become stale

**Solution:** Use `destroy_all` instead, or backfill after

### 4. Race Conditions

**Good News:** Rails `increment_counter` / `decrement_counter` are atomic:
- Uses SQL `UPDATE users SET column = column + 1 WHERE id = ?`
- Database handles concurrency
- No race conditions possible

---

## Verification

### Check if Counters are Accurate

```ruby
# In Rails console
user = User.first

# Check followers_count
actual = user.followers.count
cached = user.followers_count
puts "Followers: actual=#{actual}, cached=#{cached}, diff=#{actual - cached}"

# Check following_count
actual = user.following.count
cached = user.following_count
puts "Following: actual=#{actual}, cached=#{cached}, diff=#{actual - cached}"

# Check posts_count
actual = user.posts.count
cached = user.posts_count
puts "Posts: actual=#{actual}, cached=#{cached}, diff=#{actual - cached}"
```

### Find Users with Stale Counters

```ruby
# Find users where counters don't match actual counts
User.find_each do |user|
  if user.followers.count != user.followers_count ||
     user.following.count != user.following_count ||
     user.posts.count != user.posts_count
    puts "User #{user.id} (#{user.username}) has stale counters"
  end
end
```

---

## Backfilling Strategy

### When to Backfill

1. **After Migration:** When counter cache columns are first added
2. **After Bulk Inserts:** If using `insert_all` to create Follows/Posts
3. **After Data Fixes:** If counters become stale due to direct SQL
4. **Periodic Maintenance:** Regular checks to ensure accuracy

### How to Backfill

See `script/backfill_counter_caches.rb` for implementation.

**Strategy:**
1. Process users in batches (e.g., 10,000 at a time)
2. Use efficient SQL `UPDATE` queries
3. Track progress and allow resumption
4. Verify accuracy after completion

---

## Summary

**Counters are automatically maintained when:**
- ✅ Follows are created/destroyed via ActiveRecord (callbacks)
- ✅ Posts are created/destroyed via ActiveRecord (counter_cache)
- ✅ User#follow / User#unfollow methods are used

**Counters are NOT maintained when:**
- ❌ Direct SQL INSERT/DELETE (bypasses callbacks)
- ❌ Bulk inserts using `insert_all` (bypasses callbacks)
- ❌ Using `delete_all` instead of `destroy_all` (bypasses callbacks)

**Solution for stale counters:**
- Run backfill script to recalculate from actual data
- Use `destroy_all` instead of `delete_all` where possible
- Avoid direct SQL operations that bypass ActiveRecord

