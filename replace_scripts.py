import os
import re

replacements = {
    # Markdown command scripts
    r'bash \$\{CLAUDE_PLUGIN_ROOT\}/scripts/suggest-next\.sh': r'${CLAUDE_PLUGIN_ROOT}/yolo-mcp-server/target/release/yolo suggest-next',
    r'bash \$\{CLAUDE_PLUGIN_ROOT\}/scripts/bootstrap/bootstrap-claude\.sh': r'${CLAUDE_PLUGIN_ROOT}/yolo-mcp-server/target/release/yolo bootstrap',
    r'bash \$\{CLAUDE_PLUGIN_ROOT:-\$\(ls -1d "\$\{CLAUDE_CONFIG_DIR:-\$HOME/\.claude\}"/plugins/cache/yolo-marketplace/yolo/\* 2>/dev/null \| \(sort -V 2>/dev/null \|\| sort -t\. -k1,1n -k2,2n -k3,3n\) \| tail -1\)\}/scripts/phase-detect\.sh': r'${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/yolo-marketplace/yolo/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}/yolo-mcp-server/target/release/yolo phase-detect',
    r'bash \$\{CLAUDE_PLUGIN_ROOT:-\$\(ls -1d "\$\{CLAUDE_CONFIG_DIR:-\$HOME/\.claude\}"/plugins/cache/yolo-marketplace/yolo/\* 2>/dev/null \| \(sort -V 2>/dev/null \|\| sort -t\. -k1,1n -k2,2n -k3,3n\) \| tail -1\)\}/scripts/detect-stack\.sh': r'${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/yolo-marketplace/yolo/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}/yolo-mcp-server/target/release/yolo detect-stack',
    r'bash \$\{CLAUDE_PLUGIN_ROOT\}/scripts/list-todos\.sh': r'${CLAUDE_PLUGIN_ROOT}/yolo-mcp-server/target/release/yolo list-todos',
    r'bash \$\{CLAUDE_PLUGIN_ROOT\}/scripts/infer-project-context\.sh': r'${CLAUDE_PLUGIN_ROOT}/yolo-mcp-server/target/release/yolo infer',
    r'bash \$\{CLAUDE_PLUGIN_ROOT\}/scripts/token-baseline\.sh': r'${CLAUDE_PLUGIN_ROOT}/yolo-mcp-server/target/release/yolo token-baseline',
    r'bash \$\{CLAUDE_PLUGIN_ROOT\}/scripts/metrics-report\.sh': r'${CLAUDE_PLUGIN_ROOT}/yolo-mcp-server/target/release/yolo metrics-report',
    r'bash \$\{CLAUDE_PLUGIN_ROOT\}/scripts/state-updater\.sh': r'${CLAUDE_PLUGIN_ROOT}/yolo-mcp-server/target/release/yolo update-state',
    r'bash \$\{CLAUDE_PLUGIN_ROOT\}/scripts/yolo-statusline\.sh': r'${CLAUDE_PLUGIN_ROOT}/yolo-mcp-server/target/release/yolo statusline',
    
    # BATS tests
    r'bash "\$SCRIPTS_DIR/suggest-next\.sh"': r'"$YOLO_BIN" suggest-next',
    r'bash "\$SCRIPTS_DIR/bootstrap/bootstrap-claude\.sh"': r'"$YOLO_BIN" bootstrap',
    r'bash "\$SCRIPTS_DIR/phase-detect\.sh"': r'"$YOLO_BIN" phase-detect',
    r'bash "\$SCRIPTS_DIR/detect-stack\.sh"': r'"$YOLO_BIN" detect-stack',
    r'bash "\$SCRIPTS_DIR/list-todos\.sh"': r'"$YOLO_BIN" list-todos',
    r'bash "\$SCRIPTS_DIR/infer-project-context\.sh"': r'"$YOLO_BIN" infer',
    r'bash "\$SCRIPTS_DIR/token-baseline\.sh"': r'"$YOLO_BIN" token-baseline',
    r'bash "\$SCRIPTS_DIR/metrics-report\.sh"': r'"$YOLO_BIN" metrics-report',
    r'bash "\$SCRIPTS_DIR/state-updater\.sh"': r'"$YOLO_BIN" update-state',
    r'bash "\$SCRIPTS_DIR/bash-guard\.sh"': r'"$YOLO_BIN" hard-gate bash_guard',
    r'bash "\$SCRIPTS_DIR/file-guard\.sh"': r'"$YOLO_BIN" hard-gate file_guard',
    r'bash "\$SCRIPTS_DIR/research-warn\.sh"': r'"$YOLO_BIN" hard-gate research_warn',
    r'bash "\$SCRIPTS_DIR/validate-commit\.sh"': r'"$YOLO_BIN" hard-gate validate_commit',

    # Other edge cases
    r'bash scripts/token-baseline\.sh': r'"$YOLO_BIN" token-baseline',
}

directories_to_scan = ['commands', 'tests', 'references', 'scripts']

for directory in directories_to_scan:
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.md') or file.endswith('.bats'):
                file_path = os.path.join(root, file)
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()

                original_content = content
                for pattern, replacement in replacements.items():
                    content = re.sub(pattern, replacement, content)

                if content != original_content:
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.write(content)
                    print(f"Updated {file_path}")
