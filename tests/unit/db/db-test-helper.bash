#!/usr/bin/env bash
# db-test-helper.bash — Shared setup for FTS5 search script tests
# Creates an in-memory-equivalent temp DB with all required tables + FTS5.

# Create a temp DB with the full schema needed for search scripts
mk_test_db() {
  export TEST_DB="$BATS_TEST_TMPDIR/test-yolo.db"
  sqlite3 "$TEST_DB" <<'SCHEMA' > /dev/null
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

-- Research findings (current phase)
CREATE TABLE IF NOT EXISTS research (
    rowid   INTEGER PRIMARY KEY,
    q       TEXT NOT NULL,
    src     TEXT,
    finding TEXT NOT NULL,
    conf    TEXT DEFAULT 'medium',
    dt      TEXT,
    rel     TEXT,
    brief_for TEXT,
    mode    TEXT,
    priority TEXT,
    ra      TEXT,
    rt      TEXT,
    resolved_at TEXT,
    phase   TEXT NOT NULL
);

-- Research archive (cross-phase persistence)
CREATE TABLE IF NOT EXISTS research_archive (
    rowid   INTEGER PRIMARY KEY,
    q       TEXT NOT NULL,
    finding TEXT NOT NULL,
    conf    TEXT DEFAULT 'medium',
    phase   TEXT,
    dt      TEXT,
    src     TEXT,
    UNIQUE(q, finding)
);

-- Decisions
CREATE TABLE IF NOT EXISTS decisions (
    rowid   INTEGER PRIMARY KEY,
    ts      TEXT,
    agent   TEXT,
    task    TEXT,
    dec     TEXT NOT NULL,
    reason  TEXT,
    alts    TEXT,
    phase   TEXT NOT NULL
);

-- Gaps/issues
CREATE TABLE IF NOT EXISTS gaps (
    rowid   INTEGER PRIMARY KEY,
    id      TEXT NOT NULL,
    sev     TEXT NOT NULL,
    desc    TEXT NOT NULL,
    exp     TEXT,
    act     TEXT,
    st      TEXT DEFAULT 'open',
    res     TEXT,
    phase   TEXT NOT NULL
);

-- FTS5 virtual tables (content-synced)
CREATE VIRTUAL TABLE IF NOT EXISTS research_fts USING fts5(
    q, finding, conf, phase,
    content=research, content_rowid=rowid
);

CREATE VIRTUAL TABLE IF NOT EXISTS ra_fts USING fts5(
    q, finding, conf, phase,
    content=research_archive, content_rowid=rowid
);

CREATE VIRTUAL TABLE IF NOT EXISTS decisions_fts USING fts5(
    dec, reason, agent, phase,
    content=decisions, content_rowid=rowid
);

CREATE VIRTUAL TABLE IF NOT EXISTS gaps_fts USING fts5(
    desc, exp, act, res, phase,
    content=gaps, content_rowid=rowid
);

-- Sync triggers: research -> research_fts
CREATE TRIGGER IF NOT EXISTS research_ai AFTER INSERT ON research BEGIN
    INSERT INTO research_fts(rowid, q, finding, conf, phase)
    VALUES (new.rowid, new.q, new.finding, new.conf, new.phase);
END;
CREATE TRIGGER IF NOT EXISTS research_ad AFTER DELETE ON research BEGIN
    INSERT INTO research_fts(research_fts, rowid, q, finding, conf, phase)
    VALUES ('delete', old.rowid, old.q, old.finding, old.conf, old.phase);
END;

-- Sync triggers: research_archive -> ra_fts
CREATE TRIGGER IF NOT EXISTS ra_ai AFTER INSERT ON research_archive BEGIN
    INSERT INTO ra_fts(rowid, q, finding, conf, phase)
    VALUES (new.rowid, new.q, new.finding, new.conf, new.phase);
END;
CREATE TRIGGER IF NOT EXISTS ra_ad AFTER DELETE ON research_archive BEGIN
    INSERT INTO ra_fts(ra_fts, rowid, q, finding, conf, phase)
    VALUES ('delete', old.rowid, old.q, old.finding, old.conf, old.phase);
END;

-- Sync triggers: decisions -> decisions_fts
CREATE TRIGGER IF NOT EXISTS decisions_ai AFTER INSERT ON decisions BEGIN
    INSERT INTO decisions_fts(rowid, dec, reason, agent, phase)
    VALUES (new.rowid, new.dec, new.reason, new.agent, new.phase);
END;
CREATE TRIGGER IF NOT EXISTS decisions_ad AFTER DELETE ON decisions BEGIN
    INSERT INTO decisions_fts(decisions_fts, rowid, dec, reason, agent, phase)
    VALUES ('delete', old.rowid, old.dec, old.reason, old.agent, old.phase);
END;

-- Sync triggers: gaps -> gaps_fts
CREATE TRIGGER IF NOT EXISTS gaps_ai AFTER INSERT ON gaps BEGIN
    INSERT INTO gaps_fts(rowid, desc, exp, act, res, phase)
    VALUES (new.rowid, new.desc, new.exp, new.act, new.res, new.phase);
END;
CREATE TRIGGER IF NOT EXISTS gaps_ad AFTER DELETE ON gaps BEGIN
    INSERT INTO gaps_fts(gaps_fts, rowid, desc, exp, act, res, phase)
    VALUES ('delete', old.rowid, old.desc, old.exp, old.act, old.res, old.phase);
END;
SCHEMA
}

