# Read Replicas Setup Guide

## Overview

This guide explains how to set up read replicas for the microblog application using PostgreSQL streaming replication and Rails 6+ multiple databases support. Read replicas distribute read load across multiple database servers, improving performance and scalability.

## What are Read Replicas?

Read replicas are copies of the primary database that receive replicated data via PostgreSQL's streaming replication. The application writes to the primary database and reads from replicas, distributing the read load.

### Benefits

- **Distribute Read Load**: Reads go to replicas, writes to primary
- **Horizontal Scaling**: Add more replicas as load increases
- **Fault Tolerance**: Replicas can serve reads if primary fails
- **Better Performance**: Reduce load on primary database
- **Geographic Distribution**: Replicas can be in different regions

### Architecture

```
┌─────────────────┐
│   Rails App     │
│   (Puma)        │
└────────┬────────┘
         │
         ├─────────────┐
         │             │
         ▼             ▼
    ┌─────────┐   ┌─────────┐
    │Primary  │   │Replica 1│
    │(Writes) │   │(Reads)  │
    └─────────┘   └─────────┘
                       │
                       ▼
                  ┌─────────┐
                  │Replica 2│
                  │(Reads)  │
                  └─────────┘
```

## Prerequisites

- PostgreSQL 12+ installed
- Access to PostgreSQL configuration files
- Understanding of PostgreSQL replication concepts
- Rails 6+ (this project uses Rails 8.1)

## Setup Steps

### Step 1: Configure Primary Database

#### 1.1 Enable WAL (Write-Ahead Logging)

Edit PostgreSQL configuration file:

**macOS (Homebrew):**
```bash
# Find postgresql.conf
psql -U postgres -c "SHOW config_file;"
# Usually: /opt/homebrew/var/postgresql@16/postgresql.conf
```

**Linux:**
```bash
# Usually: /etc/postgresql/16/main/postgresql.conf
sudo nano /etc/postgresql/16/main/postgresql.conf
```

**Add/Update these settings:**
```conf
# Enable WAL for replication
wal_level = replica

# Maximum number of replication connections
max_wal_senders = 3

# Maximum number of replication slots
max_replication_slots = 3

# Archive mode (optional, for point-in-time recovery)
archive_mode = on
archive_command = '/bin/true'  # Or path to archive script
```

**Restart PostgreSQL:**
```bash
# macOS
brew services restart postgresql@16

# Linux
sudo systemctl restart postgresql
```

#### 1.2 Create Replication User

```sql
-- Connect to PostgreSQL
psql -U postgres

-- Create replication user
CREATE USER replicator WITH REPLICATION PASSWORD 'secure_password_here';

-- Grant necessary permissions
GRANT CONNECT ON DATABASE microblog_development TO replicator;
GRANT CONNECT ON DATABASE microblog_production TO replicator;

-- Verify user
\du replicator
```

#### 1.3 Configure pg_hba.conf

Edit `pg_hba.conf` to allow replication connections:

**macOS (Homebrew):**
```bash
# Usually: /opt/homebrew/var/postgresql@16/pg_hba.conf
```

**Linux:**
```bash
# Usually: /etc/postgresql/16/main/pg_hba.conf
```

**Add replication entry:**
```
# Allow replication from localhost (development)
host replication replicator 127.0.0.1/32 md5

# Allow replication from specific network (production)
host replication replicator 192.168.1.0/24 md5
```

**Reload PostgreSQL configuration:**
```bash
# macOS
psql -U postgres -c "SELECT pg_reload_conf();"

# Linux
sudo systemctl reload postgresql
```

### Step 2: Setup Replica Database (Production Only)

**Note**: For development, you can skip this step and use the same database for both primary and replica. The application will automatically route reads/writes correctly.

#### 2.1 Create Replica Database Directory

```bash
# On replica server
sudo mkdir -p /var/lib/postgresql/replica-data
sudo chown postgres:postgres /var/lib/postgresql/replica-data
```

#### 2.2 Take Base Backup

```bash
# On replica server
pg_basebackup \
  -h primary_db_host \
  -D /var/lib/postgresql/replica-data \
  -U replicator \
  -P \
  -W \
  -R \
  -S replica_slot_1
```

**Parameters:**
- `-h`: Primary database host
- `-D`: Replica data directory
- `-U`: Replication user
- `-P`: Show progress
- `-W`: Prompt for password
- `-R`: Create recovery configuration
- `-S`: Replication slot name

#### 2.3 Configure Replica PostgreSQL

Edit `postgresql.conf` on replica:
```conf
# Replica is read-only
hot_standby = on
```

#### 2.4 Start Replica PostgreSQL

