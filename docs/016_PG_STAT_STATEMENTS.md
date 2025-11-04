# pg_stat_statements Setup and Usage

## Overview

`pg_stat_statements` is a PostgreSQL extension that tracks execution statistics for all SQL statements executed by a server. It helps identify slow queries, frequently called queries, and overall database performance patterns.

## Setup

### 1. Enable the Extension

The extension is enabled via a Rails migration:

```bash
rails db:migrate
```

This runs the migration `EnablePgStatStatements` which executes:
```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

### 2. Verify It's Enabled

```bash
rails runner "puts ActiveRecord::Base.connection.execute(\"SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';\").to_a"
```

Or via psql:
```bash
psql -h localhost -U "$USER" -d microblog_development -c "\dx pg_stat_statements"
```

### 3. Configure PostgreSQL (REQUIRED)

**⚠️ IMPORTANT:** `pg_stat_statements` must be loaded via `shared_preload_libraries` before it can be used. This requires PostgreSQL configuration and a restart.

#### Find PostgreSQL Config File

**macOS (Homebrew):**
```bash
# Find the config file location
psql -h localhost -U "$USER" -d postgres -c "SHOW config_file;"
# Usually: /opt/homebrew/var/postgresql@16/postgresql.conf
# or: /usr/local/var/postgresql@16/postgresql.conf
```

**Linux:**
```bash
# Find the config file location
psql -h localhost -U "$USER" -d postgres -c "SHOW config_file;"
# Usually: /etc/postgresql/16/main/postgresql.conf
```

#### Edit postgresql.conf

Add or modify these settings:

```ini
# Add pg_stat_statements to shared_preload_libraries
shared_preload_libraries = 'pg_stat_statements'

# Configure pg_stat_statements (optional, but recommended)
pg_stat_statements.max = 10000          # Maximum number of statements tracked
pg_stat_statements.track = all          # Track all statements (including utility commands)
pg_stat_statements.track_utility = on   # Track utility commands (optional)
```

**Note:** If `shared_preload_libraries` already has values, add `pg_stat_statements` to the comma-separated list:
```ini
shared_preload_libraries = 'existing_lib,pg_stat_statements'
```

#### Restart PostgreSQL

**macOS (Homebrew):**
```bash
brew services restart postgresql@16
# or
brew services restart postgresql@14  # if using version 14
```

**Linux:**
```bash
sudo systemctl restart postgresql
# or
sudo systemctl restart postgresql@16
```

#### Verify Configuration

After restarting, verify the extension is loaded:

```bash
psql -h localhost -U "$USER" -d postgres -c "SHOW shared_preload_libraries;"
# Should include: pg_stat_statements
```

Then enable the extension in your database:

```bash
rails db:migrate
```

#### Troubleshooting

**Error: "pg_stat_statements must be loaded via shared_preload_libraries"**

This means PostgreSQL wasn't restarted after adding to `shared_preload_libraries`. You must:
1. Add `pg_stat_statements` to `shared_preload_libraries` in `postgresql.conf`
2. Restart PostgreSQL
3. Then run `rails db:migrate`

## Usage

### Rake Tasks

#### Show Top Slow Queries

```bash
# Top 20 slowest queries (by mean execution time)
rake db:stats:slow_queries

# Top 10 slowest queries
LIMIT=10 rake db:stats:slow_queries
```

**Output:**
```
================================================================================
Top 20 Slowest Queries (by mean execution time)
================================================================================

