---
phase: 01
plan: 04
title: "Extend bump_version.rs with TOML support and --major/--minor flags"
wave: 2
depends_on: [01, 02]
must_haves:
  - "bump_version.rs reads and writes Cargo.toml version via toml_edit"
  - "VersionFiles includes Cargo.toml in its file list"
  - "--major flag bumps X.Y.Z to (X+1).0.0"
  - "--minor flag bumps X.Y.Z to X.(Y+1).0"
  - ".claude-plugin/marketplace.json removed from VersionFiles"
  - "All existing tests pass plus new tests for TOML and major/minor"
  - "cargo clippy clean"
---

# Plan 04: Extend bump_version.rs with TOML support and --major/--minor flags

**Files modified:** `yolo-mcp-server/src/commands/bump_version.rs`

This is the core Rust implementation plan. It depends on Plan 01 (toml_edit dep available) and Plan 02 (.claude-plugin/marketplace.json deleted). It adds TOML read/write for Cargo.toml, --major/--minor flags, removes the deleted marketplace.json reference, and adds comprehensive tests.

## Task 1: Add TOML read/write helpers

**Files:** `yolo-mcp-server/src/commands/bump_version.rs`

**What to do:**
1. Add `use std::path::PathBuf;` if not already present (it is, via `Path`).
2. Add a new function `read_toml_version(path: &Path) -> Result<String, String>` that:
   - Reads the file content as a string.
   - Parses it with `toml_edit::DocumentMut`.
   - Extracts `doc["package"]["version"]` as a string.
   - Returns the version or an error.
3. Add a new function `write_toml_version(path: &Path, version: &str) -> Result<(), String>` that:
   - Reads the file content as a string.
   - Parses it with `toml_edit::DocumentMut`.
   - Sets `doc["package"]["version"] = toml_edit::value(version)`.
   - Writes the document back to the file (preserves formatting).
   - Returns Ok or an error.

## Task 2: Update VersionFiles to include Cargo.toml and remove duplicate marketplace.json

**Files:** `yolo-mcp-server/src/commands/bump_version.rs`

**What to do:**
1. Add a `toml_files: Vec<&'static str>` field to the `VersionFiles` struct.
2. In `version_files()`, remove the `(".claude-plugin/marketplace.json", "/plugins/0/version")` entry from `json_files`.
3. In `version_files()`, add `toml_files: vec!["yolo-mcp-server/Cargo.toml"]`.
4. The resulting `version_files()` should return:
   ```rust
   VersionFiles {
       version_file: "VERSION",
       json_files: vec![
           (".claude-plugin/plugin.json", "/version"),
           ("marketplace.json", "/plugins/0/version"),
       ],
       toml_files: vec!["yolo-mcp-server/Cargo.toml"],
   }
   ```

## Task 3: Integrate TOML into verify_versions and bump_version

**Files:** `yolo-mcp-server/src/commands/bump_version.rs`

**What to do:**
1. In `verify_versions()`, after the JSON files loop, add a loop for TOML files:
   ```rust
   for path in &vf.toml_files {
       let full = cwd.join(path);
       match read_toml_version(&full) {
           Ok(v) => versions.push((path.to_string(), v)),
           Err(e) => errors.push(e),
       }
   }
   ```
2. In `bump_version()`, after the JSON files loop, add a loop for TOML files:
   ```rust
   for path in &vf.toml_files {
       let full = cwd.join(path);
       if full.exists() {
           let old = read_toml_version(&full).unwrap_or_else(|_| "unknown".to_string());
           write_toml_version(&full, &new_version)?;
           files_updated.push(json!({"path": path, "old": old, "new": new_version}));
           changed.push(path.to_string());
       }
   }
   ```

## Task 4: Add --major and --minor flags

**Files:** `yolo-mcp-server/src/commands/bump_version.rs`

**What to do:**
1. Add two new helper functions:
   ```rust
   fn increment_major(version: &str) -> String {
       let parts: Vec<&str> = version.split('.').collect();
       if parts.len() >= 1 {
           if let Ok(major) = parts[0].parse::<u64>() {
               return format!("{}.0.0", major + 1);
           }
       }
       format!("{}.1", version)
   }

   fn increment_minor(version: &str) -> String {
       let parts: Vec<&str> = version.split('.').collect();
       if parts.len() >= 2 {
           if let Ok(major) = parts[0].parse::<u64>() {
               if let Ok(minor) = parts[1].parse::<u64>() {
                   return format!("{}.{}.0", major, minor + 1);
               }
           }
       }
       format!("{}.1", version)
   }
   ```
