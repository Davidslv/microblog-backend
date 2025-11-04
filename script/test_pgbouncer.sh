#!/bin/bash
# Test PgBouncer connection

echo "Testing PgBouncer setup..."

# Check if PgBouncer is running
if ! lsof -i :6432 > /dev/null 2>&1; then
    echo "❌ PgBouncer is not running on port 6432"
    echo ""
    echo "To start PgBouncer:"
    echo "  pgbouncer -d /opt/homebrew/etc/pgbouncer.ini"
    exit 1
fi

echo "✅ PgBouncer is running"

# Test connection
echo ""
echo "Testing connection to PgBouncer..."
if psql -h localhost -p 6432 -U "$USER" -d microblog_development -c "SELECT 1;" > /dev/null 2>&1; then
    echo "✅ Connection successful!"
else
    echo "❌ Connection failed"
    echo ""
    echo "Check PgBouncer logs:"
    echo "  tail -20 /opt/homebrew/var/log/pgbouncer.log"
    exit 1
fi

echo ""
echo "Testing Rails connection..."
if rails runner "ActiveRecord::Base.connection.execute('SELECT 1;')" > /dev/null 2>&1; then
    echo "✅ Rails can connect through PgBouncer!"
else
    echo "❌ Rails connection failed"
    echo ""
    echo "Make sure USE_PGBOUNCER=true is set:"
    echo "  export USE_PGBOUNCER=true"
    echo "  rails server"
    exit 1
fi

echo ""
echo "✅ All tests passed! PgBouncer is working correctly."

