#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# Plink — Database Reset Script (bash wrapper)
# ═══════════════════════════════════════════════════════════════════════
#
# Usage:
#   ./scripts/reset_database.sh
#
# Requires:
#   - Railway CLI installed (npm i -g @railway/cli)
#   - Logged in to Railway (railway login)
#   - Linked to the Plink project (railway link)
#
# Or if you have DATABASE_URL directly:
#   DATABASE_URL=postgresql://... ./scripts/reset_database.sh
# ═══════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/reset_database.sql"

echo "⚠️  WARNING: This will DELETE ALL USER DATA in the Plink database."
echo "   - All registered users and emails"
echo "   - All rooms and chat history"
echo "   - All friendships and friend requests"
echo ""
read -p "Are you sure you want to continue? Type 'RESET' to confirm: " confirm

if [[ "$confirm" != "RESET" ]]; then
    echo "❌ Aborted. No changes made."
    exit 0
fi

echo ""
echo "▶️  Running database reset..."

if [[ -n "${DATABASE_URL:-}" ]]; then
    # Use DATABASE_URL directly
    echo "   Using DATABASE_URL from environment"
    psql "$DATABASE_URL" -f "$SQL_FILE"
elif command -v railway &> /dev/null; then
    # Use Railway CLI
    echo "   Using Railway CLI"
    railway run psql "$DATABASE_URL" -f "$SQL_FILE"
else
    echo "❌ Neither DATABASE_URL nor Railway CLI found."
    echo "   Install Railway CLI: npm i -g @railway/cli"
    echo "   Or set DATABASE_URL: export DATABASE_URL=postgresql://..."
    exit 1
fi

echo ""
echo "✅ Database reset complete. All tables are now empty."
echo "   New users can register fresh."
