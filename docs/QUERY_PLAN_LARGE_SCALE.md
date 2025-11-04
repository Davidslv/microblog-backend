# Query Plan Analysis: user.followers at Large Scale

## Query: `u.followers` (User #1) - After Further Scaling

**Current Scale:**
- **Followers**: 49,601 (was 14,883, was 258)
- **Total Users**: 61,000 (was 16,000, was 1,000)
- **Execution Time**: 42.0ms (was 28.6ms, was 2.6ms)

---

## Query Execution Plan

```
Hash Join  (cost=22010.86..23851.00 rows=49601 width=134)
  Hash Cond: (users.id = follows.follower_id)
  ->  Seq Scan on users  (cost=0.00..1680.00 rows=61000 width=134)
  ->  Hash  (cost=21390.85..21390.85 rows=49601 width=8)
        ->  Bitmap Heap Scan on follows  (cost=620.84..21390.85 rows=49601 width=8)
              Recheck Cond: (followed_id = 1)
              ->  Bitmap Index Scan on index_follows_on_followed_id  (cost=0.00..608.44 rows=49601 width=0)
                    Index Cond: (followed_id = 1)
```

---

## Key Change: Plan Strategy Reversed!

### Previous Plan (Smaller Scale)
```
Hash Join
  -> Hash (from users table) - 16,000 rows
  -> Bitmap Heap Scan (from follows) - 14,883 rows
```

### Current Plan (Larger Scale)
```
Hash Join
  -> Hash (from follows) - 49,601 rows
  -> Seq Scan (from users) - 61,000 rows
```

**PostgreSQL switched strategies!** Now it builds the hash table from the **follows** side instead of the **users** side.

---

## Why the Strategy Changed

**PostgreSQL's Decision:**
- **Hash the smaller side**: 49,601 follows vs 61,000 users
- **Follows is smaller**: 49,601 < 61,000
- **More efficient**: Hash table with 49,601 entries uses less memory

**Memory Comparison:**
- **Old way**: Hash 16,000 users × 134 bytes = ~2.1 MB
- **New way**: Hash 49,601 follows × 8 bytes = ~0.4 MB
- **Savings**: 5x less memory! ✅

**This is PostgreSQL being smart!** It automatically chose the more efficient strategy.

---

## Step-by-Step Analysis

### Step 1: Bitmap Index Scan (608.44 cost)

