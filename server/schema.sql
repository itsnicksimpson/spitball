-- One row per opted-in install: running totals only. No audio, no text.
CREATE TABLE IF NOT EXISTS members (
  id TEXT PRIMARY KEY,            -- anonymous install id (UUID)
  handle TEXT NOT NULL DEFAULT '',
  words INTEGER NOT NULL DEFAULT 0,
  seconds INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS members_words ON members(words DESC);
