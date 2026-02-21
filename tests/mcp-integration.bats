#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/.."
    export SERVER_PATH="$PROJECT_ROOT/yolo-mcp-server/target/release/yolo-mcp-server"
    export CLI_PATH="$PROJECT_ROOT/yolo-mcp-server/target/release/yolo"
}

@test "Rust MCP Server binary exists and is executable" {
    [ -x "$SERVER_PATH" ]
}

@test "Telemetry CLI binary exists and is executable" {
    [ -x "$CLI_PATH" ]
}

@test "Telemetry DB is created or exists" {
    # It might only be created on first run, so let's try running the CLI
    run "$CLI_PATH" report
    # Either it says "No telemetry data found" or it prints the dashboard.
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total Intercepted Tool Calls"* ]] || [[ "$output" == *"No telemetry data found"* ]]
}

@test "MCP Server accepts valid JSON-RPC request format over stdio" {
    # Send a simple JSON-RPC payload representing a valid structure, but an unknown tool
    input='{"jsonrpc": "2.0", "id": 1, "method": "test"}'

    # Run the server but feed it the input directly from string. We use a 1 second timeout to prevent hanging.
    # The server process will exit when stdin closes.
    run bash -c "echo '$input' | $SERVER_PATH"

    # We expect a JSON response back (even an error response because method 'test' isn't handled by standard tool calling,
    # but the point is the server doesn't crash on valid JSON).
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"jsonrpc\":\"2.0\""* ]]
}

@test "CLI compile-context output contains STABLE_PREFIX_END sentinel" {
    # Create minimal planning structure
    tmp="$BATS_TMPDIR/yolo-sentinel-test-$$"
    mkdir -p "$tmp/.yolo-planning/codebase"
    mkdir -p "$tmp/phases"
    echo "CONV" > "$tmp/.yolo-planning/codebase/CONVENTIONS.md"
    echo "ROAD" > "$tmp/.yolo-planning/ROADMAP.md"

    cd "$tmp"
    run "$CLI_PATH" compile-context 3 dev "$tmp/phases"
    [ "$status" -eq 0 ]

    # Read the output file
    output_file="$tmp/phases/.context-dev.md"
    [ -f "$output_file" ]
    content="$(cat "$output_file")"
    [[ "$content" == *"<!-- STABLE_PREFIX_END -->"* ]]

    rm -rf "$tmp"
}

@test "CLI compile-context stable header does NOT contain phase=" {
    tmp="$BATS_TMPDIR/yolo-header-test-$$"
    mkdir -p "$tmp/.yolo-planning/codebase"
    mkdir -p "$tmp/phases"
    echo "CONV" > "$tmp/.yolo-planning/codebase/CONVENTIONS.md"

    cd "$tmp"
    run "$CLI_PATH" compile-context 5 dev "$tmp/phases"
    [ "$status" -eq 0 ]

    output_file="$tmp/phases/.context-dev.md"
    [ -f "$output_file" ]
    content="$(cat "$output_file")"

    # Stable header should be "--- COMPILED CONTEXT (role=dev) ---" without phase=
    [[ "$content" == *"--- COMPILED CONTEXT (role=dev) ---"* ]]
    # Phase should appear in volatile tail header instead
    [[ "$content" == *"--- VOLATILE TAIL (phase=5) ---"* ]]

    rm -rf "$tmp"
}
