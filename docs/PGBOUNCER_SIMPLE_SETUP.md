# Simple PgBouncer Setup (That Actually Works)

## The Problem

You're getting authentication errors because PgBouncer needs proper configuration.

## Quick Solution: Use PostgreSQL Directly (Recommended for Development)

**For development, you don't need PgBouncer.** Just use PostgreSQL directly:

```bash
# Make sure USE_PGBOUNCER is NOT set
unset USE_PGBOUNCER

# Restart Rails
rails server
```

This will connect directly to PostgreSQL on port 5432, which works immediately.

## If You Really Want PgBouncer Working

### Step 1: Update Config and Restart

```bash
# Stop PgBouncer
pkill pgbouncer

# Copy config (will ask for password)
sudo cp config/pgbouncer.ini /opt/homebrew/etc/pgbouncer.ini
sudo sed -i '' 's|logfile = /tmp/pgbouncer.log|logfile = /opt/homebrew/var/log/pgbouncer.log|' /opt/homebrew/etc/pgbouncer.ini
sudo sed -i '' 's|pidfile = /tmp/pgbouncer.pid|pidfile = /opt/homebrew/var/run/pgbouncer.pid|' /opt/homebrew/etc/pgbouncer.ini

# Start PgBouncer
pgbouncer -d /opt/homebrew/etc/pgbouncer.ini

# Verify it's running
lsof -i :6432
```

### Step 2: Enable in Rails

```bash
export USE_PGBOUNCER=true
rails server
```

### Step 3: Test

```bash
./script/test_pgbouncer.sh
```

## Why It's Failing

The error "no password supplied" happens because:
1. PgBouncer is using `auth_type = plain` which expects a password
2. But Rails is connecting with an empty password
3. PostgreSQL allows local connections without password, but PgBouncer needs to pass it through

## The Real Fix

The current config uses `auth_type = plain` with `user=davidslv` in the database strings. This should work, but you need to:

1. **Make sure PgBouncer config is updated** (run the commands above)
2. **Make sure PgBouncer is restarted** after config changes
3. **Set USE_PGBOUNCER=true** before starting Rails

## Alternative: Just Skip PgBouncer for Development

**PgBouncer is mainly useful for production** where you have many concurrent connections. For development, direct PostgreSQL connections are simpler and work fine.

To skip PgBouncer:
```bash
# Don't set USE_PGBOUNCER (or unset it)
unset USE_PGBOUNCER

# Rails will connect directly to PostgreSQL on port 5432
rails server
```

## When to Use PgBouncer

- **Production**: High concurrency, connection pooling needed
- **Development**: Usually not needed, direct PostgreSQL is simpler

