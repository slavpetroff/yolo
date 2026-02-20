import re

with open("yolo-mcp-server/src/statusline.rs", "r") as f:
    content = f.read()

# Instead of set_current_dir at the end, use a scope/guard

content = content.replace(
    'let orig_dir = env::current_dir().unwrap();',
    'let orig_dir = env::current_dir().unwrap();\n        struct DirGuard(std::path::PathBuf);\n        impl Drop for DirGuard { fn drop(&mut self) { let _ = std::env::set_current_dir(&self.0); } }\n        let _guard = DirGuard(orig_dir.clone());'
)

# remove manual restores
content = re.sub(r'let _ = env::set_current_dir\(orig_dir\);\n\s*', '', content)

with open("yolo-mcp-server/src/statusline.rs", "w") as f:
    f.write(content)

with open("yolo-mcp-server/src/cli.rs", "r") as f:
    content2 = f.read()

content2 = content2.replace('Connection::open(&path).unwrap();', 'let conn = Connection::open(&path).unwrap();')
# Wait, I didn't verify the exact code in test_run_cli_success
