use rusqlite::Connection;
use std::env;
use std::io::Read;
use std::path::PathBuf;
use crate::commands::{state_updater, statusline, hard_gate, session_start, metrics_report, token_baseline, token_budget, token_economics_report, lock_lite, lease_lock, two_phase_complete, bootstrap_claude, bootstrap_project, bootstrap_requirements, bootstrap_roadmap, bootstrap_state, suggest_next, list_todos, phase_detect, detect_stack, infer_project_context, planning_git, resolve_model, resolve_turns, log_event, collect_metrics, compress_context, prune_completed, generate_contract, contract_revision, assess_plan_risk, resolve_gate_policy, smart_route, route_monorepo, snapshot_resume, persist_state, recover_state, compile_rolling_summary, generate_gsd_index, generate_incidents, artifact_registry, infer_gsd_summary, cache_context, cache_nuke, delta_files, help_output, bump_version, doctor_cleanup, auto_repair, rollout_stage, verify, install_hooks, migrate_config, migrate_orphaned_state, tier_context, clean_stale_teams, tmux_watchdog, verify_init_todo, verify_vibe, verify_claude_bootstrap, pre_push_hook, validate_plan, review_plan, check_regression, commit_lint, diff_against_plan, validate_requirements, verify_plan_completion, parse_frontmatter, resolve_plugin_root, config_read, compile_progress, git_state};
use crate::hooks;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Command {
    Report,
    ReportTokens,
    UpdateState,
    Statusline,
    HardGate,
    SessionStart,
    MetricsReport,
    TokenBaseline,
    Bootstrap,
    SuggestNext,
    ListTodos,
    PhaseDetect,
    DetectStack,
    Infer,
    PlanningGit,
    ResolveModel,
    ResolveTurns,
    LogEvent,
    CollectMetrics,
    GenerateContract,
    ContractRevision,
    AssessRisk,
    GatePolicy,
    SmartRoute,
    RouteMonorepo,
    SnapshotResume,
    PersistState,
    RecoverState,
    RollingSummary,
    GsdIndex,
    Incidents,
    Artifact,
    GsdSummary,
    CacheContext,
    CacheNuke,
    DeltaFiles,
    MapStaleness,
    TokenBudget,
    Lock,
    LeaseLock,
    TwoPhaseComplete,
    HelpOutput,
    BumpVersion,
    Doctor,
    AutoRepair,
    RolloutStage,
    Verify,
    Hook,
    InstallHooks,
    MigrateConfig,
    InvalidateTierCache,
    CompressContext,
    PruneCompleted,
    CompileContext,
    InstallMcp,
    MigrateOrphanedState,
    CleanStaleTeams,
    TmuxWatchdog,
    VerifyInitTodo,
    VerifyVibe,
    VerifyClaudeBootstrap,
    PrePush,
    ValidatePlan,
    ReviewPlan,
    CheckRegression,
    CommitLint,
    DiffAgainstPlan,
    ValidateRequirements,
    VerifyPlanCompletion,
    ParseFrontmatter,
    ResolvePluginRoot,
    ConfigRead,
    CompileProgress,
    GitState,
}