2. In `execute()`, parse new flags:
   ```rust
   let major = args.iter().any(|a| a == "--major");
   let minor = args.iter().any(|a| a == "--minor");
   ```
3. If `major` and `minor` are both set, return an error: `"Cannot use both --major and --minor"`.
4. Pass `major` and `minor` to `bump_version()` by updating its signature to `bump_version(cwd, offline, major, minor, start)`.
5. In `bump_version()`, replace the `increment_patch(base_version)` call with:
   ```rust
   let new_version = if major {
       increment_major(base_version)
   } else if minor {
       increment_minor(base_version)
   } else {
       increment_patch(base_version)
   };
   ```
6. Add `"bump_type"` to the response delta: `"patch"`, `"minor"`, or `"major"`.

## Task 5: Update tests for TOML support, --major/--minor, and removed marketplace.json

**Files:** `yolo-mcp-server/src/commands/bump_version.rs`

**What to do:**
1. Update `setup_test_env()` to:
   - Remove the `.claude-plugin/marketplace.json` creation.
   - Add a `yolo-mcp-server/Cargo.toml` file:
     ```rust
     let cargo_dir = dir.path().join("yolo-mcp-server");
     fs::create_dir_all(&cargo_dir).unwrap();
     fs::write(
         cargo_dir.join("Cargo.toml"),
         "[package]\nname = \"yolo-mcp-server\"\nversion = \"1.2.3\"\nedition = \"2024\"\n",
     ).unwrap();
     ```
2. Update `test_verify_all_match` to verify Cargo.toml is now included in version checks.
3. Update `test_bump_offline` to verify Cargo.toml gets updated. Add:
   ```rust
   let cargo_content = fs::read_to_string(dir.path().join("yolo-mcp-server/Cargo.toml")).unwrap();
   assert!(cargo_content.contains("version = \"1.2.4\""));
   ```
   Also remove the assertion for `.claude-plugin/marketplace.json`.
4. Add new tests:
   ```rust
   #[test]
   fn test_increment_major() {
       assert_eq!(increment_major("1.2.3"), "2.0.0");
       assert_eq!(increment_major("0.9.9"), "1.0.0");
   }

   #[test]
   fn test_increment_minor() {
       assert_eq!(increment_minor("1.2.3"), "1.3.0");
       assert_eq!(increment_minor("0.0.1"), "0.1.0");
   }

   #[test]
   fn test_bump_major_flag() {
       let dir = setup_test_env();
       let (output, code) = bump_version(dir.path(), true, true, false, Instant::now()).unwrap();
       assert_eq!(code, 0);
       let j: Value = serde_json::from_str(&output).unwrap();
       assert_eq!(j["delta"]["new_version"], "2.0.0");
       assert_eq!(j["delta"]["bump_type"], "major");
   }

   #[test]
   fn test_bump_minor_flag() {
       let dir = setup_test_env();
       let (output, code) = bump_version(dir.path(), true, false, true, Instant::now()).unwrap();
       assert_eq!(code, 0);
       let j: Value = serde_json::from_str(&output).unwrap();
       assert_eq!(j["delta"]["new_version"], "1.3.0");
       assert_eq!(j["delta"]["bump_type"], "minor");
   }

   #[test]
   fn test_toml_read_write() {
       let dir = TempDir::new().unwrap();
       let path = dir.path().join("Cargo.toml");
       fs::write(&path, "[package]\nname = \"test\"\nversion = \"1.0.0\"\n").unwrap();
       assert_eq!(read_toml_version(&path).unwrap(), "1.0.0");
       write_toml_version(&path, "2.0.0").unwrap();
       assert_eq!(read_toml_version(&path).unwrap(), "2.0.0");
       // Verify formatting preserved
       let content = fs::read_to_string(&path).unwrap();
       assert!(content.contains("name = \"test\""));
   }

   #[test]
   fn test_major_minor_conflict() {
       let dir = setup_test_env();
       let args: Vec<String> = vec!["yolo".into(), "bump-version".into(), "--major".into(), "--minor".into()];
       let result = execute(&args, dir.path());
       assert!(result.is_err() || {
           let (_, code) = result.unwrap();
           code != 0
       });
   }
   ```
5. Update existing tests that call `bump_version()` directly to use the new signature: `bump_version(path, offline, false, false, start)`.
6. Run `cargo test` and `cargo clippy` to verify everything passes clean.

**Commit:** `feat(bump-version): add Cargo.toml sync via toml_edit and --major/--minor flags`
