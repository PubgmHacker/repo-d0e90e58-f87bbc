-- ═══════════════════════════════════════════════════════════════════════
-- Plink — Database Reset Script
-- ═══════════════════════════════════════════════════════════════════════
--
-- User requested: «обнулить бд по зарегистрированным почтам и юзерам»
--
-- This script clears all user data so the app starts fresh:
--   - Users, friendships, friend requests
--   - Rooms, participants, chat messages
--   - Direct messages, watch history
--   - Playback states, subscriptions
--   - Banned users, reports
--
-- Run via Railway CLI:
--   railway run psql "$DATABASE_URL" -f scripts/reset_database.sql
--
-- Or via Railway dashboard → PostgreSQL → Query tab.
--
-- ⚠️  WARNING: This is DESTRUCTIVE. All user data will be lost.
-- ⚠️  Make sure you have a backup if needed.
-- ═══════════════════════════════════════════════════════════════════════

BEGIN;

-- Disable foreign key checks during truncation
SET CONSTRAINTS ALL DEFERRED;

-- 1. Clear all chat and messaging data
TRUNCATE TABLE "ChatMessage" CASCADE;
TRUNCATE TABLE "DirectMessage" CASCADE;
TRUNCATE TABLE "Conversation" CASCADE;

-- 2. Clear room-related data
TRUNCATE TABLE "PlaybackState" CASCADE;
TRUNCATE TABLE "RoomParticipant" CASCADE;
TRUNCATE TABLE "WatchHistory" CASCADE;
TRUNCATE TABLE "Room" CASCADE;

-- 3. Clear friendship data
TRUNCATE TABLE "Friendship" CASCADE;
TRUNCATE TABLE "FriendRequest" CASCADE;

-- 4. Clear user-generated content
TRUNCATE TABLE "Report" CASCADE;
TRUNCATE TABLE "BannedUser" CASCADE;
TRUNCATE TABLE "Subscription" CASCADE;
TRUNCATE TABLE "UserBlock" CASCADE;

-- 5. Finally, clear all users (this is the main reset)
TRUNCATE TABLE "User" CASCADE;

-- 6. Reset auto-increment sequences (if any)
SELECT setval(pg_get_serial_sequence('"' || t.tablename || '"', 'id'), 1, false)
FROM pg_tables t
WHERE t.schemaname = 'public'
  AND pg_get_serial_sequence('"' || t.tablename || '"', 'id') IS NOT NULL;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════
-- Verification queries (run after reset to confirm)
-- ═══════════════════════════════════════════════════════════════════════

SELECT 'User' as table_name, COUNT(*) as row_count FROM "User"
UNION ALL
SELECT 'Room', COUNT(*) FROM "Room"
UNION ALL
SELECT 'ChatMessage', COUNT(*) FROM "ChatMessage"
UNION ALL
SELECT 'DirectMessage', COUNT(*) FROM "DirectMessage"
UNION ALL
SELECT 'Friendship', COUNT(*) FROM "Friendship"
UNION ALL
SELECT 'FriendRequest', COUNT(*) FROM "FriendRequest";

-- Expected output after reset:
--   table_name    | row_count
--   --------------+-----------
--   User          |         0
--   Room          |         0
--   ChatMessage   |         0
--   DirectMessage |         0
--   Friendship    |         0
--   FriendRequest |         0
