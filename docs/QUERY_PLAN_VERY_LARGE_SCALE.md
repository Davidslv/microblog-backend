# Query Plan Analysis: user.followers at Very Large Scale

## Query: `u.followers` (User #1) - Very Large Scale

**Current Scale:**
- **Followers**: 99,062 (was 49,601, was 14,883, was 258)
- **Total Users**: 91,000 (was 61,000, was 16,000, was 1,000)
- **Execution Time**: 107.7ms (was 42.0ms, was 28.6ms, was 2.6ms)

---

## Query Execution Plan

```
Hash Join  (cost=6642.66..43602.99 rows=99062 width=135)
  Hash Cond: (follows.follower_id = users.id)
  ->  Bitmap Heap Scan on follows  (cost=1220.16..35368.44 rows=99062 width=8)
        Recheck Cond: (followed_id = 1)
        ->  Bitmap Index Scan on index_follows_on_followed_id  (cost=0.00..1195.40 rows=99062 width=0)
              Index Cond: (followed_id = 1)
  ->  Hash  (cost=2507.00..2507.00 rows=91000 width=135)
        ->  Seq Scan on users  (cost=0.00..2507.00 rows=91000 width=135)
```

---

## Strategy Switch: Back to Hashing Users!

### Strategy Evolution

| Scale | Followers | Users | Strategy | Hash Side |
|-------|-----------|-------|----------|-----------|
| Small | 258 | 1,000 | Hash users | Users (1k) |
| Medium | 14,883 | 16,000 | Hash users | Users (16k) |
| Large | 49,601 | 61,000 | Hash follows | Follows (49k) |
| **Very Large** | 99,062 | 91,000 | **Hash users** | **Users (91k)** |

**PostgreSQL switched back!** Now hashing users (91,000) instead of follows (99,062) because:
- Users: 91,000 < Follows: 99,062
- Hash the smaller side for efficiency
- PostgreSQL automatically optimizes based on data distribution

---

## Step-by-Step Analysis

### Step 1: Bitmap Index Scan (1,195.40 cost)

