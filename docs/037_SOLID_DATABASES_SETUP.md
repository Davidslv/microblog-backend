# Solid Databases Setup Guide

This guide explains how to set up PostgreSQL databases for Solid Cache, Queue, and Cable with dedicated credentials for security and isolation.

## Overview

The application uses three separate PostgreSQL databases for Solid adapters:
- **Solid Cache**: `microblog_cache` - Application caching
- **Solid Queue**: `microblog_queue` - Background job processing
- **Solid Cable**: `microblog_cable` - WebSocket connections

Each database uses:
- **Dedicated PostgreSQL user** (e.g., `microblog_cache`, `microblog_queue`, `microblog_cable`)
- **Separate password** (configurable via environment variables)
- **Limited permissions** (users only have access to their specific database)

This provides:
- ✅ **Security**: Principle of least privilege - each service only accesses its own database
- ✅ **Isolation**: Problems with one service don't affect others
- ✅ **Auditability**: Clear separation of access patterns
- ✅ **Horizontal Scaling**: Shared databases work across multiple app instances

## Quick Setup

### Automated Setup (Recommended)

Run the setup script:

```bash
# For development
RAILS_ENV=development ./script/setup_solid_databases.sh

# For production (will prompt for passwords)
RAILS_ENV=production ./script/setup_solid_databases.sh
```

The script will:
1. Create PostgreSQL users for each service
2. Create databases owned by those users
3. Grant necessary permissions
4. Run Rails install commands

### Manual Setup

If you prefer to set up manually:

#### Step 1: Create PostgreSQL Users

```bash
# Connect to PostgreSQL
psql -U postgres
```

```sql
-- Create cache user
CREATE USER microblog_cache WITH PASSWORD 'your_cache_password';

-- Create queue user
CREATE USER microblog_queue WITH PASSWORD 'your_queue_password';

-- Create cable user
CREATE USER microblog_cable WITH PASSWORD 'your_cable_password';
```

#### Step 2: Create Databases

```sql
-- Create cache database
CREATE DATABASE microblog_cache OWNER microblog_cache;

-- Create queue database
CREATE DATABASE microblog_queue OWNER microblog_queue;

-- Create cable database
CREATE DATABASE microblog_cable OWNER microblog_cable;
```

#### Step 3: Grant Permissions

```sql
-- Grant all privileges on cache database
GRANT ALL PRIVILEGES ON DATABASE microblog_cache TO microblog_cache;

-- Grant all privileges on queue database
GRANT ALL PRIVILEGES ON DATABASE microblog_queue TO microblog_queue;

-- Grant all privileges on cable database
GRANT ALL PRIVILEGES ON DATABASE microblog_cable TO microblog_cable;
```

#### Step 4: Run Rails Install Commands

```bash
# Set environment variables
export CACHE_DB_USERNAME=microblog_cache
export CACHE_DB_PASSWORD=your_cache_password
export QUEUE_DB_USERNAME=microblog_queue
export QUEUE_DB_PASSWORD=your_queue_password
export CABLE_DB_USERNAME=microblog_cable
export CABLE_DB_PASSWORD=your_cable_password

# Install Solid Cache
bin/rails solid_cache:install

# Install Solid Queue
bin/rails solid_queue:install

# Install Solid Cable
bin/rails solid_cable:install
```

## Environment Variables

### Development/Test

Set these in your `.env` file or shell:

```bash
# Cache database credentials
CACHE_DB_USERNAME=microblog_cache
CACHE_DB_PASSWORD=your_cache_password

# Queue database credentials
QUEUE_DB_USERNAME=microblog_queue
QUEUE_DB_PASSWORD=your_queue_password

# Cable database credentials
CABLE_DB_USERNAME=microblog_cable
CABLE_DB_PASSWORD=your_cable_password
```

### Production

Set these via your deployment platform (Heroku, AWS, etc.):

```bash
# Cache database
CACHE_DB_USERNAME=microblog_cache
CACHE_DB_PASSWORD=<secure_password>
CACHE_DB_HOST=db.example.com
CACHE_DB_PORT=5432

# Queue database
QUEUE_DB_USERNAME=microblog_queue
QUEUE_DB_PASSWORD=<secure_password>
QUEUE_DB_HOST=db.example.com
QUEUE_DB_PORT=5432

# Cable database
CABLE_DB_USERNAME=microblog_cable
CABLE_DB_PASSWORD=<secure_password>
CABLE_DB_HOST=db.example.com
CABLE_DB_PORT=5432
```

**Security Note**: For production, use strong, unique passwords for each database. Consider using a password manager or secrets management service.

## Docker Compose Setup

The `docker-compose.yml` file includes default credentials for local development:

```yaml
environment:
  CACHE_DB_USERNAME: ${CACHE_DB_USERNAME:-microblog_cache}
  CACHE_DB_PASSWORD: ${CACHE_DB_PASSWORD:-cache_password}
  QUEUE_DB_USERNAME: ${QUEUE_DB_USERNAME:-microblog_queue}
  QUEUE_DB_PASSWORD: ${QUEUE_DB_PASSWORD:-queue_password}
  CABLE_DB_USERNAME: ${CABLE_DB_USERNAME:-microblog_cable}
  CABLE_DB_PASSWORD: ${CABLE_DB_PASSWORD:-cable_password}
```

