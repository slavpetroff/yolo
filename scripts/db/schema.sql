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

-- ============================================================
-- Cross-Department and State Tables (T3)
-- ============================================================

-- Design tokens (design-tokens.jsonl, from UI/UX)
CREATE TABLE IF NOT EXISTS design_tokens (
    rowid   INTEGER PRIMARY KEY,
    cat     TEXT,                   -- color, typography, spacing, elevation, motion
    name    TEXT,                   -- token name
    val     TEXT,                   -- CSS value
    sem     TEXT,                   -- semantic usage context
    dk      TEXT,                   -- dark mode value
    phase   TEXT NOT NULL,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Component specs (component-specs.jsonl, from UI/UX)
CREATE TABLE IF NOT EXISTS component_specs (
    rowid   INTEGER PRIMARY KEY,
    name    TEXT,                   -- component identifier
    desc    TEXT,                   -- purpose
    states  TEXT,                   -- JSON array of interaction states
    props   TEXT,                   -- JSON array of props
    tokens  TEXT,                   -- JSON array of token references
    a11y    TEXT,                   -- JSON object: ARIA role, keyboard nav
    status  TEXT DEFAULT 'draft',  -- ready, draft, deferred
    phase   TEXT NOT NULL,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- User flows (user-flows.jsonl, from UI/UX)
CREATE TABLE IF NOT EXISTS user_flows (
    rowid      INTEGER PRIMARY KEY,
    id         TEXT NOT NULL,       -- UF-NN
    name       TEXT,
    steps      TEXT,                -- JSON array of step sequence
    err        TEXT,                -- JSON array of error conditions
    entry      TEXT,                -- entry point URL/state
    exit_point TEXT,                -- success destination
    phase      TEXT NOT NULL,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Design handoff (design-handoff.jsonl, UX -> Frontend)
CREATE TABLE IF NOT EXISTS design_handoff (
    rowid     INTEGER PRIMARY KEY,
    component TEXT,
    status    TEXT,
    tokens    TEXT,                 -- JSON array
    phase     TEXT NOT NULL,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- API contracts (api-contracts.jsonl, Frontend <-> Backend)
CREATE TABLE IF NOT EXISTS api_contracts (
    rowid    INTEGER PRIMARY KEY,
    endpoint TEXT,
    method   TEXT,
    status   TEXT,                  -- proposed, agreed, implemented
    dept     TEXT,                  -- department
    phase    TEXT NOT NULL,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- PO Q&A verdict (po-qa-verdict.jsonl)
CREATE TABLE IF NOT EXISTS po_qa_verdict (
    rowid       INTEGER PRIMARY KEY,
    r           TEXT,               -- accept, patch, major
    phase_id    TEXT,
    scope_match TEXT,               -- full, partial, misaligned
    findings    TEXT,               -- JSON array
    action      TEXT,
    dt          TEXT,
    created_at  TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Manual QA (manual-qa.jsonl)
CREATE TABLE IF NOT EXISTS manual_qa (
    rowid   INTEGER PRIMARY KEY,
    r       TEXT,                   -- PASS, FAIL, PARTIAL
    tests   TEXT,                   -- JSON array of test entries
    dt      TEXT,
    phase   TEXT NOT NULL,
    created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Workflow state (state.json)
CREATE TABLE IF NOT EXISTS state (
    rowid   INTEGER PRIMARY KEY,
    ms      TEXT,                   -- milestone
    ph      INTEGER,               -- current phase
    tt      INTEGER,               -- total phases
    st      TEXT,                   -- planning, executing, verifying, complete
    step    TEXT,                   -- workflow step
    pr      INTEGER DEFAULT 0,     -- progress 0-100
    started TEXT,                   -- start date
    updated_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- Execution state (.execution-state.json)
CREATE TABLE IF NOT EXISTS execution_state (
    rowid        INTEGER PRIMARY KEY,
    phase        TEXT NOT NULL,
    step         TEXT,
    status       TEXT,
    started_at   TEXT,
    completed_at TEXT,
    updated_at   TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

-- ============================================================
-- Indexes (T3)
-- ============================================================

-- Phase-scoped indexes for all per-phase tables
CREATE INDEX IF NOT EXISTS idx_critique_phase ON critique(phase);
CREATE INDEX IF NOT EXISTS idx_research_phase ON research(phase);
CREATE INDEX IF NOT EXISTS idx_decisions_phase ON decisions(phase);
CREATE INDEX IF NOT EXISTS idx_escalation_phase ON escalation(phase);
CREATE INDEX IF NOT EXISTS idx_gaps_phase ON gaps(phase);
CREATE INDEX IF NOT EXISTS idx_verification_phase ON verification(phase);
CREATE INDEX IF NOT EXISTS idx_code_review_phase ON code_review(phase);
CREATE INDEX IF NOT EXISTS idx_security_audit_phase ON security_audit(phase);
CREATE INDEX IF NOT EXISTS idx_test_plan_phase ON test_plan(phase);
CREATE INDEX IF NOT EXISTS idx_test_results_phase ON test_results(phase);
CREATE INDEX IF NOT EXISTS idx_qa_gate_results_phase ON qa_gate_results(phase);
CREATE INDEX IF NOT EXISTS idx_design_tokens_phase ON design_tokens(phase);
CREATE INDEX IF NOT EXISTS idx_component_specs_phase ON component_specs(phase);
CREATE INDEX IF NOT EXISTS idx_user_flows_phase ON user_flows(phase);
CREATE INDEX IF NOT EXISTS idx_design_handoff_phase ON design_handoff(phase);
CREATE INDEX IF NOT EXISTS idx_api_contracts_phase ON api_contracts(phase);
CREATE INDEX IF NOT EXISTS idx_manual_qa_phase ON manual_qa(phase);
CREATE INDEX IF NOT EXISTS idx_execution_state_phase ON execution_state(phase);

-- Phase+plan compound indexes for task-scoped tables
CREATE INDEX IF NOT EXISTS idx_tasks_phase_plan ON tasks(plan_id);
CREATE INDEX IF NOT EXISTS idx_summaries_plan ON summaries(plan_id);
CREATE INDEX IF NOT EXISTS idx_qa_gate_results_phase_plan ON qa_gate_results(phase, plan);
CREATE INDEX IF NOT EXISTS idx_test_results_phase_plan ON test_results(phase, plan);
CREATE INDEX IF NOT EXISTS idx_code_review_phase_plan ON code_review(phase, plan);

-- ============================================================
-- FTS5 Virtual Tables (T4)
-- ============================================================

-- Full-text search on research findings
CREATE VIRTUAL TABLE IF NOT EXISTS research_fts USING fts5(
    q, finding, conf, phase,
    content=research,
    content_rowid=rowid
);

-- Full-text search on decisions
CREATE VIRTUAL TABLE IF NOT EXISTS decisions_fts USING fts5(
    dec, reason, agent, phase,
    content=decisions,
    content_rowid=rowid
);

-- Full-text search on gaps
CREATE VIRTUAL TABLE IF NOT EXISTS gaps_fts USING fts5(
    desc, exp, act, res, phase,
    content=gaps,
    content_rowid=rowid
);

-- ============================================================
-- FTS5 Sync Triggers (T4)
-- ============================================================

-- Research FTS sync
CREATE TRIGGER IF NOT EXISTS research_ai AFTER INSERT ON research BEGIN
    INSERT INTO research_fts(rowid, q, finding, conf, phase)
    VALUES (new.rowid, new.q, new.finding, new.conf, new.phase);
END;

CREATE TRIGGER IF NOT EXISTS research_ad AFTER DELETE ON research BEGIN
    INSERT INTO research_fts(research_fts, rowid, q, finding, conf, phase)
    VALUES ('delete', old.rowid, old.q, old.finding, old.conf, old.phase);
END;

CREATE TRIGGER IF NOT EXISTS research_au AFTER UPDATE ON research BEGIN
    INSERT INTO research_fts(research_fts, rowid, q, finding, conf, phase)
    VALUES ('delete', old.rowid, old.q, old.finding, old.conf, old.phase);
    INSERT INTO research_fts(rowid, q, finding, conf, phase)
    VALUES (new.rowid, new.q, new.finding, new.conf, new.phase);
END;

-- Decisions FTS sync
CREATE TRIGGER IF NOT EXISTS decisions_ai AFTER INSERT ON decisions BEGIN
    INSERT INTO decisions_fts(rowid, dec, reason, agent, phase)
    VALUES (new.rowid, new.dec, new.reason, new.agent, new.phase);
END;

CREATE TRIGGER IF NOT EXISTS decisions_ad AFTER DELETE ON decisions BEGIN
    INSERT INTO decisions_fts(decisions_fts, rowid, dec, reason, agent, phase)
    VALUES ('delete', old.rowid, old.dec, old.reason, old.agent, old.phase);
END;

CREATE TRIGGER IF NOT EXISTS decisions_au AFTER UPDATE ON decisions BEGIN
    INSERT INTO decisions_fts(decisions_fts, rowid, dec, reason, agent, phase)
    VALUES ('delete', old.rowid, old.dec, old.reason, old.agent, old.phase);
    INSERT INTO decisions_fts(rowid, dec, reason, agent, phase)
    VALUES (new.rowid, new.dec, new.reason, new.agent, new.phase);
END;

-- Gaps FTS sync
CREATE TRIGGER IF NOT EXISTS gaps_ai AFTER INSERT ON gaps BEGIN
    INSERT INTO gaps_fts(rowid, desc, exp, act, res, phase)
    VALUES (new.rowid, new.desc, new.exp, new.act, new.res, new.phase);
END;

CREATE TRIGGER IF NOT EXISTS gaps_ad AFTER DELETE ON gaps BEGIN
    INSERT INTO gaps_fts(gaps_fts, rowid, desc, exp, act, res, phase)
    VALUES ('delete', old.rowid, old.desc, old.exp, old.act, old.res, old.phase);
END;

CREATE TRIGGER IF NOT EXISTS gaps_au AFTER UPDATE ON gaps BEGIN
    INSERT INTO gaps_fts(gaps_fts, rowid, desc, exp, act, res, phase)
    VALUES ('delete', old.rowid, old.desc, old.exp, old.act, old.res, old.phase);
    INSERT INTO gaps_fts(rowid, desc, exp, act, res, phase)
    VALUES (new.rowid, new.desc, new.exp, new.act, new.res, new.phase);
END;
