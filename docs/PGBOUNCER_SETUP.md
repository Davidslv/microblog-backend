# PgBouncer Setup Guide

## Overview

PgBouncer is a lightweight connection pooler for PostgreSQL. It sits between your Rails application and PostgreSQL, managing database connections more efficiently.

**Benefits:**
- ✅ **Better connection management** - Reduces connection overhead
- ✅ **Higher concurrency** - Can handle more client connections with fewer PostgreSQL connections
- ✅ **Improved performance** - Less connection establishment overhead
- ✅ **Resource efficiency** - Fewer PostgreSQL connections needed

**How It Works:**
```
Rails App (50 connections) → PgBouncer (25 connections) → PostgreSQL
```

Instead of 50 direct connections to PostgreSQL, PgBouncer pools them into 25 connections.

## Installation

### macOS (Homebrew)
```bash
brew install pgbouncer
```

### Linux (Ubuntu/Debian)
```bash
sudo apt-get install pgbouncer
```

### Linux (Fedora/RHEL)
```bash
sudo dnf install pgbouncer
```

### Verify Installation
```bash
pgbouncer --version
```

## Configuration

### 1. Update PgBouncer Configuration (Recommended)

**Use the automated script:**
```bash
./script/update_pgbouncer_config.sh
```

This script will:
- Backup your current config
- Stop PgBouncer if running
- Copy our optimized config
- Update paths for your OS

**Or manually:**
The configuration file is at `config/pgbouncer.ini`. Copy it to the system location:

**macOS:**
```bash
# Stop PgBouncer first
pkill pgbouncer

# Copy config
sudo cp config/pgbouncer.ini /opt/homebrew/etc/pgbouncer.ini

# Update paths in config
sudo sed -i '' 's|logfile = /tmp/pgbouncer.log|logfile = /opt/homebrew/var/log/pgbouncer.log|' /opt/homebrew/etc/pgbouncer.ini
sudo sed -i '' 's|pidfile = /tmp/pgbouncer.pid|pidfile = /opt/homebrew/var/run/pgbouncer.pid|' /opt/homebrew/etc/pgbouncer.ini
```

**Linux:**
```bash
# Stop PgBouncer first
sudo systemctl stop pgbouncer

# Copy config
sudo cp config/pgbouncer.ini /etc/pgbouncer/pgbouncer.ini
```

### 2. Create User List (Optional)

For production, create a user list file:

```bash
# /etc/pgbouncer/userlist.txt
"your_username" "md5_hashed_password"
```

Or use `trust` authentication for development (already configured).

### 3. Update Database Configuration

**Option A: Use PgBouncer Config File**
```bash
# Backup current config
cp config/database.yml config/database.yml.backup

# Use PgBouncer config
cp config/database.yml.pgbouncer config/database.yml
```

**Option B: Manual Update**
Edit `config/database.yml`:
```yaml
default: &default
  adapter: postgresql
  host: localhost
  port: 6432  # PgBouncer port (was 5432)
  pool: 50    # Can use more connections now
  prepared_statements: false  # Required for transaction pooling
```

### 4. Start PgBouncer

**Development (Foreground):**
```bash
pgbouncer -d /usr/local/etc/pgbouncer.ini  # macOS
pgbouncer -d /etc/pgbouncer/pgbouncer.ini  # Linux
```

**Development (Background):**
```bash
pgbouncer -d /usr/local/etc/pgbouncer.ini &
```

**Production (Systemd - Linux):**
```bash
sudo systemctl start pgbouncer
sudo systemctl enable pgbouncer
```

**macOS (Launchd):**
Create `/Library/LaunchDaemons/pgbouncer.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>pgbouncer</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/pgbouncer</string>
    <string>-d</string>
    <string>/usr/local/etc/pgbouncer.ini</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
```

Then:
```bash
sudo launchctl load /Library/LaunchDaemons/pgbouncer.plist
```

### 5. Verify PgBouncer is Running

```bash
# Check if it's listening
lsof -i :6432

# Or connect to PgBouncer admin console
psql -h localhost -p 6432 -U postgres pgbouncer
```

### 6. Test Rails Connection

```bash
rails console
> ActiveRecord::Base.connection.execute("SELECT version();")
```

## PgBouncer Pooling Modes

**Transaction Pooling (Recommended):**
- One PostgreSQL connection per transaction
- Best for high-concurrency workloads
- Requires `prepared_statements: false` in Rails

**Session Pooling:**
- One PostgreSQL connection per client session
- More like direct connection
- Can use `prepared_statements: true`

**Statement Pooling:**
- One PostgreSQL connection per statement
- Not recommended for Rails

**Current Configuration:**
- Uses **transaction pooling** (best for Rails)
- Requires `prepared_statements: false`

