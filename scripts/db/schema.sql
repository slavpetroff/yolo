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

-- ============================================================
-- Workflow Artifact Tables (T2)
-- ============================================================

-- Critique findings (critique.jsonl, one line per finding)
CREATE TABLE IF NOT EXISTS critique (
    rowid   INTEGER PRIMARY KEY,
    id      TEXT NOT NULL,          -- C1, C2, etc.
    cat     TEXT,                   -- gap, risk, improvement, question, alternative
    sev     TEXT,                   -- critical, major, minor
    q       TEXT,                   -- question/finding
    ctx     TEXT,                   -- context/evidence
    sug     TEXT,                   -- suggestion
    st      TEXT DEFAULT 'open',   -- open, addressed, deferred, rejected
    cf      INTEGER DEFAULT 0,     -- confidence 0-100
    rd      INTEGER DEFAULT 1,     -- critique round 1-3
    phase   TEXT NOT NULL,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Research findings (research.jsonl)
CREATE TABLE IF NOT EXISTS research (
    rowid       INTEGER PRIMARY KEY,
    q           TEXT,               -- query
    src         TEXT,               -- web, docs, codebase
    finding     TEXT,
    conf        TEXT,               -- high, medium, low
    dt          TEXT,               -- date
    rel         TEXT,               -- relevance
    brief_for   TEXT,               -- critique ID link (optional)
    mode        TEXT DEFAULT 'standalone',  -- pre-critic, post-critic, standalone
    priority    TEXT DEFAULT 'medium',
    ra          TEXT,               -- requesting_agent
    rt          TEXT DEFAULT 'informational', -- blocking, informational
    resolved_at TEXT,
    phase       TEXT NOT NULL,
    created_at  TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Research archive (cross-phase persistence)
CREATE TABLE IF NOT EXISTS research_archive (
    rowid   INTEGER PRIMARY KEY,
    q       TEXT,
    finding TEXT,
    conf    TEXT,
    phase   TEXT,
    dt      TEXT,
    src     TEXT,                   -- scout, architect, lead
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Decisions (decisions.jsonl, append-only)
CREATE TABLE IF NOT EXISTS decisions (
    rowid   INTEGER PRIMARY KEY,
    ts      TEXT,                   -- timestamp ISO 8601
    agent   TEXT,
    task    TEXT,                   -- task reference
    dec     TEXT,                   -- decision
    reason  TEXT,
    alts    TEXT,                   -- JSON array of alternatives
    phase   TEXT NOT NULL,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Escalation log (escalation.jsonl, append-only)
CREATE TABLE IF NOT EXISTS escalation (
    rowid   INTEGER PRIMARY KEY,
    id      TEXT NOT NULL,          -- ESC-04-05-T3
    dt      TEXT,                   -- datetime ISO 8601
    agent   TEXT,                   -- who wrote this entry
    reason  TEXT,
    sb      TEXT,                   -- scope_boundary
    tgt     TEXT,                   -- target (senior, lead, etc.)
    sev     TEXT,                   -- blocking, major, minor
    st      TEXT DEFAULT 'open',   -- open, escalated, resolved
    res     TEXT,                   -- resolution (only on resolved)
    phase   TEXT NOT NULL,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Gaps (gaps.jsonl)
CREATE TABLE IF NOT EXISTS gaps (
    rowid   INTEGER PRIMARY KEY,
    id      TEXT NOT NULL,
    sev     TEXT,                   -- critical, major, minor
    desc    TEXT,
    exp     TEXT,                   -- expected
    act     TEXT,                   -- actual
    st      TEXT DEFAULT 'open',   -- open, fixed, accepted
    res     TEXT,                   -- resolution
    phase   TEXT NOT NULL,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Verification summary (verification.jsonl, line 1)
CREATE TABLE IF NOT EXISTS verification (
    rowid   INTEGER PRIMARY KEY,
    tier    TEXT,                   -- quick, standard, deep
    r       TEXT,                   -- PASS, FAIL, PARTIAL
    ps      INTEGER DEFAULT 0,     -- passed
    fl      INTEGER DEFAULT 0,     -- failed
    tt      INTEGER DEFAULT 0,     -- total
    dt      TEXT,
    phase   TEXT NOT NULL,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Verification checks (verification.jsonl, lines 2+)
CREATE TABLE IF NOT EXISTS verification_checks (
    rowid           INTEGER PRIMARY KEY,
    verification_id INTEGER NOT NULL REFERENCES verification(rowid) ON DELETE CASCADE,
    c               TEXT,           -- check name
    r               TEXT,           -- pass, fail, warn
    ev              TEXT,           -- evidence
    cat             TEXT,           -- must_have, artifact, key_link, anti_pattern, convention
    created_at      TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Code review (code-review.jsonl, line 1 verdict)
CREATE TABLE IF NOT EXISTS code_review (
    rowid       INTEGER PRIMARY KEY,
    plan        TEXT,               -- plan ID
    r           TEXT,               -- approve, changes_requested
    tdd         TEXT,               -- pass, fail, skip
    cycle       INTEGER DEFAULT 1,  -- review cycle 1-3
    dt          TEXT,
    sg_reviewed INTEGER,            -- suggestions reviewed count
    sg_promoted TEXT,               -- JSON array of promoted suggestions
    phase       TEXT NOT NULL,
    created_at  TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Security audit (security-audit.jsonl, line 1 summary)
CREATE TABLE IF NOT EXISTS security_audit (
    rowid    INTEGER PRIMARY KEY,
    r        TEXT,                  -- PASS, FAIL, WARN
    findings INTEGER DEFAULT 0,
    critical INTEGER DEFAULT 0,
    dt       TEXT,
    phase    TEXT NOT NULL,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Test plan (test-plan.jsonl, one line per task)
CREATE TABLE IF NOT EXISTS test_plan (
    rowid   INTEGER PRIMARY KEY,
    id      TEXT NOT NULL,          -- task ID
    tf      TEXT,                   -- JSON array of test files
    tc      INTEGER DEFAULT 0,     -- test count
    red     INTEGER DEFAULT 0,     -- boolean: red confirmed
    desc    TEXT,
    phase   TEXT NOT NULL,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Test results (test-results.jsonl, one line per plan)
CREATE TABLE IF NOT EXISTS test_results (
    rowid       INTEGER PRIMARY KEY,
    plan        TEXT,               -- plan ID
    dept        TEXT,               -- backend, frontend, uiux
    tdd_phase   TEXT,               -- red, green
    tc          INTEGER DEFAULT 0,  -- total test cases
    ps          INTEGER DEFAULT 0,  -- passed
    fl          INTEGER DEFAULT 0,  -- failed
    dt          TEXT,
    tasks       TEXT,               -- JSON array of per-task breakdown
    phase       TEXT NOT NULL,
    created_at  TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- QA gate results (.qa-gate-results.jsonl, append-only)
CREATE TABLE IF NOT EXISTS qa_gate_results (
    rowid   INTEGER PRIMARY KEY,
    gl      TEXT,                   -- gate_level: post-task, post-plan, post-phase
    r       TEXT,                   -- PASS, FAIL, WARN
    plan    TEXT,
    task    TEXT,
    tst     TEXT,                   -- JSON object {ps, fl}
    dur     INTEGER,               -- duration_ms
    f       TEXT,                   -- JSON array of files_tested
    mh      TEXT,                   -- JSON object must_have_coverage (post-plan)
    dt      TEXT,
    phase   TEXT NOT NULL,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