impl Command {
    pub fn from_arg(s: &str) -> Option<Command> {
        match s {
            "report" => Some(Command::Report),
            "report-tokens" => Some(Command::ReportTokens),
            "update-state" => Some(Command::UpdateState),
            "statusline" => Some(Command::Statusline),
            "hard-gate" => Some(Command::HardGate),
            "session-start" => Some(Command::SessionStart),
            "metrics-report" => Some(Command::MetricsReport),
            "token-baseline" => Some(Command::TokenBaseline),
            "bootstrap" => Some(Command::Bootstrap),
            "suggest-next" => Some(Command::SuggestNext),
            "list-todos" => Some(Command::ListTodos),
            "phase-detect" => Some(Command::PhaseDetect),
            "detect-stack" => Some(Command::DetectStack),
            "infer" => Some(Command::Infer),
            "planning-git" => Some(Command::PlanningGit),
            "resolve-model" => Some(Command::ResolveModel),
            "resolve-turns" => Some(Command::ResolveTurns),
            "log-event" => Some(Command::LogEvent),
            "collect-metrics" => Some(Command::CollectMetrics),
            "generate-contract" => Some(Command::GenerateContract),
            "contract-revision" => Some(Command::ContractRevision),
            "assess-risk" => Some(Command::AssessRisk),
            "gate-policy" => Some(Command::GatePolicy),
            "smart-route" => Some(Command::SmartRoute),
            "route-monorepo" => Some(Command::RouteMonorepo),
            "snapshot-resume" => Some(Command::SnapshotResume),
            "persist-state" => Some(Command::PersistState),
            "recover-state" => Some(Command::RecoverState),
            "rolling-summary" => Some(Command::RollingSummary),
            "gsd-index" => Some(Command::GsdIndex),
            "incidents" => Some(Command::Incidents),
            "artifact" => Some(Command::Artifact),
            "gsd-summary" => Some(Command::GsdSummary),
            "cache-context" => Some(Command::CacheContext),
            "cache-nuke" => Some(Command::CacheNuke),
            "delta-files" => Some(Command::DeltaFiles),
            "map-staleness" => Some(Command::MapStaleness),
            "token-budget" => Some(Command::TokenBudget),
            "lock" => Some(Command::Lock),
            "lease-lock" => Some(Command::LeaseLock),
            "two-phase-complete" => Some(Command::TwoPhaseComplete),
            "help-output" => Some(Command::HelpOutput),
            "bump-version" => Some(Command::BumpVersion),
            "doctor" => Some(Command::Doctor),
            "auto-repair" => Some(Command::AutoRepair),
            "rollout-stage" | "rollout" => Some(Command::RolloutStage),
            "verify" => Some(Command::Verify),
            "hook" => Some(Command::Hook),
            "install-hooks" => Some(Command::InstallHooks),
            "migrate-config" => Some(Command::MigrateConfig),
            "invalidate-tier-cache" => Some(Command::InvalidateTierCache),
            "compress-context" => Some(Command::CompressContext),
            "prune-completed" => Some(Command::PruneCompleted),
            "compile-context" => Some(Command::CompileContext),
            "install-mcp" => Some(Command::InstallMcp),
            "migrate-orphaned-state" => Some(Command::MigrateOrphanedState),
            "clean-stale-teams" => Some(Command::CleanStaleTeams),
            "tmux-watchdog" => Some(Command::TmuxWatchdog),
            "verify-init-todo" => Some(Command::VerifyInitTodo),
            "verify-vibe" => Some(Command::VerifyVibe),
            "verify-claude-bootstrap" => Some(Command::VerifyClaudeBootstrap),
            "pre-push" => Some(Command::PrePush),
            "validate-plan" => Some(Command::ValidatePlan),
            "review-plan" => Some(Command::ReviewPlan),
            "check-regression" => Some(Command::CheckRegression),
            "commit-lint" => Some(Command::CommitLint),
            "diff-against-plan" => Some(Command::DiffAgainstPlan),
            "validate-requirements" => Some(Command::ValidateRequirements),
            "verify-plan-completion" => Some(Command::VerifyPlanCompletion),
            "parse-frontmatter" => Some(Command::ParseFrontmatter),
            "resolve-plugin-root" => Some(Command::ResolvePluginRoot),
            "config-read" => Some(Command::ConfigRead),
            "compile-progress" => Some(Command::CompileProgress),
            "git-state" => Some(Command::GitState),
            _ => None,
        }
    }