## Configuration Details

### Key Settings

**max_client_conn = 1000**
- Maximum client connections PgBouncer will accept
- Rails can use up to 50 connections (pool size)

**default_pool_size = 25**
- Maximum PostgreSQL connections per database
- PgBouncer pools Rails connections into this

**pool_mode = transaction**
- Pooling mode (transaction is best for Rails)

### Connection Flow

**Without PgBouncer:**
```
Rails (50 connections) → PostgreSQL (50 connections)
```

**With PgBouncer:**
```
Rails (50 connections) → PgBouncer → PostgreSQL (25 connections)
```

**Benefits:**
- 50 Rails connections pooled into 25 PostgreSQL connections
- Less connection overhead
- Better resource utilization

## Performance Impact

### Expected Improvements

**Connection Management:**
- ✅ Faster connection establishment
- ✅ Better connection reuse
- ✅ Less PostgreSQL connection overhead

**Concurrency:**
- ✅ Can handle more client connections
- ✅ Better under high load
- ✅ Reduced connection exhaustion

**Expected Results:**
- **RPS**: Should improve (less connection overhead)
- **Latency**: Should decrease (faster connections)
- **Timeouts**: Should decrease (better connection management)
- **Efficiency**: Should improve

### Testing

**Before PgBouncer:**
```bash
wrk -t8 -c250 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
```

**After PgBouncer:**
```bash
# Same test
wrk -t8 -c250 -d30s -s load_test/wrk_feed.lua http://localhost:3000/
```

**Expected Improvements:**
- Better connection management
- Fewer timeouts
- Higher throughput

## Monitoring

### PgBouncer Admin Console

```bash
psql -h localhost -p 6432 -U postgres pgbouncer
```

**Useful Commands:**
```sql
-- Show pools
SHOW POOLS;

-- Show databases
SHOW DATABASES;

-- Show clients
SHOW CLIENTS;

-- Show servers
SHOW SERVERS;

-- Show stats
SHOW STATS;

-- Show config
SHOW CONFIG;
```

### Rails Health Check

Update `/health` endpoint to check PgBouncer:
```ruby
# In config/routes.rb
get '/health' => proc { |env|
  # Check PgBouncer connection
  pgbouncer_connected = ActiveRecord::Base.connection.active?
  # ... rest of health check
}
```

## Troubleshooting

### PgBouncer Not Starting

**Check Logs:**
```bash
tail -f /tmp/pgbouncer.log
```

**Common Issues:**
- Config file path incorrect
- PostgreSQL not running
- Port 6432 already in use
- Permission issues

### Connection Errors

**Error: "No such database"**
- Check `pgbouncer.ini` database configuration
- Verify PostgreSQL databases exist

**Error: "Password authentication failed" or "no password supplied"**
- **Most common issue**: Using default Homebrew config with `auth_type = md5`
- **Fix**: Run `./script/update_pgbouncer_config.sh` to use our `trust` config
- Or manually set `auth_type = trust` in PgBouncer config
- Remove or comment out `auth_file` line when using `trust`
- Restart PgBouncer after config changes

**Error: "no such user"**
- PgBouncer is using `auth_type = md5` and user not in auth_file
- **Fix**: Change to `auth_type = trust` in config and restart

**Error: "Too many connections"**
- Increase `default_pool_size` in pgbouncer.ini
- Check PostgreSQL `max_connections` setting

### Rails Connection Issues

**Error: "Connection refused"**
- PgBouncer not running
- Wrong port in database.yml (should be 6432)

**Error: "Prepared statements not supported"**
- Set `prepared_statements: false` in database.yml
- Required for transaction pooling mode

## Production Considerations

### Security

**Use Proper Authentication:**
- Don't use `trust` in production
- Use `md5` or `scram-sha-256`
- Create user list file with hashed passwords

**Network Security:**
- Bind PgBouncer to localhost only
- Use firewall rules
- Consider SSL/TLS

### High Availability

**Multiple PgBouncer Instances:**
- Run PgBouncer on each app server
- Or use a shared PgBouncer pool

**Monitoring:**
- Set up alerts for connection pool exhaustion
- Monitor PgBouncer stats
- Track connection wait times

## Migration Steps

1. ✅ Install PgBouncer
2. ✅ Copy config file
3. ✅ Start PgBouncer
4. ✅ Update database.yml to use port 6432
5. ✅ Set `prepared_statements: false`
6. ✅ Restart Rails server
7. ✅ Test connection
8. ✅ Run load tests

## References

- PgBouncer Documentation: https://www.pgbouncer.org/
- Rails + PgBouncer: https://www.pgbouncer.org/features.html
- Pooling Modes: https://www.pgbouncer.org/config.html#pool_mode

