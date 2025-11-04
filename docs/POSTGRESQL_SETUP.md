# PostgreSQL Setup Guide

## Overview

This application uses:
- **PostgreSQL** for the primary database (users, posts, follows) - better performance and concurrency
- **SQLite** for cache, queue, and cable (Rails 8 solid adapters) - lightweight and sufficient for these use cases

This hybrid approach gives you:
- ✅ PostgreSQL performance for your main application data
- ✅ SQLite simplicity for cache/queue/cable (which don't need high concurrency)
- ✅ Best of both worlds!

## Prerequisites

### Install PostgreSQL

**macOS (using Homebrew):**
```bash
brew install postgresql@16
brew services start postgresql@16
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get update
sudo apt-get install postgresql postgresql-contrib
sudo systemctl start postgresql
```

**Linux (Fedora/RHEL):**
```bash
sudo dnf install postgresql postgresql-server
sudo systemctl start postgresql
```

**Windows:**
Download and install from: https://www.postgresql.org/download/windows/

### Verify Installation

```bash
psql --version
# Should show: psql (PostgreSQL) 16.x or similar
```

## Database Setup

### 1. Create PostgreSQL User (if needed)

```bash
# Connect to PostgreSQL
psql postgres

# Create user (optional - can use your system user)
CREATE USER microblog WITH PASSWORD 'your_password';
CREATE DATABASE microblog_development OWNER microblog;
CREATE DATABASE microblog_test OWNER microblog;
\q
```

**Note:** If you don't create a specific user, PostgreSQL will use your system username by default.

### 2. Create Databases

```bash
# Using createdb command (uses your system user)
createdb microblog_development
createdb microblog_test

# Or using psql
psql postgres
CREATE DATABASE microblog_development;
CREATE DATABASE microblog_test;
\q
```

### 3. Update Gemfile

The Gemfile has been updated to use `pg` instead of `sqlite3`:
```ruby
gem "pg", "~> 1.5"
```

### 4. Install Dependencies

```bash
bundle install
```

### 5. Configure Database

The `config/database.yml` has been updated for PostgreSQL. Default configuration:
- **Host**: localhost
- **Username**: Your system username (or set `DATABASE_USERNAME` env var)
- **Password**: Empty (or set `DATABASE_PASSWORD` env var)
- **Port**: 5432 (default PostgreSQL port)

### 6. Run Migrations

```bash
# Create database structure
rails db:create

# Run migrations
rails db:migrate

# Seed test data (optional)
rails db:seed
```

### 7. Set Up Test Database

```bash
# Create test database
RAILS_ENV=test rails db:create

# Run migrations on test database
RAILS_ENV=test rails db:migrate
```

## Environment Variables (Optional)

You can customize database connection:

```bash
# .env or export in your shell
export DATABASE_USERNAME=myuser
export DATABASE_PASSWORD=mypassword
export DATABASE_HOST=localhost
export DATABASE_PORT=5432
```

## Migration from SQLite

If you have existing SQLite data you want to migrate:

### Option 1: Fresh Start (Recommended for Development)

```bash
# Just start fresh with PostgreSQL
rails db:create
rails db:migrate
rails db:seed
```

### Option 2: Export/Import Data

```bash
# Export from SQLite
rails runner "require 'csv'; ..." > export.csv

# Import to PostgreSQL
# (Use Rails console or write a script)
```

## Verification

### Test Database Connection

```bash
rails console
> ActiveRecord::Base.connection
> User.count
# Should work without errors
```

### Run Tests

```bash
bundle exec rspec
# All tests should pass
```

## Performance Improvements

### Expected Benefits

**Connection Pooling:**
- PostgreSQL handles 25+ concurrent connections efficiently
- No single-writer limitation (like SQLite)
- Better for high-concurrency workloads

**Query Performance:**
- Better query planner for complex JOINs
- More efficient index usage
- Better handling of large datasets

**Expected Performance:**
- **Concurrent Connections**: 300-500+ (vs 100-150 with SQLite)
- **RPS**: 200-400+ (vs 27-273 with SQLite)
- **Latency**: <300ms (vs 500ms-1.1s with SQLite)
- **Timeouts**: Minimal (vs 757 with SQLite at 250 concurrent)

## Troubleshooting

### Connection Errors

**Error: "FATAL: database does not exist"**
```bash
createdb microblog_development
createdb microblog_test
```

**Error: "FATAL: password authentication failed"**
```bash
# Check your username/password
# Or update config/database.yml with correct credentials
```

**Error: "FATAL: role does not exist"**
```bash
# Create user in PostgreSQL
psql postgres
CREATE USER your_username;
\q
```

### Migration Issues

**Error: "Index already exists"**
```bash
# Drop and recreate
rails db:drop
rails db:create
rails db:migrate
```

**Error: "Column does not exist"**
```bash
# Make sure all migrations have run
rails db:migrate:status
rails db:migrate
```

## Production Setup

For production, use environment variables:

```yaml
# config/database.yml (production)
production:
  primary:
    adapter: postgresql
    database: <%= ENV['DATABASE_NAME'] %>
    username: <%= ENV['DATABASE_USERNAME'] %>
    password: <%= ENV['DATABASE_PASSWORD'] %>
    host: <%= ENV['DATABASE_HOST'] %>
    port: <%= ENV['DATABASE_PORT'] || 5432 %>
    pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 25 } %>
```

## Index Optimization

The composite index on `posts (author_id, created_at DESC)` works perfectly with PostgreSQL:

```sql
-- PostgreSQL will use this index efficiently
CREATE INDEX index_posts_on_author_id_and_created_at
ON posts (author_id, created_at DESC);
```

## Next Steps

1. ✅ Install PostgreSQL
2. ✅ Update Gemfile (done)
3. ✅ Update database.yml (done)
4. ✅ Run `bundle install`
5. ✅ Create databases
6. ✅ Run migrations
7. ✅ Test the application
8. ✅ Run load tests to verify performance improvements

## References

- PostgreSQL Documentation: https://www.postgresql.org/docs/
- Rails PostgreSQL Guide: https://guides.rubyonrails.org/configuring.html#configuring-a-database
- pg gem: https://github.com/ged/ruby-pg

