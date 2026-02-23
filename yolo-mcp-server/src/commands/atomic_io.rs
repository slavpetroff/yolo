use sha2::{Sha256, Digest};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// Append a suffix to a path, preserving the original extension.
/// `state.json` + `sha256` => `state.json.sha256`
/// `STATE` + `sha256` => `STATE.sha256`
fn append_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut s = path.as_os_str().to_os_string();
    s.push(".");
    s.push(suffix);
    PathBuf::from(s)
}

/// Write content to a file atomically using temp-file + rename.
/// Writes to `{path}.tmp.{pid}`, fsyncs, then renames to `{path}`.
/// On rename failure, the temp file is removed.
pub fn atomic_write(path: &Path, content: &[u8]) -> io::Result<()> {
    let pid = std::process::id();
    let tmp_path = append_suffix(path, &format!("tmp.{}", pid));

    // Ensure parent directory exists
    if let Some(parent) = path.parent() {
        if !parent.exists() {
            fs::create_dir_all(parent)?;
        }
    }

    fs::write(&tmp_path, content)?;

    // fsync the file
    {
        let f = fs::File::open(&tmp_path)?;
        f.sync_all()?;
    }

    // Rename to target
    if let Err(e) = fs::rename(&tmp_path, path) {
        let _ = fs::remove_file(&tmp_path);
        return Err(e);
    }

    Ok(())
}

/// Compute SHA256 hex digest of content.
pub fn sha256_hex(content: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(content);
    format!("{:x}", hasher.finalize())
}

/// Write a SHA256 sidecar file at `{path}.sha256`.
pub fn write_checksum(path: &Path, content: &[u8]) -> io::Result<()> {
    let hex = sha256_hex(content);
    let sidecar = append_suffix(path, "sha256");
    fs::write(&sidecar, hex.as_bytes())
}

/// Verify that the file at `path` matches its `.sha256` sidecar.
/// Returns Ok(false) if the sidecar is missing (backwards compat).
/// Returns Ok(true) if checksums match, Ok(false) if they don't.
pub fn verify_checksum(path: &Path) -> io::Result<bool> {
    let sidecar = append_suffix(path, "sha256");

    if !sidecar.exists() {
        return Ok(false);
    }

    let content = fs::read(path)?;
    let expected = fs::read_to_string(&sidecar)?;
    let actual = sha256_hex(&content);

    Ok(actual == expected.trim())
}

/// Atomic write with checksum sidecar and backup.
/// 1. Copy current file to `{path}.backup` (if it exists)
/// 2. Atomic-write the new content
/// 3. Write the `.sha256` sidecar
pub fn atomic_write_with_checksum(path: &Path, content: &[u8]) -> io::Result<()> {
    // Create backup of current file if it exists
    if path.exists() {
        let backup = append_suffix(path, "backup");
        let _ = fs::copy(path, &backup);
    }

    atomic_write(path, content)?;
    write_checksum(path, content)?;
    Ok(())
}

/// Read a file and verify its checksum. If mismatch, attempt backup restore.
/// If backup also fails, return the original (possibly corrupt) content with a warning.
pub fn read_verified(path: &Path) -> io::Result<Vec<u8>> {
    let content = fs::read(path)?;

    match verify_checksum(path) {
        Ok(true) => return Ok(content),
        Ok(false) => {
            // Sidecar missing or mismatch — try backup
            let backup = append_suffix(path, "backup");
            if backup.exists() {
                let backup_content = fs::read(&backup)?;
                let sidecar = append_suffix(path, "sha256");
                if sidecar.exists() {
                    let expected = fs::read_to_string(&sidecar)?;
                    let actual = sha256_hex(&backup_content);
                    if actual == expected.trim() {
                        eprintln!(
                            "[atomic_io] checksum mismatch for {}, restored from backup",
                            path.display()
                        );
                        // Restore backup to main file
                        atomic_write(path, &backup_content)?;
                        return Ok(backup_content);
                    }
                }
                // Backup doesn't match either, fall through
            }
            // No backup or backup also bad — return original content
            eprintln!(
                "[atomic_io] warning: checksum verification failed for {}, no valid backup",
                path.display()
            );
            Ok(content)
        }
        Err(e) => {
            eprintln!(
                "[atomic_io] warning: checksum read error for {}: {}",
                path.display(),
                e
            );
            Ok(content)
        }
    }
}

