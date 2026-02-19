-- YOLO Artifact Store — SQLite Schema
-- All artifact types from references/artifact-formats.md
-- WAL mode + FTS5 for full-text search on research/decisions/gaps
-- Convention: abbreviated key names from JSONL schemas where practical

PRAGMA foreign_keys = ON;

-- ============================================================
-- Core Artifact Tables (T1)
-- ============================================================

-- Plan headers (line 1 of {NN-MM}.plan.jsonl)
CREATE TABLE IF NOT EXISTS plans (
    rowid       INTEGER PRIMARY KEY,
    phase       TEXT NOT NULL,
    plan_num    TEXT NOT NULL,
    title       TEXT,
    wave        INTEGER DEFAULT 1,
    depends_on  TEXT,       -- JSON array of plan IDs
    xd          TEXT,       -- JSON array of cross-phase deps
    must_haves  TEXT,       -- JSON object {tr, ar, kl}
    objective   TEXT,
    effort      TEXT DEFAULT 'balanced',
    skills      TEXT,       -- JSON array
    fm          TEXT,       -- JSON array of files_modified
    autonomous  INTEGER DEFAULT 0,  -- boolean
    created_at  TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at  TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    UNIQUE(phase, plan_num)
);

-- Plan tasks (lines 2+ of {NN-MM}.plan.jsonl)
CREATE TABLE IF NOT EXISTS tasks (
    rowid         INTEGER PRIMARY KEY,
    plan_id       INTEGER NOT NULL REFERENCES plans(rowid) ON DELETE CASCADE,
    task_id       TEXT NOT NULL,        -- T1, T2, etc.
    type          TEXT DEFAULT 'auto',  -- auto, checkpoint:review
    action        TEXT,
    files         TEXT,                 -- JSON array
    verify        TEXT,
    done          TEXT,
    spec          TEXT,
    test_spec     TEXT,
    task_depends  TEXT,                 -- JSON array of task IDs
    status        TEXT DEFAULT 'pending',
    assigned_to   TEXT,
    completed_at  TEXT,
    files_written TEXT,                 -- JSON array
    summary       TEXT,
    created_at    TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at    TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    UNIQUE(plan_id, task_id)
);

-- Plan summaries ({NN-MM}.summary.jsonl)
CREATE TABLE IF NOT EXISTS summaries (
    rowid           INTEGER PRIMARY KEY,
    plan_id         INTEGER NOT NULL REFERENCES plans(rowid) ON DELETE CASCADE,
    status          TEXT,               -- complete, partial, failed
    date_completed  TEXT,
    tasks_completed INTEGER,
    tasks_total     INTEGER,
    commit_hashes   TEXT,               -- JSON array
    fm              TEXT,               -- JSON array of files_modified
    deviations      TEXT,               -- JSON array
    built           TEXT,               -- JSON array
    test_status     TEXT,               -- red_green, green_only, no_tests
    suggestions     TEXT,               -- JSON array
    created_at      TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    updated_at      TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    UNIQUE(plan_id)
);
