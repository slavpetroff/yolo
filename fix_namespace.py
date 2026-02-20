import os

# New namespaces
REPLACEMENTS = {
    "crate::telemetry": "crate::telemetry::db",
    "crate::telemetry::db::db": "crate::telemetry::db",
    "crate::telemetry::db::db::TelemetryDb": "crate::telemetry::db::TelemetryDb",
    "crate::telemetry::TelemetryDb": "crate::telemetry::db::TelemetryDb",
    "crate::jsonrpc": "crate::mcp::jsonrpc",
    "crate::tools": "crate::mcp::tools",
    "crate::statusline": "crate::commands::statusline",
    "crate::state_updater": "crate::commands::state_updater",
    "crate::session_start": "crate::commands::session_start",
    "crate::infer_project_context": "crate::commands::infer_project_context",
    "crate::hard_gate": "crate::commands::hard_gate",
    "crate::token_baseline": "crate::commands::token_baseline",
    "crate::metrics_report": "crate::commands::metrics_report",
    "crate::suggest_next": "crate::commands::suggest_next",
    "crate::list_todos": "crate::commands::list_todos",
    "crate::bootstrap_claude": "crate::commands::bootstrap_claude",
    "crate::phase_detect": "crate::commands::phase_detect",
    "crate::detect_stack": "crate::commands::detect_stack"
}

target_dir = "yolo-mcp-server/src"

for root, _, files in os.walk(target_dir):
    for f in files:
        if f.endswith(".rs"):
            path = os.path.join(root, f)
            with open(path, "r") as file:
                content = file.read()
            
            new_content = content
            for old, new in REPLACEMENTS.items():
                new_content = new_content.replace(old, new)
                
            if "crate::commands" in new_content:
                new_content = new_content.replace("crate::commands::commands::", "crate::commands::")
            if "crate::mcp::mcp::" in new_content:
                new_content = new_content.replace("crate::mcp::mcp::", "crate::mcp::")
            
            with open(path, "w") as file:
                file.write(new_content)
                
print("Refactoring complete.")