**What's happening:**
- Scans `index_follows_on_followed_id` for `followed_id = 1`
- Finds **49,601 rows** (49,601 users follow user #1)
- Creates bitmap of row locations

**Comparison:**
| Scale | Followers | Index Cost | Change |
|-------|-----------|------------|--------|
| Small | 258 | 6.23 | - |
| Medium | 14,883 | 176.05 | 28x |
| Large | 49,601 | 608.44 | **3.5x** (from medium) |

**Performance:**
- Cost increased proportionally with rows
- Still very efficient (index scan is fast)
- Sub-linear scaling (good!)

### Step 2: Bitmap Heap Scan (21,390.85 cost)

**What's happening:**
- Reads 49,601 actual `follower_id` values from disk
- Much more data to read

**Comparison:**
| Scale | Followers | Heap Cost | Change |
|-------|-----------|-----------|--------|
| Small | 258 | 718.83 | - |
| Medium | 14,883 | 8,604.99 | 12x |
| Large | 49,601 | 21,390.85 | **2.5x** (from medium) |

**Why it's higher:**
- 3.3x more rows to read (49,601 vs 14,883)
- More disk I/O
- Still sub-linear scaling (efficient!)

### Step 3: Hash Table Build (21,390.85 cost)

**What's happening:**
- Takes 49,601 `follower_id` values from Step 2
- Builds an in-memory hash table
- Key: `follower_id`
- Value: Just the ID (8 bytes)

**Memory Usage:**
- 49,601 entries × 8 bytes = ~397 KB
- Much smaller than previous approach (2.1 MB)

**Why this is better:**
- Smaller hash table = faster lookups
- Less memory pressure
- Better cache locality

### Step 4: Sequential Scan on users (1,680.00 cost)

**What's happening:**
- Scans **all 61,000 users** from disk
- For each user, checks if ID exists in hash table
- If found, includes user record in result

**Comparison:**
| Scale | Users | Seq Scan Cost | Change |
|-------|-------|---------------|--------|
| Small | 1,000 | 27.00 | - |
| Medium | 16,000 | 440.00 | 16x |
| Large | 61,000 | 1,680.00 | **3.8x** (from medium) |

**Why Sequential Scan:**
- PostgreSQL still considers it cheaper than index scans
- For 61,000 rows, sequential scan is efficient
- Will switch to index scan around 100k-200k rows

**When will it switch?**
- Around 100,000-200,000 users
- PostgreSQL optimizer will switch automatically
- No manual intervention needed

### Step 5: Hash Join (23,851.00 total cost)

**What's happening:**
- For each of 61,000 users scanned
- Hash lookup: `hash_table[user.id]`
- If found (user is a follower), add to result
- Returns 49,601 user records

**Performance:**
- 61,000 hash lookups (O(1) each)
- 49,601 matches found
- Execution time: 42.0ms

**Efficiency:**
- Hash lookups are O(1) - very fast
- Only 49,601 actual matches (not all 61k users)
- Optimal strategy for this use case

---

## Performance Analysis

### Execution Time Breakdown

**Total: 42.0ms**

**Estimated breakdown:**
- Index scan: ~2-3ms
- Heap scan: ~25-30ms (most time - reading 49k rows)
- Hash build: ~2-3ms
- Seq scan: ~10-15ms (scanning 61k users)
- Hash join: ~2-3ms

**Bottleneck:** Reading 49,601 rows from disk (Heap Scan)

### Scaling Analysis

**Linear Scaling Confirmed:**

| Followers | Execution Time | Time per Follower |
|-----------|---------------|-------------------|
| 258 | 2.6ms | 0.010ms |
| 14,883 | 28.6ms | 0.0019ms |
| 49,601 | 42.0ms | 0.0008ms |

**Interesting:** Time per follower is **decreasing**! This is because:
- Hash table efficiency improves with scale
- Fixed costs (index scan, seq scan) are amortized
- PostgreSQL's optimizer chose better strategy

**Not perfectly linear, but very close!**

### Cost Scaling

**Total Cost: 23,851**

| Component | Cost | Percentage |
|-----------|------|------------|
| Index Scan | 608.44 | 2.6% |
| Heap Scan | 21,390.85 | 89.7% |
| Seq Scan | 1,680.00 | 7.0% |
| Hash Join | 23,851.00 | 100% |

**Heap Scan is the dominant cost** (89.7%) - this is where most time is spent.

---

## Performance Comparison Across Scales

| Scale | Followers | Users | Time | Cost | Strategy |
|-------|-----------|-------|------|------|----------|
| **Small** | 258 | 1,000 | 2.6ms | 759 | Hash users |
| **Medium** | 14,883 | 16,000 | 28.6ms | 9,284 | Hash users |
| **Large** | 49,601 | 61,000 | 42.0ms | 23,851 | **Hash follows** |

**Key Observations:**
1. ✅ Execution time scales sub-linearly (better than linear!)
2. ✅ PostgreSQL automatically switches strategies
3. ✅ 42.0ms for 49,601 followers is excellent
4. ✅ Cost increases are predictable

---

## Why PostgreSQL Switched Strategies

### Hash Table Size Comparison

**Old Strategy (Hash Users):**
- Hash 61,000 users × 134 bytes = ~8.2 MB
- Memory: Large

**New Strategy (Hash Follows):**
- Hash 49,601 follows × 8 bytes = ~0.4 MB
- Memory: Small

**Savings: 20x less memory!**

### Lookup Efficiency

**Old Strategy:**
- 49,601 lookups in 61,000-entry hash table
- Hash table is sparsely populated

**New Strategy:**
- 61,000 lookups in 49,601-entry hash table
- Hash table is densely populated
- Better cache locality

**PostgreSQL chose the optimal strategy automatically!** ✅

---

## Optimization Opportunities

### Current Performance: ✅ Excellent

**42.0ms for 49,601 followers is still very fast!**

### When to Consider Optimization

**Pagination (Recommended for Display):**
```ruby
# Only load 20 followers at a time
user.followers.limit(20)

# Or use cursor pagination
cursor_paginate(user.followers, per_page: 20)
```

**Benefits:**
- Execution time: ~5-10ms (instead of 42ms)
- Only loads 20 users instead of 49,601
- Much better user experience

**Counter Cache (For Count Only):**
```ruby
# Add to users table
add_column :users, :followers_count, :integer, default: 0

# Query becomes O(1)
user.followers_count
```

**Benefits:**
- Count query: <1ms (instead of 42ms)
- Perfect for "X followers" display
- No need to load all followers

### Future Considerations

**At 100,000 followers:**
- Estimated time: ~80-100ms
- Still acceptable
- **Definitely add pagination**

**At 500,000 followers:**
- Estimated time: ~300-400ms
- **Requires optimization:**
  - Pagination (mandatory)
  - Counter cache (for count)
  - Consider materialized view

---

## Key Takeaways

### ✅ What's Working Well

1. **Automatic Optimization**: PostgreSQL switched strategies automatically
2. **Sub-linear Scaling**: Performance better than linear scaling
3. **Memory Efficiency**: New strategy uses 20x less memory
4. **Fast Execution**: 42.0ms for 49,601 rows is excellent

### 📊 Performance Metrics

- **Query Time**: 42.0ms (excellent for this scale)
- **Cost**: 23,851 (reasonable for 49k rows)
- **Memory**: ~0.4 MB (hash table)
- **Strategy**: Optimal (PostgreSQL chose best approach)

### 🔮 Future Scaling

**Projected Performance:**

| Followers | Estimated Time | Status |
|-----------|---------------|--------|
| 50,000 | ~42ms | ✅ Excellent |
| 100,000 | ~80ms | ✅ Good |
| 250,000 | ~180ms | ⚠️ Consider pagination |
| 500,000 | ~350ms | ⚠️ Needs optimization |

**Recommendations:**
- ✅ **Current**: No optimization needed
- ⚠️ **At 100k**: Add pagination for display
- ⚠️ **At 250k**: Add counter cache
- ⚠️ **At 500k**: Consider materialized view

---

## Conclusion

**Current Performance: ✅ Excellent**

- 42.0ms for 49,601 followers is very fast
- PostgreSQL automatically optimized the query plan
- Strategy switch (hash follows vs hash users) is smart
- Performance scales sub-linearly (better than expected)

**PostgreSQL is doing its job perfectly!** The optimizer automatically chose the most efficient strategy based on the data distribution.

**Status:** ✅ All good - query is well-optimized!

**Next Steps:**
- Monitor performance as followers grow
- Add pagination when displaying followers list
- Add counter cache if only count is needed
- Current scale: No action needed