```bash
# On replica server
sudo systemctl start postgresql@16-replica
```

### Step 3: Configure Rails Application

#### 3.1 Update database.yml

```yaml
# config/database.yml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 25 } %>
  timeout: 5000
  prepared_statements: false
  statement_limit: 1000

development:
  primary:
    <<: *default
    database: microblog_development
    host: localhost
    port: 5432
    username: <%= ENV.fetch("DATABASE_USERNAME") { ENV["USER"] } %>
    password: <%= ENV.fetch("DATABASE_PASSWORD") { "" } %>

  # For development, use same database as primary (no actual replication)
  # In production, this would point to a replica server
  primary_replica:
    <<: *default
    database: microblog_development
    host: <%= ENV.fetch("REPLICA_HOST") { "localhost" } %>
    port: <%= ENV.fetch("REPLICA_PORT") { 5432 } %>
    username: <%= ENV.fetch("DATABASE_USERNAME") { ENV["USER"] } %>
    password: <%= ENV.fetch("DATABASE_PASSWORD") { "" } %>
    replica: true

test:
  primary:
    <<: *default
    database: microblog_test

  # For tests, use same database (replica support is optional)
  primary_replica:
    <<: *default
    database: microblog_test
    replica: true

production:
  primary:
    <<: *default
    database: microblog_production
    username: <%= ENV.fetch("DATABASE_USERNAME") { "microblog" } %>
    password: <%= ENV.fetch("DATABASE_PASSWORD") { "" } %>
    host: <%= ENV.fetch("DATABASE_HOST") { "localhost" } %>
    port: <%= ENV.fetch("DATABASE_PORT") { 5432 } %>

  primary_replica:
    <<: *default
    database: microblog_production
    username: <%= ENV.fetch("REPLICA_USERNAME") { ENV.fetch("DATABASE_USERNAME") { "microblog" } } %>
    password: <%= ENV.fetch("REPLICA_PASSWORD") { ENV.fetch("DATABASE_PASSWORD") { "" } } %>
    host: <%= ENV.fetch("REPLICA_HOST") { ENV.fetch("DATABASE_HOST") { "localhost" } } %>
    port: <%= ENV.fetch("REPLICA_PORT") { ENV.fetch("DATABASE_PORT") { 5432 } } %>
    replica: true
```

#### 3.2 Configure Application

```ruby
# config/application.rb
module Microblog
  class Application < Rails::Application
    config.load_defaults 8.1

    # Configure read replicas
    # Automatically route reads to replica, writes to primary
    config.active_record.database_selector = { delay: 2.seconds }
    config.active_record.database_resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver
    config.active_record.database_resolver_context = ActiveRecord::Middleware::DatabaseSelector::Resolver::Session
  end
end
```

#### 3.3 Use Replicas in Controllers

Rails will automatically route reads to replicas and writes to primary. For explicit control:

```ruby
# app/controllers/posts_controller.rb
def index
  # Automatically uses replica for reads
  @posts = current_user.feed_posts.timeline

  # Or explicitly use replica
  ActiveRecord::Base.connected_to(role: :reading) do
    @posts = current_user.feed_posts.timeline
  end
end

def create
  # Automatically uses primary for writes
  @post = Post.create(post_params)

  # Or explicitly use primary
  ActiveRecord::Base.connected_to(role: :writing) do
    @post = Post.create(post_params)
  end
end
```

### Step 4: Run Migrations

Migrations run on the primary database by default:

```bash
# Run migrations on primary
rails db:migrate

# Run migrations on specific database
rails db:migrate:primary
```

**Note**: Replicas automatically receive schema changes via replication.

## Development Setup (Simplified)

For development, you don't need actual replication. Rails can use the same database for both primary and replica:

```yaml
# config/database.yml
development:
  primary:
    <<: *default
    database: microblog_development

  primary_replica:
    <<: *default
    database: microblog_development  # Same database
    replica: true
```

This allows you to test the read/write routing logic without setting up actual replication.

## Production Setup

### Environment Variables

Set these environment variables in production:

```bash
# Primary database
DATABASE_HOST=primary-db.example.com
DATABASE_PORT=5432
DATABASE_USERNAME=microblog
DATABASE_PASSWORD=secure_password

# Replica database
REPLICA_HOST=replica-db.example.com
REPLICA_PORT=5432
REPLICA_USERNAME=microblog
REPLICA_PASSWORD=secure_password
```

### Verify Replication

```sql
-- On primary
SELECT * FROM pg_stat_replication;

-- On replica
SELECT pg_is_in_recovery();
-- Should return: true
```

### Monitor Replication Lag

