# Quick Fix: PgBouncer Authentication Error

## Error
```
connection to server at "::1", port 6432 failed: fe_sendauth: no password supplied
```

## Cause
PgBouncer is using the default Homebrew configuration with `auth_type = md5`, which requires a password/userlist file. Our config uses `auth_type = trust` for development.

## Quick Fix

**Run the automated fix script:**
```bash
./script/fix_pgbouncer_auth.sh
```

**Or manually:**

1. **Stop PgBouncer:**
   ```bash
   pkill pgbouncer
   ```

2. **Backup and update config:**
   ```bash
   sudo cp /opt/homebrew/etc/pgbouncer.ini /opt/homebrew/etc/pgbouncer.ini.backup
   sudo cp config/pgbouncer.ini /opt/homebrew/etc/pgbouncer.ini
   ```

3. **Update paths for macOS:**
   ```bash
   sudo sed -i '' 's|logfile = /tmp/pgbouncer.log|logfile = /opt/homebrew/var/log/pgbouncer.log|' /opt/homebrew/etc/pgbouncer.ini
   sudo sed -i '' 's|pidfile = /tmp/pgbouncer.pid|pidfile = /opt/homebrew/var/run/pgbouncer.pid|' /opt/homebrew/etc/pgbouncer.ini
   ```

4. **Verify the change:**
   ```bash
   grep "auth_type" /opt/homebrew/etc/pgbouncer.ini
   # Should show: auth_type = trust
   ```

5. **Start PgBouncer:**
   ```bash
   pgbouncer -d /opt/homebrew/etc/pgbouncer.ini
   ```

6. **Verify it's running:**
   ```bash
   lsof -i :6432
   ```

7. **Restart your Rails server** (if it's running)

## Verify It Works

After restarting PgBouncer, try connecting:
```bash
rails console
> ActiveRecord::Base.connection.execute("SELECT 1;")
```

Or restart your Rails server and test the application.

## Troubleshooting

**If PgBouncer won't start:**
- Check logs: `tail -f /opt/homebrew/var/log/pgbouncer.log`
- Make sure PostgreSQL is running: `pg_isready`
- Verify config syntax: `pgbouncer -C /opt/homebrew/etc/pgbouncer.ini`

**If still getting authentication errors:**
- Make sure `auth_type = trust` in the config
- Make sure no `auth_file` line is active (comment it out)
- Restart both PgBouncer and Rails server

