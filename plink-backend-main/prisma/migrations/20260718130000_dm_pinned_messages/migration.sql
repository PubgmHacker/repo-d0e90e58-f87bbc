-- Pinned messages and reply pointers for direct messages
ALTER TABLE "DirectMessage"
  ADD COLUMN IF NOT EXISTS "pinnedMessageId" TEXT;

CREATE TABLE IF NOT EXISTS "PinnedMessage" (
    "id" TEXT NOT NULL,
    "userAID" TEXT NOT NULL,
    "userBID" TEXT NOT NULL,
    "messageID" TEXT NOT NULL,
    "pinnedByID" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "PinnedMessage_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "PinnedMessage_userAID_userBID_key"
  ON "PinnedMessage"("userAID", "userBID");

CREATE INDEX IF NOT EXISTS "PinnedMessage_messageID_idx"
  ON "PinnedMessage"("messageID");

CREATE INDEX IF NOT EXISTS "PinnedMessage_pinnedByID_idx"
  ON "PinnedMessage"("pinnedByID");

CREATE INDEX IF NOT EXISTS "DirectMessage_pinnedMessageId_idx"
  ON "DirectMessage"("pinnedMessageId");

DO $$ BEGIN
  ALTER TABLE "DirectMessage"
    ADD CONSTRAINT "DirectMessage_pinnedMessageId_fkey"
    FOREIGN KEY ("pinnedMessageId") REFERENCES "DirectMessage"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "PinnedMessage"
    ADD CONSTRAINT "PinnedMessage_userAID_fkey"
    FOREIGN KEY ("userAID") REFERENCES "User"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "PinnedMessage"
    ADD CONSTRAINT "PinnedMessage_userBID_fkey"
    FOREIGN KEY ("userBID") REFERENCES "User"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "PinnedMessage"
    ADD CONSTRAINT "PinnedMessage_messageID_fkey"
    FOREIGN KEY ("messageID") REFERENCES "DirectMessage"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "PinnedMessage"
    ADD CONSTRAINT "PinnedMessage_pinnedByID_fkey"
    FOREIGN KEY ("pinnedByID") REFERENCES "User"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
