#!/bin/bash
# Disable PgBouncer and use PostgreSQL directly

echo "Disabling PgBouncer..."

# Unset the environment variable
unset USE_PGBOUNCER

# Stop PgBouncer (optional, but clean)
pkill pgbouncer 2>/dev/null || true

echo ""
echo "✅ PgBouncer disabled"
echo ""
echo "Rails will now connect directly to PostgreSQL on port 5432"
echo ""
echo "To restart Rails:"
echo "  rails server"
echo ""
echo "Or if using foreman:"
echo "  bin/dev"
echo ""
echo "To re-enable PgBouncer later:"
echo "  export USE_PGBOUNCER=true"