    /// Return the canonical CLI name for this command.
    pub fn name(&self) -> &'static str {
        match self {
            Command::Report => "report",
            Command::ReportTokens => "report-tokens",
            Command::UpdateState => "update-state",
            Command::Statusline => "statusline",
            Command::HardGate => "hard-gate",
            Command::SessionStart => "session-start",
            Command::MetricsReport => "metrics-report",
            Command::TokenBaseline => "token-baseline",
            Command::Bootstrap => "bootstrap",
            Command::SuggestNext => "suggest-next",
            Command::ListTodos => "list-todos",
            Command::PhaseDetect => "phase-detect",
            Command::DetectStack => "detect-stack",
            Command::Infer => "infer",
            Command::PlanningGit => "planning-git",
            Command::ResolveModel => "resolve-model",
            Command::ResolveTurns => "resolve-turns",
            Command::LogEvent => "log-event",
            Command::CollectMetrics => "collect-metrics",
            Command::GenerateContract => "generate-contract",
            Command::ContractRevision => "contract-revision",
            Command::AssessRisk => "assess-risk",
            Command::GatePolicy => "gate-policy",
            Command::SmartRoute => "smart-route",
            Command::RouteMonorepo => "route-monorepo",
            Command::SnapshotResume => "snapshot-resume",
            Command::PersistState => "persist-state",
            Command::RecoverState => "recover-state",
            Command::RollingSummary => "rolling-summary",
            Command::GsdIndex => "gsd-index",
            Command::Incidents => "incidents",
            Command::Artifact => "artifact",
            Command::GsdSummary => "gsd-summary",
            Command::CacheContext => "cache-context",
            Command::CacheNuke => "cache-nuke",
            Command::DeltaFiles => "delta-files",
            Command::MapStaleness => "map-staleness",
            Command::TokenBudget => "token-budget",
            Command::Lock => "lock",
            Command::LeaseLock => "lease-lock",
            Command::TwoPhaseComplete => "two-phase-complete",
            Command::HelpOutput => "help-output",
            Command::BumpVersion => "bump-version",
            Command::Doctor => "doctor",
            Command::AutoRepair => "auto-repair",
            Command::RolloutStage => "rollout-stage",
            Command::Verify => "verify",
            Command::Hook => "hook",
            Command::InstallHooks => "install-hooks",
            Command::MigrateConfig => "migrate-config",
            Command::InvalidateTierCache => "invalidate-tier-cache",
            Command::CompressContext => "compress-context",
            Command::PruneCompleted => "prune-completed",
            Command::CompileContext => "compile-context",
            Command::InstallMcp => "install-mcp",
            Command::MigrateOrphanedState => "migrate-orphaned-state",
            Command::CleanStaleTeams => "clean-stale-teams",
            Command::TmuxWatchdog => "tmux-watchdog",
            Command::VerifyInitTodo => "verify-init-todo",
            Command::VerifyVibe => "verify-vibe",
            Command::VerifyClaudeBootstrap => "verify-claude-bootstrap",
            Command::PrePush => "pre-push",
            Command::ValidatePlan => "validate-plan",
            Command::ReviewPlan => "review-plan",
            Command::CheckRegression => "check-regression",
            Command::CommitLint => "commit-lint",
            Command::DiffAgainstPlan => "diff-against-plan",
            Command::ValidateRequirements => "validate-requirements",
            Command::VerifyPlanCompletion => "verify-plan-completion",
            Command::ParseFrontmatter => "parse-frontmatter",
            Command::ResolvePluginRoot => "resolve-plugin-root",
            Command::ConfigRead => "config-read",
            Command::CompileProgress => "compile-progress",
            Command::GitState => "git-state",
        }
    }

    /// All known canonical command names.
    fn all_names() -> &'static [&'static str] {
        &[
            "report", "report-tokens", "update-state", "statusline", "hard-gate",
            "session-start", "metrics-report", "token-baseline", "bootstrap",
            "suggest-next", "list-todos", "phase-detect", "detect-stack", "infer",
            "planning-git", "resolve-model", "resolve-turns", "log-event",
            "collect-metrics", "generate-contract", "contract-revision", "assess-risk",
            "gate-policy", "smart-route", "route-monorepo", "snapshot-resume",
            "persist-state", "recover-state", "rolling-summary", "gsd-index",
            "incidents", "artifact", "gsd-summary", "cache-context", "cache-nuke",
            "delta-files", "map-staleness", "token-budget", "lock", "lease-lock",
            "two-phase-complete", "help-output", "bump-version", "doctor", "auto-repair",
            "rollout-stage", "verify", "hook", "install-hooks", "migrate-config",
            "invalidate-tier-cache", "compress-context", "prune-completed",
            "compile-context", "install-mcp", "migrate-orphaned-state",
            "clean-stale-teams", "tmux-watchdog", "verify-init-todo", "verify-vibe",
            "verify-claude-bootstrap", "pre-push", "validate-plan", "review-plan",
            "check-regression", "commit-lint", "diff-against-plan",
            "validate-requirements", "verify-plan-completion",
            "parse-frontmatter", "resolve-plugin-root", "config-read",
            "compile-progress", "git-state",
        ]
    }

    /// Suggest the closest command name for a typo.
    pub fn suggest(input: &str) -> Option<&'static str> {
        let mut best: Option<(&str, usize)> = None;
        for name in Self::all_names() {
            let dist = edit_distance(input, name);
            if dist <= 3 {
                if best.is_none() || dist < best.unwrap().1 {
                    best = Some((name, dist));
                }
            }
        }
        best.map(|(name, _)| name)
    }
}

fn edit_distance(a: &str, b: &str) -> usize {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    let mut dp = vec![vec![0usize; b.len() + 1]; a.len() + 1];
    for i in 0..=a.len() { dp[i][0] = i; }
    for j in 0..=b.len() { dp[0][j] = j; }
    for i in 1..=a.len() {
        for j in 1..=b.len() {
            let cost = if a[i-1] == b[j-1] { 0 } else { 1 };
            dp[i][j] = (dp[i-1][j] + 1).min(dp[i][j-1] + 1).min(dp[i-1][j-1] + cost);
        }
    }
    dp[a.len()][b.len()]
}