**What's happening:**
- Scans `index_follows_on_followed_id` for `followed_id = 1`
- Finds **99,062 rows** (99,062 users follow user #1)
- Creates bitmap of row locations

**Scaling:**
| Scale | Followers | Index Cost | Multiplier |
|-------|-----------|------------|------------|
| Large | 49,601 | 608.44 | - |
| Very Large | 99,062 | 1,195.40 | **2.0x** |

**Performance:**
- Cost doubled (2x) for doubled followers (2x)
- Linear scaling - expected behavior
- Still very efficient

### Step 2: Bitmap Heap Scan (35,368.44 cost)

**What's happening:**
- Reads 99,062 actual `follower_id` values from disk
- Nearly 100,000 rows to read

**Scaling:**
| Scale | Followers | Heap Cost | Multiplier |
|-------|-----------|-----------|------------|
| Large | 49,601 | 21,390.85 | - |
| Very Large | 99,062 | 35,368.44 | **1.65x** |

**Performance:**
- Cost increased 1.65x for 2x rows
- Sub-linear scaling (efficient!)
- Most time is spent here (reading data)

### Step 3: Sequential Scan on users (2,507.00 cost)

**What's happening:**
- Scans **all 91,000 users** from disk
- Builds hash table in memory
- Cost increased from 1,680 to 2,507

**Scaling:**
| Scale | Users | Seq Scan Cost | Multiplier |
|-------|-------|---------------|------------|
| Large | 61,000 | 1,680.00 | - |
| Very Large | 91,000 | 2,507.00 | **1.49x** |

**Why Sequential Scan:**
- Still cheaper than index scans
- PostgreSQL will switch to index scan around 100k-200k users
- Hash table build is fast (one-time cost)

### Step 4: Hash Table Build (2,507.00 cost)

**What's happening:**
- Takes all 91,000 users
- Builds in-memory hash table
- Key: `users.id`
- Value: Full user record (135 bytes)

**Memory Usage:**
- 91,000 users × 135 bytes = ~12.3 MB
- Larger than previous approach (0.4 MB from follows)
- But still efficient for this scale

**Why Hash Users:**
- 91,000 users < 99,062 follows
- Hash the smaller side
- More efficient lookups

### Step 5: Hash Join (43,602.99 total cost)

**What's happening:**
- For each of 99,062 follows
- Hash lookup: `hash_table[follower_id]`
- If found, add user record to result
- Returns 99,062 user records

**Performance:**
- 99,062 hash lookups (O(1) each)
- All 99,062 matches found
- Execution time: 107.7ms

**Efficiency:**
- Hash lookups are O(1) - very fast
- 99,062 lookups in 91,000-entry hash table
- Optimal strategy for this distribution

---

## Performance Analysis

### Execution Time Breakdown

**Total: 107.7ms**

**Estimated breakdown:**
- Index scan: ~5-8ms
- Heap scan: ~60-70ms (most time - reading 99k rows)
- Seq scan: ~20-25ms (scanning 91k users)
- Hash build: ~5-8ms
- Hash join: ~8-12ms

**Bottleneck:** Reading 99,062 rows from disk (Heap Scan)

### Scaling Analysis

**Performance Across All Scales:**

| Scale | Followers | Users | Time | Time per Follower |
|-------|-----------|-------|------|-------------------|
| Small | 258 | 1,000 | 2.6ms | 0.010ms |
| Medium | 14,883 | 16,000 | 28.6ms | 0.0019ms |
| Large | 49,601 | 61,000 | 42.0ms | 0.0008ms |
| **Very Large** | **99,062** | **91,000** | **107.7ms** | **0.0011ms** |

**Scaling Pattern:**
- **Time per follower**: Fluctuates but stays around 0.001ms
- **Overall scaling**: Nearly linear (2.6x time for 2x followers)
- **Efficiency**: Very good - predictable scaling

### Cost Scaling

**Total Cost: 43,603**

| Component | Cost | Percentage |
|-----------|------|------------|
| Index Scan | 1,195.40 | 2.7% |
| Heap Scan | 35,368.44 | 81.1% |
| Seq Scan | 2,507.00 | 5.8% |
| Hash Join | 43,602.99 | 100% |

**Heap Scan dominates** (81.1% of cost) - this is where optimization would help most.

---

## Strategy Comparison

### Why PostgreSQL Switched Back

**At Large Scale (49,601 followers, 61,000 users):**
- Hash follows: 49,601 entries × 8 bytes = ~0.4 MB
- Hash users: 61,000 entries × 134 bytes = ~8.2 MB
- **Chose**: Hash follows (smaller)

**At Very Large Scale (99,062 followers, 91,000 users):**
- Hash follows: 99,062 entries × 8 bytes = ~0.8 MB
- Hash users: 91,000 entries × 135 bytes = ~12.3 MB
- **Chose**: Hash users (smaller)

**Key Insight:** PostgreSQL always hashes the **smaller side**, regardless of which table it is!

**Memory Comparison:**
- Hash follows: 0.8 MB
- Hash users: 12.3 MB
- **Difference**: 15x more memory for users
- **But**: Users (91k) < Follows (99k), so hash users

**PostgreSQL's Logic:**
1. Count rows on each side
2. Hash the side with fewer rows
3. Scan the other side and look up in hash
4. Optimal strategy! ✅

---

## Performance: Still Good, But Approaching Threshold

### Current Status: ✅ Good, But Consider Optimization

**107.7ms for 99,062 followers is still acceptable, but:**
- Getting close to 100ms threshold
- Loading 99k users is a lot of data
- User experience may suffer

### Optimization Recommendations

#### 1. Pagination (Highly Recommended)

**For Display:**
```ruby
# Instead of loading all 99,062 followers
user.followers.limit(20)

# Or use cursor pagination
cursor_paginate(user.followers, per_page: 20)
```

**Benefits:**
- Execution time: ~5-10ms (instead of 107ms)
- Only loads 20 users (instead of 99,062)
- **10-20x faster!**
- Much better user experience

**When to implement:** ✅ Now (at this scale)

#### 2. Counter Cache (For Count Only)

**If you only need the count:**
```ruby
# Add to users table
add_column :users, :followers_count, :integer, default: 0

# Update on follow/unfollow
User.increment_counter(:followers_count, user_id)
User.decrement_counter(:followers_count, user_id)

# Query becomes O(1)
user.followers_count  # <1ms instead of 107ms
```

**Benefits:**
- Count query: <1ms (instead of 107ms)
- **100x faster!**
- Perfect for "99,062 followers" display

**When to implement:** ✅ Now (if only count is needed)

#### 3. Limit Query Scope

**If you don't need all followers:**
```ruby
# Only recent followers
user.followers.order(created_at: :desc).limit(100)

# Or with includes to avoid N+1
user.followers.includes(:posts).limit(20)
```

---

## Future Scaling Projections

### Performance Projections

| Followers | Estimated Time | Status | Action |
|-----------|---------------|--------|--------|
| 50,000 | ~42ms | ✅ Excellent | None |
| 100,000 | ~107ms | ⚠️ Good | **Add pagination** |
| 250,000 | ~250ms | ⚠️ Slow | Add counter cache |
| 500,000 | ~500ms | ❌ Too slow | Materialized view |
| 1,000,000 | ~1s | ❌ Unacceptable | Major optimization |

### Recommended Actions by Scale

**At 100,000 followers (current scale):**
- ✅ **Add pagination** for followers list display
- ✅ **Add counter cache** for followers count
- ⚠️ Monitor query performance

**At 250,000 followers:**
- ✅ Pagination (mandatory)
- ✅ Counter cache (mandatory)
- ⚠️ Consider materialized view

**At 500,000+ followers:**
- ✅ Materialized view
- ✅ Read replicas
- ✅ Caching layer (Redis)

---

## Key Takeaways

### ✅ What's Working

1. **Automatic Optimization**: PostgreSQL switches strategies automatically
2. **Predictable Scaling**: Nearly linear, easy to forecast
3. **Optimal Strategy**: Always hashes the smaller side
4. **Index Usage**: Efficient index scans

### ⚠️ What to Watch

1. **Execution Time**: 107.7ms is approaching threshold
2. **Data Volume**: 99,062 rows is a lot to load
3. **User Experience**: May feel slow for users

### 📊 Performance Metrics

- **Query Time**: 107.7ms (good, but approaching limit)
- **Cost**: 43,603 (reasonable for this scale)
- **Memory**: ~12.3 MB (hash table)
- **Strategy**: Optimal (PostgreSQL chose best)

### 🔮 Next Steps

**Immediate Actions:**
1. ✅ **Add pagination** - Don't load all 99k followers
2. ✅ **Add counter cache** - For count display
3. ✅ **Monitor performance** - Track query times

**Code Changes:**
```ruby
# In UsersController
def show
  @user = User.find(params[:id])
  # Use pagination instead of loading all
  @followers, @next_cursor, @has_next = cursor_paginate(
    @user.followers,
    per_page: 20
  )
  # Use counter cache for count
  @followers_count = @user.followers_count
end
```

---

## Conclusion

**Current Performance: ⚠️ Good, But Optimization Recommended**

- 107.7ms for 99,062 followers is still acceptable
- PostgreSQL is optimizing correctly
- Strategy switches are automatic and optimal
- **But**: Time to add pagination and counter cache

**Status:** ✅ Query is well-optimized, but **application-level optimization needed**

**Recommendation:**
- ✅ **Add pagination now** - Don't load all 99k followers
- ✅ **Add counter cache** - For count display
- ✅ **Monitor** - Track performance as scale grows

**The query itself is fine, but the application should paginate the results!**