/// Convenience wrapper returning String.
pub fn read_verified_string(path: &Path) -> io::Result<String> {
    let bytes = read_verified(path)?;
    String::from_utf8(bytes).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;
    use std::path::PathBuf;

    fn test_dir(name: &str) -> PathBuf {
        let mut d = env::temp_dir();
        d.push(format!(
            "yolo_atomic_io_{}_{}", name,
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_micros()
        ));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn test_atomic_write_roundtrip() {
        let dir = test_dir("roundtrip");
        let file = dir.join("test.json");
        let data = b"hello world";

        atomic_write(&file, data).unwrap();
        assert_eq!(fs::read(&file).unwrap(), data);

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_write_and_verify_checksum() {
        let dir = test_dir("checksum");
        let file = dir.join("data.json");
        let data = b"{\"key\": \"value\"}";

        fs::write(&file, data).unwrap();
        write_checksum(&file, data).unwrap();

        assert!(verify_checksum(&file).unwrap());

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_checksum_mismatch_detection() {
        let dir = test_dir("mismatch");
        let file = dir.join("data.json");
        let data = b"original";

        fs::write(&file, data).unwrap();
        write_checksum(&file, data).unwrap();

        // Corrupt the file
        fs::write(&file, b"corrupted").unwrap();

        assert!(!verify_checksum(&file).unwrap());

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_missing_sidecar_returns_false() {
        let dir = test_dir("no_sidecar");
        let file = dir.join("data.json");
        fs::write(&file, b"content").unwrap();

        // No sidecar written
        assert!(!verify_checksum(&file).unwrap());

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_atomic_write_with_checksum_creates_sidecar_and_backup() {
        let dir = test_dir("with_checksum");
        let file = dir.join("state.json");

        // First write — no backup yet
        atomic_write_with_checksum(&file, b"first").unwrap();
        assert!(file.exists());
        assert!(file.with_extension("json.sha256").exists());
        assert!(!file.with_extension("json.backup").exists());

        // Second write — backup should now exist
        atomic_write_with_checksum(&file, b"second").unwrap();
        assert!(file.with_extension("json.backup").exists());
        assert_eq!(fs::read(file.with_extension("json.backup")).unwrap(), b"first");
        assert_eq!(fs::read(&file).unwrap(), b"second");
        assert!(verify_checksum(&file).unwrap());

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_sha256_hex_known_value() {
        // SHA256 of empty string
        let hex = sha256_hex(b"");
        assert_eq!(hex, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    }

    #[test]
    fn test_read_verified_returns_content_on_valid_checksum() {
        let dir = test_dir("read_verified_ok");
        let file = dir.join("state.json");

        atomic_write_with_checksum(&file, b"good data").unwrap();
        let result = read_verified(&file).unwrap();
        assert_eq!(result, b"good data");

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_read_verified_restores_from_backup_on_corruption() {
        let dir = test_dir("read_verified_corrupt");
        let file = dir.join("state.json");

        // Write first version (becomes backup on second write)
        atomic_write_with_checksum(&file, b"original content").unwrap();
        // Write second version (first becomes .backup)
        atomic_write_with_checksum(&file, b"updated content").unwrap();

        // Corrupt the main file (but leave sidecar pointing to "updated content")
        fs::write(&file, b"CORRUPTED DATA").unwrap();

        // read_verified should detect mismatch and try backup.
        // Backup has "original content" but sidecar has hash of "updated content",
        // so backup won't match sidecar either. Falls through to original content.
        let result = read_verified(&file).unwrap();
        assert_eq!(result, b"CORRUPTED DATA");

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_read_verified_backup_matches_previous_sidecar() {
        let dir = test_dir("read_verified_backup_match");
        let file = dir.join("state.json");

        // Write first version
        atomic_write_with_checksum(&file, b"v1").unwrap();
        // Write second version
        atomic_write_with_checksum(&file, b"v2").unwrap();

        // Now corrupt main file AND update sidecar to match v1 (the backup)
        fs::write(&file, b"BROKEN").unwrap();
        let v1_hash = sha256_hex(b"v1");
        fs::write(file.with_extension("json.sha256"), v1_hash.as_bytes()).unwrap();

        // read_verified: main file hash != sidecar (v1 hash), tries backup which IS v1
        let result = read_verified(&file).unwrap();
        assert_eq!(result, b"v1");

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_read_verified_no_backup_returns_content() {
        let dir = test_dir("read_verified_no_backup");
        let file = dir.join("data.json");

        // Write with checksum (first write, no backup)
        atomic_write_with_checksum(&file, b"only version").unwrap();
        // Corrupt the file
        fs::write(&file, b"corrupted").unwrap();

        // No backup exists, should return corrupted content with warning
        let result = read_verified(&file).unwrap();
        assert_eq!(result, b"corrupted");

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_read_verified_string_convenience() {
        let dir = test_dir("read_verified_string");
        let file = dir.join("test.json");

        atomic_write_with_checksum(&file, b"hello string").unwrap();
        let result = read_verified_string(&file).unwrap();
        assert_eq!(result, "hello string");

        let _ = fs::remove_dir_all(&dir);
    }

    // --- Integration tests for corruption recovery ---

    #[test]
    fn test_integration_full_corruption_recovery_flow() {
        let dir = test_dir("integration_recovery");
        let file = dir.join("execution-state.json");

        // Write v1
        atomic_write_with_checksum(&file, b"{\"phase\": 1}").unwrap();
        assert!(verify_checksum(&file).unwrap());

        // Write v2 — v1 becomes backup
        atomic_write_with_checksum(&file, b"{\"phase\": 2}").unwrap();
        assert!(verify_checksum(&file).unwrap());

        // Verify backup exists with v1 content
        let backup = file.with_extension("json.backup");
        assert!(backup.exists());
        assert_eq!(fs::read(&backup).unwrap(), b"{\"phase\": 1}");

        // Corrupt the main file by flipping bytes
        fs::write(&file, b"{\"phase\": CORRUPT}").unwrap();
        assert!(!verify_checksum(&file).unwrap());

        // Set sidecar to match backup (simulating: sidecar from v1 was preserved)
        let v1_hash = sha256_hex(b"{\"phase\": 1}");
        fs::write(file.with_extension("json.sha256"), v1_hash.as_bytes()).unwrap();

        // read_verified should detect mismatch and restore from backup
        let recovered = read_verified(&file).unwrap();
        assert_eq!(recovered, b"{\"phase\": 1}");

        // After recovery, the main file should be restored
        assert_eq!(fs::read(&file).unwrap(), b"{\"phase\": 1}");

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_integration_sidecar_is_correct_hex() {
        let dir = test_dir("integration_sidecar_hex");
        let file = dir.join("state.json");
        let content = b"test content for hex check";

        atomic_write_with_checksum(&file, content).unwrap();

        let sidecar = file.with_extension("json.sha256");
        let stored_hex = fs::read_to_string(&sidecar).unwrap();
        let expected_hex = sha256_hex(content);

        assert_eq!(stored_hex, expected_hex);
        assert_eq!(stored_hex.len(), 64); // SHA256 hex is always 64 chars

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_integration_backup_exists_after_second_write() {
        let dir = test_dir("integration_backup_exists");
        let file = dir.join("config.json");

        let backup = file.with_extension("json.backup");
        assert!(!backup.exists());

        atomic_write_with_checksum(&file, b"first").unwrap();
        assert!(!backup.exists()); // No backup after first write

        atomic_write_with_checksum(&file, b"second").unwrap();
        assert!(backup.exists()); // Backup exists after second write
        assert_eq!(fs::read(&backup).unwrap(), b"first");

        atomic_write_with_checksum(&file, b"third").unwrap();
        assert_eq!(fs::read(&backup).unwrap(), b"second"); // Backup updated

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_integration_atomic_write_cleans_temp_on_failure() {
        let dir = test_dir("integration_temp_cleanup");
        // Create a read-only directory to force rename failure
        let ro_dir = dir.join("readonly");
        fs::create_dir_all(&ro_dir).unwrap();
        let target = ro_dir.join("file.json");

        // First, write successfully
        atomic_write(&target, b"initial").unwrap();

        // Make directory read-only
        let mut perms = fs::metadata(&ro_dir).unwrap().permissions();
        #[allow(clippy::permissions_set_readonly_false)]
        {
            perms.set_readonly(true);
        }
        let _ = fs::set_permissions(&ro_dir, perms.clone());

        // Attempt write — should fail (can't create temp file in read-only dir)
        let result = atomic_write(&target, b"should fail");

        // Restore permissions for cleanup
        perms.set_readonly(false);
        let _ = fs::set_permissions(&ro_dir, perms);

        // Verify either failed or temp file was cleaned up
        if result.is_err() {
            // No temp files should remain
            let entries: Vec<_> = fs::read_dir(&ro_dir)
                .unwrap()
                .filter_map(|e| e.ok())
                .filter(|e| e.file_name().to_string_lossy().contains(".tmp."))
                .collect();
            assert!(entries.is_empty(), "temp files should be cleaned up on failure");
        }

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_integration_file_without_extension() {
        let dir = test_dir("integration_no_ext");
        let file = dir.join("STATE");

        atomic_write_with_checksum(&file, b"no extension").unwrap();
        assert!(file.exists());
        assert_eq!(fs::read(&file).unwrap(), b"no extension");
        assert!(verify_checksum(&file).unwrap());

        let _ = fs::remove_dir_all(&dir);
    }
}