pub fn generate_report(total_calls: i64, compile_calls: i64, avg_output_length: f64, unique_sessions: Option<i64>) -> String {
    let mut out = String::new();
    out.push_str("============================================================\n");
    out.push_str("             YOLO EXPERT ROI & TELEMETRY DASHBOARD           \n");
    out.push_str("============================================================\n");
    out.push_str(&format!("Total Intercepted Tool Calls: {}\n", total_calls));
    out.push_str(&format!("Context Compilations (Cache hits): {}\n", compile_calls));

    let prefix_size = avg_output_length;
    let is_measured = avg_output_length != 80_000.0;
    let cold_cost_per_m = 3.00;
    let caching_write_cost_per_m = 3.75;
    let caching_read_cost_per_m = 0.30;

    let total_tokens_pushed = compile_calls as f64 * prefix_size;
    let expected_cold_cost = (total_tokens_pushed / 1_000_000.0) * cold_cost_per_m;

    // Session-based write/read split when available, else fallback to 1:10
    let (writes, reads) = if let Some(sessions) = unique_sessions {
        let w = (sessions as f64).max(1.0);
        let r = (compile_calls as f64 - w).max(0.0);
        (w, r)
    } else {
        let w = (compile_calls as f64 / 10.0).max(1.0);
        let r = compile_calls as f64 - w;
        (w, r)
    };

    let actual_hot_cost = ((writes * prefix_size) / 1_000_000.0) * caching_write_cost_per_m +
                          ((reads * prefix_size) / 1_000_000.0) * caching_read_cost_per_m;
    let savings = expected_cold_cost - actual_hot_cost;

    let label = if is_measured { "Measured" } else { "Projected (no data)" };
    out.push_str("------------------------------------------------------------\n");
    out.push_str(&format!("Token Efficiency Analysis ({})\n", label));
    out.push_str("------------------------------------------------------------\n");
    out.push_str(&format!("Avg Prefix Size (tokens):        {:.0}\n", prefix_size));
    out.push_str(&format!("Estimated Total Tokens Pushed:   {:.0} million\n", total_tokens_pushed / 1_000_000.0));
    out.push_str(&format!("Expected Cold Cache Cost:        ${:.2}\n", expected_cold_cost));
    out.push_str(&format!("Actual Hot Cache Cost (with Prefix): ${:.2}\n", actual_hot_cost));
    out.push_str(&format!("Cache Writes / Reads:            {:.0} / {:.0}\n", writes, reads));
    out.push_str("------------------------------------------------------------\n");
    out.push_str(&format!("TOTAL SAVINGS:                   +${:.2}\n", savings));
    out.push_str("============================================================\n");
    out
}