```sql
-- On replica
SELECT
  EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS lag_seconds;
```

## Replication Lag Considerations

### Problem

Replicas may be slightly behind primary (replication lag), typically <1 second but can be higher under load.

### Solutions

#### 1. Sticky Sessions (Recommended)

Route user's reads to primary for a short time after writes:

```ruby
# config/application.rb
config.active_record.database_selector = { delay: 2.seconds }
```

This ensures users see their own writes immediately.

#### 2. Critical Reads to Primary

For critical reads (user profile, account settings), use primary:

```ruby
# app/controllers/users_controller.rb
def show
  # Use primary for user profile (must be up-to-date)
  ActiveRecord::Base.connected_to(role: :writing) do
    @user = User.find(params[:id])
  end
end
```

#### 3. Acceptable Lag for Feeds

Feed queries can tolerate small lag (seconds):

```ruby
# app/controllers/posts_controller.rb
def index
  # Automatically uses replica (acceptable lag for feeds)
  @posts = current_user.feed_posts.timeline
end
```

## Testing

### Test Database Configuration

For tests, replicas are optional. The test suite will work with or without replica configuration:

```yaml
# config/database.yml
test:
  primary:
    <<: *default
    database: microblog_test

  primary_replica:
    <<: *default
    database: microblog_test  # Same database for tests
    replica: true
```

### Run Tests

```bash
# All tests should pass
bundle exec rspec

# Test read/write routing
bundle exec rspec spec/models spec/controllers
```

## Troubleshooting

### Replication Not Working

1. **Check PostgreSQL logs:**
```bash
# macOS
tail -f /opt/homebrew/var/log/postgresql@16.log

# Linux
tail -f /var/log/postgresql/postgresql-16-main.log
```

2. **Verify replication user:**
```sql
SELECT * FROM pg_user WHERE usename = 'replicator';
```

3. **Check pg_hba.conf:**
```bash
grep replication /path/to/pg_hba.conf
```

### Replication Lag Too High

1. **Check network latency:**
```bash
ping replica_host
```

2. **Check WAL sender:**
```sql
SELECT * FROM pg_stat_replication;
```

3. **Increase WAL sender slots:**
```conf
# postgresql.conf
max_wal_senders = 10
```

### Rails Not Using Replica

1. **Check database configuration:**
```ruby
Rails.application.config.database_configuration
```

2. **Verify middleware is enabled:**
```ruby
# config/application.rb
config.active_record.database_selector
```

3. **Check connection:**
```ruby
# Rails console
ActiveRecord::Base.connected_to(role: :reading) do
  ActiveRecord::Base.connection.current_database
end
```

## Performance Monitoring

### Key Metrics

1. **Replication Lag:**
```sql
SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS lag_seconds;
```

2. **Replication Status:**
```sql
SELECT * FROM pg_stat_replication;
```

3. **Connection Counts:**
```sql
SELECT count(*) FROM pg_stat_activity WHERE datname = 'microblog_production';
```

### Expected Improvements

- **Read Capacity**: 2x (primary + 1 replica)
- **Connection Pool**: Can use separate pools for reads/writes
- **Fault Tolerance**: Replicas can serve reads if primary fails
- **Query Performance**: Feed queries on replica don't block writes

## Maintenance

### Adding More Replicas

1. Setup new replica server (follow Step 2)
2. Update database.yml:
```yaml
production:
  primary_replica_2:
    <<: *default
    database: microblog_production
    host: replica2.example.com
    replica: true
```

3. Configure load balancing (use connection pooler or application-level)

### Removing Replicas

1. Stop replication on replica server
2. Remove from database.yml
3. Drop replication slot:
```sql
SELECT pg_drop_replication_slot('replica_slot_1');
```

## Security Considerations

1. **Replication User**: Use strong password for replicator user
2. **Network**: Restrict replication connections to trusted IPs
3. **Encryption**: Use SSL for replication connections:
```conf
# postgresql.conf
ssl = on
ssl_cert_file = '/path/to/server.crt'
ssl_key_file = '/path/to/server.key'
```

## Summary

Read replicas provide:
- ✅ **2x read capacity** (primary + replicas)
- ✅ **Better fault tolerance** (replicas can serve reads if primary fails)
- ✅ **Horizontal scaling** (add more replicas as needed)
- ✅ **Geographic distribution** (replicas in different regions)

**For Development**: Use same database for primary and replica (no actual replication needed)

**For Production**: Setup PostgreSQL streaming replication with dedicated replica servers

See [Scaling Strategies](docs/028_SCALING_AND_PERFORMANCE_STRATEGIES.md) for more details.