To use custom passwords:

```bash
# Create .env file
cat > .env << EOF
CACHE_DB_PASSWORD=my_secure_cache_password
QUEUE_DB_PASSWORD=my_secure_queue_password
CABLE_DB_PASSWORD=my_secure_cable_password
EOF

# Run migrations (will create users and databases)
docker compose --profile tools run migrate
```

## Database Configuration

The `config/database.yml` file is configured to use environment variables:

```yaml
cache:
  adapter: postgresql
  database: microblog_cache
  username: <%= ENV.fetch("CACHE_DB_USERNAME") { "microblog_cache" } %>
  password: <%= ENV.fetch("CACHE_DB_PASSWORD") { "" } %>
```

Defaults are provided for local development, but production should always set explicit passwords.

## Security Best Practices

### 1. Use Strong Passwords

Generate strong, unique passwords for each database:

```bash
# Generate random passwords
openssl rand -base64 32  # Cache password
openssl rand -base64 32  # Queue password
openssl rand -base64 32  # Cable password
```

### 2. Limit User Permissions

Users only have access to their own database. This follows the principle of least privilege:

```sql
-- Each user can only access their own database
-- No cross-database access
-- No superuser privileges
```

### 3. Use Environment Variables

Never hardcode passwords in configuration files. Always use environment variables:

```bash
# ✅ Good - uses environment variables
password: <%= ENV.fetch("CACHE_DB_PASSWORD") { "" } %>

# ❌ Bad - hardcoded password
password: "my_password"
```

### 4. Rotate Passwords Regularly

For production, rotate passwords periodically:

```sql
-- Change password
ALTER USER microblog_cache WITH PASSWORD 'new_secure_password';
```

Then update environment variables and restart the application.

## Troubleshooting

### Connection Errors

**Error: "FATAL: password authentication failed"**

```bash
# Verify password is correct
psql -U microblog_cache -d microblog_cache -h localhost

# Check environment variable
echo $CACHE_DB_PASSWORD
```

**Error: "FATAL: database does not exist"**

```bash
# Create database
createdb -O microblog_cache microblog_cache
```

### Permission Errors

**Error: "permission denied for database"**

```sql
-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE microblog_cache TO microblog_cache;
```

### Migration Errors

**Error: "relation does not exist"**

```bash
# Run install commands
bin/rails solid_cache:install
bin/rails solid_queue:install
bin/rails solid_cable:install
```

## Verification

### Test Database Connections

```bash
# Test cache database
psql -U microblog_cache -d microblog_cache -c "SELECT 1;"

# Test queue database
psql -U microblog_queue -d microblog_queue -c "SELECT 1;"

# Test cable database
psql -U microblog_cable -d microblog_cable -c "SELECT 1;"
```

### Test from Rails Console

```ruby
# Test cache connection
Rails.cache.write("test", "value")
Rails.cache.read("test")  # => "value"

# Test queue connection
ActiveJob::Base.queue_adapter = :solid_queue
TestJob.perform_later  # Should enqueue without errors

# Test cable connection (if using Action Cable)
# Check logs for connection errors
```

## Test Environment

For the test environment, databases use `_test` suffix:

- `microblog_cache_test`
- `microblog_queue_test`
- `microblog_cable_test`

The setup script automatically handles this based on `RAILS_ENV`.

## Production Deployment

### Checklist

- [ ] Create PostgreSQL users with strong passwords
- [ ] Create databases owned by respective users
- [ ] Grant appropriate permissions
- [ ] Set environment variables in deployment platform
- [ ] Run Rails install commands
- [ ] Verify connections work
- [ ] Test cache, queue, and cable functionality
- [ ] Document passwords in secure password manager

### Example for Heroku

```bash
# Set environment variables
heroku config:set CACHE_DB_USERNAME=microblog_cache
heroku config:set CACHE_DB_PASSWORD=<secure_password>
heroku config:set QUEUE_DB_USERNAME=microblog_queue
heroku config:set QUEUE_DB_PASSWORD=<secure_password>
heroku config:set CABLE_DB_USERNAME=microblog_cable
heroku config:set CABLE_DB_PASSWORD=<secure_password>

# Run migrations
heroku run rails solid_cache:install
heroku run rails solid_queue:install
heroku run rails solid_cable:install
```

## Summary

- ✅ Each Solid service has its own PostgreSQL database
- ✅ Each database has a dedicated user with password
- ✅ Users have limited permissions (only their database)
- ✅ Credentials configured via environment variables
- ✅ Works with horizontal scaling (shared databases)
- ✅ Secure by default (no hardcoded passwords)

For more information, see:
- [Horizontal Scaling Guide](036_HORIZONTAL_SCALING.md)
- [Read Replicas Setup](034_READ_REPLICAS_SETUP.md)