# Seed research data
seed_research() {
  sqlite3 "$TEST_DB" <<'SQL'
INSERT INTO research (q, finding, conf, phase, dt, src)
VALUES
  ('How to handle JWT tokens?', 'Use RS256 with key rotation for production JWT signing', 'high', '03', '2026-02-10', 'RFC 7519'),
  ('SQLite WAL mode benefits?', 'WAL mode allows concurrent reads during writes with minimal overhead', 'high', '03', '2026-02-11', 'sqlite.org'),
  ('Best practices for error handling?', 'Use structured error types with context propagation', 'medium', '04', '2026-02-12', 'go blog');
SQL
}

# Seed research_archive data
seed_archive() {
  sqlite3 "$TEST_DB" <<'SQL'
INSERT INTO research_archive (q, finding, conf, phase, dt, src)
VALUES
  ('Authentication patterns?', 'OAuth2 with PKCE for SPAs, API keys for service-to-service', 'high', '01', '2026-01-15', 'OWASP'),
  ('How to handle JWT tokens?', 'Use short-lived tokens with refresh rotation', 'medium', '02', '2026-01-20', 'auth0 blog');
SQL
}

# Seed decisions data
seed_decisions() {
  sqlite3 "$TEST_DB" <<'SQL'
INSERT INTO decisions (ts, agent, task, dec, reason, phase)
VALUES
  ('2026-02-10T10:00:00Z', 'architect', 'T1', 'Use WAL mode for SQLite', 'Concurrent reads needed for multi-agent access', '03'),
  ('2026-02-10T11:00:00Z', 'lead', 'T2', 'FTS5 for full-text search', 'Built-in SQLite extension with good performance', '03'),
  ('2026-02-11T09:00:00Z', 'architect', 'T1', 'JSONL as interchange format', 'Backward compatible with existing artifact pipeline', '04');
SQL
}

# Seed gaps data
seed_gaps() {
  sqlite3 "$TEST_DB" <<'SQL'
INSERT INTO gaps (id, sev, desc, exp, act, st, phase)
VALUES
  ('G-01', 'critical', 'Missing authentication on API endpoints', 'All endpoints require auth', 'No auth middleware', 'open', '03'),
  ('G-02', 'major', 'Error handling lacks context propagation', 'Errors include stack trace', 'Generic error messages', 'open', '03'),
  ('G-03', 'minor', 'Missing input validation on search queries', 'SQL injection prevention', 'Raw query passthrough', 'fixed', '04');
SQL
}
