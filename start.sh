#!/bin/sh
# start.sh — Railway/Docker startup script with explicit step logging.
#
# Each step prints a clear "==== Step N: ... ====" banner with its exit code,
# so Railway logs show exactly which step succeeded, failed, or hung.
# stdin is redirected from /dev/null on the prisma step to prevent it from
# hanging waiting for interactive confirmation in non-TTY environments.
set -e

echo "==== Step 1/3: prisma generate ===="
npx prisma generate
echo "==== Step 1/3 done (exit $?) ===="

echo "==== Step 2/3: prisma db push ===="
# --skip-generate: avoid double-generating (we just did it in Step 1)
# --accept-data-loss: non-interactive confirmation for destructive changes
# < /dev/null: hard-block stdin so prisma can NEVER wait for input
npx prisma db push --accept-data-loss --skip-generate < /dev/null
echo "==== Step 2/3 done (exit $?) ===="

echo "==== Step 3/3: starting Plink backend (tsx src/index.ts) ===="
exec npx tsx src/index.ts
