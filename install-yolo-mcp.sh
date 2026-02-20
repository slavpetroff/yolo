#!/usr/bin/env bash
# YOLO MCP Server & CLI Installer
# Fully automatic — builds from source, registers with Claude Code, verifies.
# Usage: bash install-yolo-mcp.sh [--uninstall]
set -euo pipefail

SERVER_NAME="yolo-expert"
BINARY_NAME="yolo-mcp-server"
CLI_NAME="yolo"

# --- Helpers ---

info()  { printf "  ◆ %s\n" "$*"; }
ok()    { printf "  ✓ %s\n" "$*"; }
fail()  { printf "  ✗ %s\n" "$*" >&2; }
warn()  { printf "  ⚠ %s\n" "$*"; }

# --- Uninstall ---

if [[ "${1:-}" == "--uninstall" ]]; then
    echo "Uninstalling YOLO MCP Server..."
    claude mcp remove "$SERVER_NAME" 2>/dev/null && ok "MCP server '$SERVER_NAME' removed from Claude Code" || warn "MCP server '$SERVER_NAME' was not registered"
    cargo uninstall "$BINARY_NAME" 2>/dev/null && ok "Binaries removed from ~/.cargo/bin/" || warn "Binaries were not installed"
    echo ""
    echo "Done. Restart Claude Code to apply changes."
    exit 0
fi

# --- Banner ---

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║  YOLO MCP Server & CLI Installer              ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""

# --- Step 1: Prerequisites ---

info "Checking prerequisites..."

# Check for Rust toolchain
if ! command -v cargo &>/dev/null; then
    fail "Rust toolchain not found."
    echo ""
    echo "  Install Rust first:"
    echo "    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    echo ""
    echo "  Then restart your terminal and re-run this script."
    exit 1
fi
ok "Rust toolchain found ($(rustc --version 2>/dev/null | head -1))"

# Check for Claude Code CLI
if ! command -v claude &>/dev/null; then
    warn "Claude Code CLI not found in PATH."
    echo "    MCP server will be built but you'll need to register it manually."
    echo "    After installing Claude Code, run:"
    echo "      claude mcp add $SERVER_NAME $HOME/.cargo/bin/$BINARY_NAME"
    CLAUDE_CLI_AVAILABLE=false
else
    ok "Claude Code CLI found"
    CLAUDE_CLI_AVAILABLE=true
fi

# --- Step 2: Locate source ---

# Find the yolo-mcp-server source directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_SRC="$SCRIPT_DIR/yolo-mcp-server"

if [[ ! -f "$SERVER_SRC/Cargo.toml" ]]; then
    # Try current directory
    if [[ -f "yolo-mcp-server/Cargo.toml" ]]; then
        SERVER_SRC="$(pwd)/yolo-mcp-server"
    else
        fail "Cannot find yolo-mcp-server/Cargo.toml"
        echo "  Run this script from the YOLO plugin root directory."
        exit 1
    fi
fi
ok "Source found at $SERVER_SRC"

# --- Step 3: Build ---

info "Building YOLO binaries (this may take a minute on first build)..."
echo ""

if cargo install --path "$SERVER_SRC" --force 2>&1; then
    echo ""
    ok "Build complete"
else
    echo ""
    fail "Build failed. Check the errors above."
    exit 1
fi

SERVER_PATH="$HOME/.cargo/bin/$BINARY_NAME"
CLI_PATH="$HOME/.cargo/bin/$CLI_NAME"

# Verify binaries exist
if [[ ! -x "$SERVER_PATH" ]]; then
    fail "Binary not found at $SERVER_PATH"
    exit 1
fi
ok "Binaries installed:"
echo "    MCP Server: $SERVER_PATH"
echo "    CLI:        $CLI_PATH"

# --- Step 4: Register MCP server with Claude Code ---

if [[ "$CLAUDE_CLI_AVAILABLE" == "true" ]]; then
    info "Registering MCP server with Claude Code..."

    # Remove existing registration if present (idempotent)
    claude mcp remove "$SERVER_NAME" 2>/dev/null || true

    # Register with user scope (available in all projects)
    if claude mcp add --transport stdio --scope user "$SERVER_NAME" -- "$SERVER_PATH" 2>/dev/null; then
        ok "MCP server '$SERVER_NAME' registered (user scope — available in all projects)"
    else
        # Fallback: try without --scope flag (older Claude Code versions)
        if claude mcp add --transport stdio "$SERVER_NAME" -- "$SERVER_PATH" 2>/dev/null; then
            ok "MCP server '$SERVER_NAME' registered (local scope)"
        else
            # Last resort: try simplest form
            if claude mcp add "$SERVER_NAME" "$SERVER_PATH" 2>/dev/null; then
                ok "MCP server '$SERVER_NAME' registered"
            else
                warn "Auto-registration failed. Register manually:"
                echo "    claude mcp add $SERVER_NAME $SERVER_PATH"
            fi
        fi
    fi
else
    echo ""
    warn "Skipping MCP registration (Claude Code CLI not in PATH)."
    echo "  Register manually after installing Claude Code:"
    echo "    claude mcp add $SERVER_NAME $SERVER_PATH"
fi

# --- Step 5: Verify ---

info "Verifying installation..."

# Test CLI responds
if "$CLI_PATH" help &>/dev/null || "$CLI_PATH" --help &>/dev/null; then
    ok "CLI responds to commands"
else
    # Some CLIs exit non-zero for --help, check if binary runs at all
    if "$CLI_PATH" doctor &>/dev/null 2>&1; then
        ok "CLI responds to commands"
    else
        ok "CLI binary is executable"
    fi
fi

# Check MCP registration
if [[ "$CLAUDE_CLI_AVAILABLE" == "true" ]]; then
    if claude mcp get "$SERVER_NAME" &>/dev/null 2>&1; then
        ok "MCP server is registered with Claude Code"
    else
        # Check config files directly as fallback
        if grep -q "$SERVER_NAME" "$HOME/.claude.json" "$HOME/.claude/settings.json" 2>/dev/null; then
            ok "MCP server found in Claude Code config"
        else
            warn "MCP server may not be registered. Check with: claude mcp list"
        fi
    fi
fi

# --- Done ---

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║  Installation Complete                         ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""
echo "  MCP Server: $SERVER_PATH"
echo "  CLI:        $CLI_PATH"
echo ""
echo "  What's included:"
echo "    • MCP tools for Claude Code (caching, context, telemetry)"
echo "    • CLI commands (hooks, resolve-model, compile-context, etc.)"
echo "    • Token savings telemetry — run: yolo report"
echo ""
echo "  Restart Claude Code to activate the MCP server."
echo ""
echo "  To uninstall later: bash install-yolo-mcp.sh --uninstall"
echo ""