Query: SELECT "posts".* FROM "posts" WHERE "posts"."author_id" IN ($1, $2, $3...
  Calls: 1250
  Mean Time: 45.32ms
  Max Time: 234.56ms
  Total Time: 56650.00ms
  Rows: 12500
  Cache Hit: 98.5%
```

#### Show Most Frequent Queries

```bash
rake db:stats:frequent_queries
```

This helps identify queries that are called frequently, which might benefit from optimization even if they're fast.

#### Show Queries by Total Execution Time

```bash
rake db:stats:total_time
```

This shows queries that consume the most total time, which is useful for identifying optimization targets.

#### Show Summary Statistics

```bash
rake db:stats:summary
```

**Output:**
```
============================================================
pg_stat_statements Summary
============================================================
Total Unique Queries: 156
Total Calls: 125000
Total Execution Time: 4567890.12ms
Average Mean Time: 12.34ms
Maximum Execution Time: 456.78ms
============================================================
```

#### Reset Statistics

```bash
rake db:stats:reset
```

Resets all statistics. Useful when you want to start fresh after making optimizations.

### Direct SQL Queries

You can also query `pg_stat_statements` directly:

```ruby
# In Rails console
ActiveRecord::Base.connection.execute(<<-SQL)
  SELECT
    LEFT(query, 100) as query,
    calls,
    mean_exec_time,
    total_exec_time
  FROM pg_stat_statements
  ORDER BY mean_exec_time DESC
  LIMIT 10;
SQL
```

Or via psql:
```bash
psql -h localhost -U "$USER" -d microblog_development
```

```sql
-- Top slow queries
SELECT
  LEFT(query, 100) as query,
  calls,
  mean_exec_time,
  total_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

## Key Metrics Explained

### `calls`
- Number of times the query was executed
- High calls = frequently used query

### `total_exec_time`
- Total time spent executing this query (in milliseconds)
- High total time = query is a bottleneck

### `mean_exec_time`
- Average execution time per call (in milliseconds)
- High mean time = slow query

### `max_exec_time`
- Maximum execution time for a single call
- Shows worst-case performance

### `rows`
- Total number of rows returned/affected
- Helps identify queries returning large datasets

### `shared_blks_hit` / `shared_blks_read`
- Cache hit ratio
- High hit ratio = good (data is in cache)
- Low hit ratio = may need more memory or query optimization

## Common Use Cases

### 1. Identify Slow Queries

```bash
rake db:stats:slow_queries LIMIT=10
```

Look for queries with high `mean_exec_time`. These are candidates for:
- Adding indexes
- Query optimization
- Caching

### 2. Find N+1 Query Problems

```bash
rake db:stats:frequent_queries LIMIT=20
```

If you see the same query pattern repeated many times, you might have an N+1 problem.

### 3. Monitor After Optimizations

```bash
# Reset stats
rake db:stats:reset

# Run your application/load tests
# ...

# Check new stats
rake db:stats:slow_queries
```

### 4. Identify Cache Issues

```bash
# Look for queries with low cache hit ratio
psql -h localhost -U "$USER" -d microblog_development -c "
  SELECT
    LEFT(query, 100) as query,
    calls,
    100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0) AS hit_percent
  FROM pg_stat_statements
  WHERE shared_blks_hit + shared_blks_read > 100
  ORDER BY hit_percent ASC
  LIMIT 10;
"
```

## Integration with Load Testing

### Before Load Test

```bash
# Reset statistics
rake db:stats:reset
```

### After Load Test

```bash
# Check slow queries
rake db:stats:slow_queries

# Check most frequent
rake db:stats:frequent_queries

# Check total time
rake db:stats:total_time
```

This helps identify which queries were bottlenecks during the load test.

## Performance Impact

`pg_stat_statements` has minimal performance impact:
- **Memory**: ~2.4KB per unique query (configurable)
- **CPU**: Negligible overhead
- **Disk**: No disk I/O

The extension is designed to be lightweight and safe for production use.

## Limitations

1. **Query Text Truncation**: Very long queries are truncated
2. **Limited History**: Statistics reset on PostgreSQL restart (unless configured to persist)
3. **Normalized Queries**: Constants are replaced with `$1`, `$2`, etc., so you see query patterns, not exact queries

## Troubleshooting

### Extension Not Enabled

```bash
# Check if extension exists
psql -h localhost -U "$USER" -d microblog_development -c "\dx"

# If not listed, enable it
psql -h localhost -U "$USER" -d microblog_development -c "CREATE EXTENSION pg_stat_statements;"
```

### No Statistics

If you see no results, it means:
- No queries have been executed yet
- Statistics were reset
- Extension was just enabled

Run some queries and check again.

### Statistics Not Updating

If statistics don't seem to update:
1. Check if extension is enabled: `\dx pg_stat_statements`
2. Verify queries are being executed
3. Try resetting: `rake db:stats:reset`

## References

- PostgreSQL Documentation: https://www.postgresql.org/docs/current/pgstatstatements.html
- pg_stat_statements View: https://www.postgresql.org/docs/current/pgstatstatements.html#PGSTATSTATEMENTS-PG-STAT-STATEMENTS