pub fn run_cli(args: Vec<String>, db_path: PathBuf) -> Result<(String, i32), String> {
    if args.len() < 2 {
        return Err("Usage: yolo <command> [args...]".to_string());
    }

    let command = Command::from_arg(args[1].as_str());
    match command {
        Some(Command::Report) => {
            if !db_path.exists() {
                return Err("No telemetry data found! Connect the MCP server and run some tasks first.".to_string());
            }

            let conn = Connection::open(&db_path).map_err(|e| format!("Failed to open Telemetry DB: {}", e))?;

            let count_query = "SELECT COUNT(*) FROM tool_usage";
            let total_calls: i64 = conn.query_row(count_query, [], |row| row.get(0)).unwrap_or(0);

            let compile_query = "SELECT COUNT(*) FROM tool_usage WHERE tool_name = 'compile_context'";
            let compile_calls: i64 = conn.query_row(compile_query, [], |row| row.get(0)).unwrap_or(0);

            // Query measured avg output length; fall back to 80K if no data
            let avg_output_length: f64 = conn
                .query_row(
                    "SELECT AVG(output_length) FROM tool_usage WHERE tool_name = 'compile_context' AND output_length > 0",
                    [],
                    |row| row.get::<_, f64>(0),
                )
                .unwrap_or(80_000.0);

            // Query unique sessions for write/read split; None if column missing
            let unique_sessions: Option<i64> = conn
                .query_row(
                    "SELECT COUNT(DISTINCT session_id) FROM tool_usage WHERE tool_name = 'compile_context'",
                    [],
                    |row| row.get(0),
                )
                .ok()
                .filter(|&v: &i64| v > 0);

            Ok((generate_report(total_calls, compile_calls, avg_output_length, unique_sessions), 0))
        }
        Some(Command::ReportTokens) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            token_economics_report::execute(&args, &cwd, &db_path)
        }
        Some(Command::UpdateState) => {
            if args.len() < 3 {
                return Err("Usage: yolo update-state <file_path>".to_string());
            }
            state_updater::update_state(&args[2]).map(|s| (s, 0))
        }
        Some(Command::Statusline) => {
            let mut stdin_json = String::new();
            let _ = std::io::stdin().read_to_string(&mut stdin_json);
            if stdin_json.is_empty() {
                stdin_json = "{}".to_string();
            }
            statusline::render_statusline(&stdin_json).map(|s| (s, 0))
        }
        Some(Command::HardGate) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            hard_gate::execute_gate(&args, &cwd)
        }
        Some(Command::SessionStart) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            session_start::execute_session_start(&args, &cwd)
        }
        Some(Command::MetricsReport) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            let phase_filter = if args.len() > 2 { Some(args[2].as_str()) } else { None };
            metrics_report::generate_metrics_report(&cwd, phase_filter)
        }
        Some(Command::TokenBaseline) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            token_baseline::execute(&args, &cwd)
        }
        Some(Command::Bootstrap) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            // Dispatch bootstrap subcommands; fall through to bootstrap_claude for CLAUDE.md
            if args.len() > 2 {
                match args[2].as_str() {
                    "project" => return bootstrap_project::execute(&args[2..], &cwd),
                    "requirements" => return bootstrap_requirements::execute(&args[2..], &cwd),
                    "roadmap" => return bootstrap_roadmap::execute(&args[2..], &cwd),
                    "state" => return bootstrap_state::execute(&args[2..], &cwd),
                    _ => {} // Not a known subcommand, fall through to bootstrap_claude
                }
            }
            bootstrap_claude::execute(&args, &cwd)
        }
        Some(Command::SuggestNext) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            suggest_next::execute(&args, &cwd)
        }
        Some(Command::ListTodos) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            list_todos::execute(&args, &cwd)
        }
        Some(Command::PhaseDetect) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            phase_detect::execute(&args, &cwd)
        }
        Some(Command::DetectStack) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            detect_stack::execute(&args, &cwd)
        }
        Some(Command::Infer) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            infer_project_context::execute(&args, &cwd)
        }
        Some(Command::PlanningGit) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            planning_git::execute(&args, &cwd)
        }
        Some(Command::ResolveModel) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            resolve_model::execute(&args, &cwd)
        }
        Some(Command::ResolveTurns) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            resolve_turns::execute(&args, &cwd)
        }
        Some(Command::LogEvent) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            log_event::execute(&args, &cwd)
        }
        Some(Command::CollectMetrics) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            collect_metrics::execute(&args, &cwd)
        }
        Some(Command::GenerateContract) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            generate_contract::execute(&args, &cwd)
        }
        Some(Command::ContractRevision) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            contract_revision::execute(&args, &cwd)
        }
        Some(Command::AssessRisk) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            assess_plan_risk::execute(&args, &cwd)
        }
        Some(Command::GatePolicy) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            resolve_gate_policy::execute(&args, &cwd)
        }
        Some(Command::SmartRoute) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            smart_route::execute(&args, &cwd)
        }
        Some(Command::RouteMonorepo) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            route_monorepo::execute(&args, &cwd)
        }
        Some(Command::SnapshotResume) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            snapshot_resume::execute(&args[2..].to_vec(), &cwd)
        }
        Some(Command::PersistState) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            persist_state::execute(&args[2..].to_vec(), &cwd)
        }
        Some(Command::RecoverState) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            recover_state::execute(&args[2..].to_vec(), &cwd)
        }
        Some(Command::RollingSummary) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            compile_rolling_summary::execute(&args[2..].to_vec(), &cwd)
        }
        Some(Command::GsdIndex) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            generate_gsd_index::execute(&args, &cwd)
        }
        Some(Command::Incidents) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            generate_incidents::execute(&args, &cwd)
        }
        Some(Command::Artifact) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            artifact_registry::execute(&args, &cwd)
        }
        Some(Command::GsdSummary) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            infer_gsd_summary::execute(&args, &cwd)
        }
        Some(Command::CacheContext) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            cache_context::execute(&args, &cwd)
        }
        Some(Command::CacheNuke) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            cache_nuke::execute(&args, &cwd)
        }
        Some(Command::DeltaFiles) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            delta_files::execute(&args, &cwd)
        }
        Some(Command::MapStaleness) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            hooks::map_staleness::execute(&args, &cwd)
        }
        Some(Command::TokenBudget) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            token_budget::execute(&args, &cwd)
        }
        Some(Command::Lock) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            lock_lite::execute(&args, &cwd)
        }
        Some(Command::LeaseLock) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            lease_lock::execute(&args, &cwd)
        }
        Some(Command::TwoPhaseComplete) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            two_phase_complete::execute(&args, &cwd)
        }
        Some(Command::HelpOutput) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            help_output::execute(&args[1..], &cwd)
        }
        Some(Command::BumpVersion) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            bump_version::execute(&args, &cwd)
        }
        Some(Command::Doctor) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            doctor_cleanup::execute(&args, &cwd)
        }
        Some(Command::AutoRepair) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            auto_repair::execute(&args, &cwd)
        }
        Some(Command::RolloutStage) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            rollout_stage::execute(&args, &cwd)
        }
        Some(Command::Verify) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            verify::execute(&args, &cwd)
        }
        Some(Command::Hook) => {
            if args.len() < 3 {
                return Err("Usage: yolo hook <event-name>".to_string());
            }
            let event_name = &args[2];

            // Register SIGHUP handler for cleanup
            let sighup_flag = hooks::sighup::register_sighup_handler().ok();

            // Read stdin (hook JSON context from Claude Code)
            let mut stdin_json = String::new();
            let _ = std::io::stdin().read_to_string(&mut stdin_json);
            if stdin_json.is_empty() {
                stdin_json = "{}".to_string();
            }

            let result = hooks::dispatcher::dispatch_from_cli(event_name, &stdin_json);

            // Check if SIGHUP was received during dispatch
            if let Some(ref flag) = sighup_flag {
                if hooks::sighup::check_and_handle_sighup(flag.as_ref()) {
                    return Ok(("".to_string(), 1));
                }
            }

            result
        }
        Some(Command::InstallHooks) => {
            install_hooks::install_hooks().map(|s| (s, 0))
        }
        Some(Command::MigrateConfig) => {
            if args.len() < 3 {
                return Err("Usage: yolo migrate-config <config_path> [defaults_path]".to_string());
            }
            let config_path = std::path::Path::new(&args[2]);
            let defaults_path_buf;
            let defaults_path = if args.len() > 3 && !args[3].starts_with("--") {
                std::path::Path::new(&args[3])
            } else {
                // Resolve from CLAUDE_PLUGIN_ROOT or binary location
                let plugin_root = env::var("CLAUDE_PLUGIN_ROOT").unwrap_or_else(|_| {
                    env::current_exe()
                        .ok()
                        .and_then(|p| p.parent().map(|d| d.parent().unwrap_or(d).to_path_buf()))
                        .unwrap_or_else(|| PathBuf::from("."))
                        .to_string_lossy()
                        .to_string()
                });
                defaults_path_buf = PathBuf::from(&plugin_root).join("config").join("defaults.json");
                defaults_path_buf.as_path()
            };
            let print_added = args.iter().any(|a| a == "--print-added");
            match migrate_config::migrate_config(config_path, defaults_path) {
                Ok(added) => {
                    if print_added {
                        Ok((format!("{}", added), 0))
                    } else {
                        Ok((format!("Config migrated ({} keys added)", added), 0))
                    }
                }
                Err(e) => Err(e),
            }
        }
        Some(Command::InvalidateTierCache) => {
            match tier_context::invalidate_tier_cache() {
                Ok(()) => Ok(("Tier cache invalidated".to_string(), 0)),
                Err(e) => Ok((format!("Cache invalidation failed (non-fatal): {}", e), 0)),
            }
        }
        Some(Command::CompressContext) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            compress_context::execute(&args, &cwd)
        }
        Some(Command::PruneCompleted) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            prune_completed::execute(&args, &cwd)
        }
        Some(Command::CompileContext) => {
            if args.len() < 4 {
                return Err("Usage: yolo compile-context <phase> <role> <phases_dir> [plan_path]".to_string());
            }
            let phase = &args[2];
            let role = &args[3];
            let phases_dir = std::path::Path::new(&args[4]);
            let plan_path_opt = args.get(5).map(|s| std::path::Path::new(s.as_str()));

            let planning_dir = PathBuf::from(".yolo-planning");
            let phase_i64 = phase.parse::<i64>().unwrap_or(0);
            let ctx = tier_context::build_tiered_context(
                &planning_dir, role, phase_i64, Some(phases_dir), plan_path_opt,
            );

            let mut context = ctx.combined;
            context.push_str("\n--- END COMPILED CONTEXT ---\n");

            // Write to .context-{role}.md in phases_dir
            let output_path = phases_dir.join(format!(".context-{}.md", role));
            match std::fs::write(&output_path, &context) {
                Ok(_) => Ok((format!("Wrote {}", output_path.display()), 0)),
                Err(_) => {
                    // Fall back to stdout
                    Ok((context, 0))
                }
            }
        }
        Some(Command::InstallMcp) => {
            // Locate install-yolo-mcp.sh relative to plugin root or binary
            let plugin_root = env::var("CLAUDE_PLUGIN_ROOT").unwrap_or_else(|_| {
                env::current_exe()
                    .ok()
                    .and_then(|p| p.parent().map(|d| d.parent().unwrap_or(d).to_path_buf()))
                    .unwrap_or_else(|| PathBuf::from("."))
                    .to_string_lossy()
                    .to_string()
            });
            let script_path = PathBuf::from(&plugin_root).join("install-yolo-mcp.sh");
            if !script_path.exists() {
                return Err(format!("install-yolo-mcp.sh not found at {}", script_path.display()));
            }
            let mut cmd = std::process::Command::new("bash");
            cmd.arg(&script_path);
            // Pass through any extra args
            for arg in &args[2..] {
                cmd.arg(arg);
            }
            let output = cmd.output().map_err(|e| format!("Failed to run install script: {e}"))?;
            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();
            let combined = if stderr.is_empty() { stdout } else { format!("{}\n{}", stdout, stderr) };
            if output.status.success() {
                Ok((combined, 0))
            } else {
                Ok((combined, output.status.code().unwrap_or(1)))
            }
        }
        Some(Command::MigrateOrphanedState) => {
            if args.len() < 3 {
                return Err("Usage: yolo migrate-orphaned-state <planning_dir>".to_string());
            }
            let planning_dir = std::path::Path::new(&args[2]);
            match migrate_orphaned_state::migrate_orphaned_state(planning_dir) {
                Ok(true) => Ok(("Migrated".to_string(), 0)),
                Ok(false) => Ok(("No migration needed".to_string(), 0)),
                Err(e) => Err(e),
            }
        }
        Some(Command::CleanStaleTeams) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            let claude_dir = cwd.join(".claude");
            let log_file = cwd.join(".yolo-planning").join("clean-stale-teams.log");
            let (teams, tasks) = clean_stale_teams::clean_stale_teams(&claude_dir, &log_file);
            Ok((format!("Cleaned {} teams, {} task dirs", teams, tasks), 0))
        }
        Some(Command::TmuxWatchdog) => {
            match tmux_watchdog::get_tmux_session() {
                Some(session) => Ok((format!("tmux session: {}", session), 0)),
                None => Ok(("Not running in tmux".to_string(), 0)),
            }
        }
        Some(Command::VerifyInitTodo) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            verify_init_todo::execute(&args, &cwd)
        }
        Some(Command::VerifyVibe) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            verify_vibe::execute(&args, &cwd)
        }
        Some(Command::VerifyClaudeBootstrap) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            verify_claude_bootstrap::execute(&args, &cwd)
        }
        Some(Command::PrePush) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            pre_push_hook::execute(&args, &cwd)
        }
        Some(Command::ValidatePlan) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            validate_plan::execute(&args, &cwd)
        }
        Some(Command::ReviewPlan) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            review_plan::execute(&args, &cwd)
        }
        Some(Command::CheckRegression) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            check_regression::execute(&args, &cwd)
        }
        Some(Command::CommitLint) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            commit_lint::execute(&args, &cwd)
        }
        Some(Command::DiffAgainstPlan) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            diff_against_plan::execute(&args, &cwd)
        }
        Some(Command::ValidateRequirements) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            validate_requirements::execute(&args, &cwd)
        }
        Some(Command::VerifyPlanCompletion) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            verify_plan_completion::execute(&args, &cwd)
        }
        Some(Command::ParseFrontmatter) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            parse_frontmatter::execute(&args, &cwd)
        }
        Some(Command::ResolvePluginRoot) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            resolve_plugin_root::execute(&args, &cwd)
        }
        Some(Command::ConfigRead) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            config_read::execute(&args, &cwd)
        }
        Some(Command::CompileProgress) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            compile_progress::execute(&args, &cwd)
        }
        Some(Command::GitState) => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            git_state::execute(&args, &cwd)
        }
        None => {
            let suggestion = Command::suggest(&args[1]);
            let msg = if let Some(s) = suggestion {
                format!("Unknown command: '{}'. Did you mean '{}'?", args[1], s)
            } else {
                format!("Unknown command: '{}'", args[1])
            };
            Err(msg)
        }
    }
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_report() {
        let report = generate_report(100, 50, 80_000.0, None);
        assert!(report.contains("Total Intercepted Tool Calls: 100"));
        assert!(report.contains("Context Compilations (Cache hits): 50"));
        assert!(report.contains("TOTAL SAVINGS"));
        assert!(report.contains("Projected (no data)"));
    }

    #[test]
    fn test_generate_report_measured() {
        let report = generate_report(100, 50, 45_000.0, Some(5));
        assert!(report.contains("Total Intercepted Tool Calls: 100"));
        assert!(report.contains("Measured"));
        assert!(!report.contains("Projected"));
        assert!(report.contains("Avg Prefix Size (tokens):        45000"));
        // With 5 sessions: writes=5, reads=45
        assert!(report.contains("Cache Writes / Reads:            5 / 45"));
    }

    #[test]
    fn test_run_cli_errors() {
        let path = std::env::temp_dir().join(format!("yolo-test-cli-missing-{}.db", std::process::id()));
        // missing args
        assert!(run_cli(vec!["yolo".into()], path.clone()).is_err());
        // wrong command — should get "Unknown command: 'unknown'"
        let err = run_cli(vec!["yolo".into(), "unknown".into()], path.clone()).unwrap_err();
        assert!(err.contains("Unknown command: 'unknown'"), "got: {}", err);
        // valid command, missing db
        assert!(run_cli(vec!["yolo".into(), "report".into()], path.clone()).is_err());
    }

    #[test]
    fn test_run_cli_success() {
        let path = std::env::temp_dir().join(format!("yolo-test-cli-success-{}.db", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let conn = Connection::open(&path).unwrap();
        conn.execute(
            "CREATE TABLE tool_usage (tool_name TEXT, output_length INTEGER, session_id TEXT)",
            [],
        ).unwrap();
        conn.execute(
            "INSERT INTO tool_usage (tool_name, output_length, session_id) VALUES ('compile_context', 50000, 'sess-1')",
            [],
        ).unwrap();

        let (report, code) = run_cli(vec!["yolo".into(), "report".into()], path.clone()).unwrap();
        assert!(report.contains("Total Intercepted Tool Calls: 1"));
        assert!(report.contains("Measured"));
        assert!(report.contains("Avg Prefix Size (tokens):        50000"));
        assert_eq!(code, 0);

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn test_routed_verify_commands() {
        let path = std::env::temp_dir().join(format!("yolo-test-route-{}.db", std::process::id()));
        // These should not return "Unknown command" errors
        for cmd in &["verify-init-todo", "verify-vibe", "pre-push", "clean-stale-teams", "tmux-watchdog", "verify-claude-bootstrap"] {
            let result = run_cli(vec!["yolo".into(), cmd.to_string()], path.clone());
            // May fail for other reasons, but should NOT be "Unknown command"
            if let Err(e) = &result {
                assert!(!e.contains("Unknown command"), "Command {} should be routed but got: {}", cmd, e);
            }
        }
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn test_command_from_arg_all_variants() {
        // Every canonical name must map to Some(Command)
        for name in Command::all_names() {
            assert!(Command::from_arg(name).is_some(), "from_arg({}) returned None", name);
        }
        // Alias
        assert_eq!(Command::from_arg("rollout"), Some(Command::RolloutStage));
    }

    #[test]
    fn test_command_from_arg_unknown() {
        assert_eq!(Command::from_arg("nonexistent"), None);
        assert_eq!(Command::from_arg(""), None);
        assert_eq!(Command::from_arg("zzzzz"), None);
    }

    #[test]
    fn test_command_name_roundtrip() {
        for name in Command::all_names() {
            let cmd = Command::from_arg(name).unwrap();
            assert_eq!(cmd.name(), *name, "roundtrip failed for {}", name);
        }
    }

    #[test]
    fn test_command_suggest_typo() {
        assert_eq!(Command::suggest("reprot"), Some("report"));
        assert_eq!(Command::suggest("reporr"), Some("report"));
        assert_eq!(Command::suggest("boostrap"), Some("bootstrap"));
        assert_eq!(Command::suggest("vrify"), Some("verify"));
    }

    #[test]
    fn test_command_suggest_no_match() {
        assert_eq!(Command::suggest("zzzzzzzzzzz"), None);
        assert_eq!(Command::suggest("xylophone"), None);
    }

    #[test]
    fn test_run_cli_did_you_mean() {
        let path = std::env::temp_dir().join(format!("yolo-test-suggest-{}.db", std::process::id()));
        let err = run_cli(vec!["yolo".into(), "reprot".into()], path.clone()).unwrap_err();
        assert!(err.contains("Did you mean 'report'"), "got: {}", err);
        let _ = std::fs::remove_file(&path);
    }
}
