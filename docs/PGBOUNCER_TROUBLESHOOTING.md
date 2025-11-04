# PgBouncer Troubleshooting

## Common Authentication Errors

### Error: "trust authentication failed"

**Symptoms:**
```
connection to server at "127.0.0.1", port 6432 failed: FATAL: "trust" authentication failed
```

**Cause:**
- PgBouncer is using `auth_type = trust` but PostgreSQL is rejecting the connection
- This happens when PgBouncer tries to connect to PostgreSQL but PostgreSQL's authentication rules don't match

**Solution:**
1. **Use `auth_type = any` instead** (recommended for development):
   ```ini
   auth_type = any
   ```
   This allows any user/password and passes through to PostgreSQL.

2. **Or use `auth_type = plain`** (if you want to pass through credentials):
   ```ini
   auth_type = plain
   ```

3. **Or configure PostgreSQL's pg_hba.conf** to allow trust authentication:
   ```bash
   # Edit pg_hba.conf (location varies)
   # Add line:
   host    all    all    127.0.0.1/32    trust
   ```

### Error: "no such user"

**Symptoms:**
```
no such user: davidslv
```

**Cause:**
- PgBouncer is using `auth_type = md5` and user not in auth_file
- Or user doesn't exist in PostgreSQL

**Solution:**
1. **Change to `auth_type = any`** (development):
   ```ini
   auth_type = any
   ```

2. **Or create userlist.txt** (production):
   ```bash
   # Generate password hash
   echo -n "passwordusername" | md5sum
   
   # Add to /opt/homebrew/etc/userlist.txt
   "username" "md5hash"
   ```

### Error: "Connection refused"

**Symptoms:**
```
connection to server at "::1", port 6432 failed: Connection refused
```

**Cause:**
- PgBouncer is not running
- Or listening on wrong address/port

**Solution:**
1. **Check if PgBouncer is running:**
   ```bash
   ps aux | grep pgbouncer
   lsof -i :6432
   ```

2. **Start PgBouncer:**
   ```bash
   pgbouncer -d /opt/homebrew/etc/pgbouncer.ini
   ```

3. **Check config:**
   ```ini
   listen_addr = 127.0.0.1
   listen_port = 6432
   ```

## Authentication Types Explained

### `auth_type = trust`
- **Client → PgBouncer**: No authentication required
- **PgBouncer → PostgreSQL**: Uses connecting user, no password
- **Requires**: PostgreSQL must allow trust authentication for localhost
- **Use for**: Development only

### `auth_type = plain`
- **Client → PgBouncer**: Password sent in plain text
- **PgBouncer → PostgreSQL**: Passes through password
- **Requires**: Client must provide password
- **Use for**: Development/testing

### `auth_type = any`
- **Client → PgBouncer**: Accepts any user/password
- **PgBouncer → PostgreSQL**: Passes through user/password
- **Requires**: PostgreSQL must authenticate the user
- **Use for**: Development (most flexible)

### `auth_type = md5`
- **Client → PgBouncer**: Password hashed with MD5
- **PgBouncer → PostgreSQL**: Uses auth_file or auth_query
- **Requires**: Userlist file or auth_query configured
- **Use for**: Production

## Quick Fixes

### For Development
```ini
# config/pgbouncer.ini
auth_type = any
```

Then restart PgBouncer:
```bash
pkill pgbouncer
pgbouncer -d /opt/homebrew/etc/pgbouncer.ini
```

### For Production
```ini
# config/pgbouncer.ini
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
```

Create userlist:
```bash
# Generate MD5 hash: md5(password + username)
echo -n "passwordusername" | md5sum

# Add to userlist.txt
"username" "md5hash"
```

## Testing Connection

**Test PgBouncer:**
```bash
psql -h localhost -p 6432 -U davidslv -d microblog_development
```

**Test direct PostgreSQL:**
```bash
psql -h localhost -p 5432 -U davidslv -d microblog_development
```

**Test from Rails:**
```ruby
rails console
> ActiveRecord::Base.connection.execute("SELECT 1;")
```

## Debugging Steps

1. **Check PgBouncer logs:**
   ```bash
   tail -f /opt/homebrew/var/log/pgbouncer.log
   ```

2. **Check PgBouncer status:**
   ```bash
   psql -h localhost -p 6432 -U postgres pgbouncer
   SHOW POOLS;
   SHOW CLIENTS;
   ```

3. **Check PostgreSQL logs:**
   ```bash
   tail -f /opt/homebrew/var/log/postgresql.log
   # or
   tail -f ~/Library/Logs/PostgreSQL/postgresql*.log
   ```

4. **Verify config:**
   ```bash
   pgbouncer -C /opt/homebrew/etc/pgbouncer.ini
   ```

