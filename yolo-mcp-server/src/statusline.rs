use std::path::{Path, PathBuf};
use std::fs;
use std::time::Duration;
use rusqlite::Connection;
use serde_json::Value;

pub fn render_statusline(db_path: &PathBuf) -> Result<String, String> {
    let project_name = get_project_name();
    let (phase_str, plans_str, progress_str) = get_state_info();
    let cache_hits = get_cache_hits(db_path);
    let (limits_str, model_str) = get_limits_and_model();
    
    // Formatting variables
    let c_reset  = "\x1b[0m";
    let c_dim    = "\x1b[2m";
    let c_bold   = "\x1b[1m";
    let c_cyan   = "\x1b[36m";
    let c_purple = "\x1b[35m";
    
    let l1 = format!("\r\x1b[K{}{} YOLO EXPERT 🚀 {}{} {}", c_bold, c_purple, c_cyan, project_name, c_reset);
    let l2 = format!("\r\x1b[K{}[{} | {} | {}]{}", c_dim, phase_str, plans_str, progress_str, c_reset);
    let l3 = format!("\r\x1b[K{}Session: {} | Cache Hits: {}{}", c_dim, limits_str, cache_hits, c_reset);
    let l4 = format!("\r\x1b[K{}Model: {}{}", c_dim, model_str, c_reset);

    Ok(format!("{}\n{}\n{}\n{}\n", l1, l2, l3, l4))
}

fn get_project_name() -> String {
    if let Ok(path) = std::env::current_dir() {
        if let Some(name) = path.file_name() {
            return name.to_string_lossy().to_string();
        }
    }
    "Unknown Project".to_string()
}

fn get_state_info() -> (String, String, String) {
    let mut phase = "Phase: None".to_string();
    let mut plans = "Plans: 0/0".to_string();
    let mut prog = "Progress: 0%".to_string();

    let state_md = Path::new(".yolo-planning/STATE.md");
    if state_md.exists() {
        if let Ok(content) = fs::read_to_string(state_md) {
            for line in content.lines() {
                if line.starts_with("Phase: ") {
                    phase = line.to_string();
                } else if line.starts_with("Plans: ") {
                    plans = line.to_string();
                } else if line.starts_with("Progress: ") {
                    prog = line.to_string();
                }
            }
        }
    }
    (phase, plans, prog)
}

fn get_cache_hits(db_path: &PathBuf) -> i64 {
    if !db_path.exists() {
        return 0;
    }
    if let Ok(conn) = Connection::open(db_path) {
        let query = "SELECT COUNT(*) FROM tool_usage WHERE tool_name = 'compile_context'";
        if let Ok(count) = conn.query_row(query, [], |row| row.get(0)) {
            return count;
        }
    }
    0
}

fn get_cache_path() -> PathBuf {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    let mut hasher = DefaultHasher::new();
    if let Ok(path) = std::env::current_dir() {
        path.to_string_lossy().hash(&mut hasher);
    }
    let hash = hasher.finish();
    std::env::temp_dir().join(format!(".yolo-limit-cache-{:x}.json", hash))
}

pub fn trigger_background_fetch() {
    if let Ok(exe) = std::env::current_exe() {
        let _ = std::process::Command::new(exe)
            .arg("fetch-limits")
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn();
    }
}

pub fn execute_fetch_limits() -> Result<(), String> {
    // 1. Get API Key
    let api_key = std::env::var("ANTHROPIC_API_KEY")
        .or_else(|_| std::env::var("YOLO_OAUTH_TOKEN"))
        .or_else(|_| {
            let home = std::env::var("HOME").unwrap_or_default();
            fs::read_to_string(PathBuf::from(home).join(".yolo_api_key")).map(|s| s.trim().to_string())
        })
        .unwrap_or_default();

    if api_key.is_empty() {
        let cache_path = get_cache_path();
        let _ = fs::write(cache_path, r#"{"status": "auth"}"#);
        return Err("No Auth".to_string());
    }

    let client = reqwest::blocking::Client::new();
    let body = serde_json::json!({
        "model": "claude-3-5-sonnet-20241022",
        "messages": [{"role": "user", "content": "ping"}],
        "max_tokens": 1
    });

    let is_bearer = api_key.starts_with("sk-ant-") == false && api_key.len() > 10;
    
    let mut builder = client.post("https://api.anthropic.com/v1/messages")
        .header("anthropic-version", "2023-06-01")
        .header("content-type", "application/json")
        .json(&body);

    if is_bearer {
        builder = builder.header("Authorization", format!("Bearer {}", api_key));
    } else {
        builder = builder.header("x-api-key", api_key);
    }

    match builder.send() {
        Ok(res) => {
            let tokens_remaining = res.headers().get("anthropic-ratelimit-tokens-remaining")
                .and_then(|h| h.to_str().ok()).unwrap_or("0");
            let tokens_limit = res.headers().get("anthropic-ratelimit-tokens-limit")
                .and_then(|h| h.to_str().ok()).unwrap_or("0");
            
            let remaining: i64 = tokens_remaining.parse().unwrap_or(0);
            let limit: i64 = tokens_limit.parse().unwrap_or(1);
            
            let pct = if limit > 0 { (remaining * 100) / limit } else { 0 };

            let cache_data = serde_json::json!({
                "status": "ok",
                "tokens_pct": pct,
                "model": "claude-3-5-sonnet-20241022"
            });

            let _ = fs::write(get_cache_path(), cache_data.to_string());
            Ok(())
        }
        Err(_) => {
            let _ = fs::write(get_cache_path(), r#"{"status": "fail"}"#);
            Err("Fetch Failed".to_string())
        }
    }
}

fn get_limits_and_model() -> (String, String) {
    let cache_path = get_cache_path();
    
    let mut needs_sync = true;
    let mut needs_async = false;

    if let Ok(metadata) = fs::metadata(&cache_path) {
        if let Ok(modified) = metadata.modified() {
            if let Ok(elapsed) = modified.elapsed() {
                if elapsed < Duration::from_secs(5) {
                    needs_sync = false;
                } else if elapsed < Duration::from_secs(60) {
                    needs_sync = false;
                    needs_async = true;
                }
            }
        }
    }

    if needs_async {
        trigger_background_fetch();
    } else if needs_sync {
        let _ = execute_fetch_limits();
    }

    // Read cache
    if let Ok(content) = fs::read_to_string(&cache_path) {
        if let Ok(data) = serde_json::from_str::<Value>(&content) {
            let status = data.get("status").and_then(|v| v.as_str()).unwrap_or("fail");
            let model = data.get("model").and_then(|v| v.as_str()).unwrap_or("claude-3-5-sonnet-20241022");
            
            if status == "auth" {
                return (format!("\x1b[31mauth expired (run /login)\x1b[0m"), model.to_string());
            } else if status == "fail" {
                return (format!("\x1b[31mfetch failed (retry in 60s)\x1b[0m"), model.to_string());
            } else if status == "ok" {
                let pct = data.get("tokens_pct").and_then(|v| v.as_i64()).unwrap_or(0);
                
                // Construct progress bar [==   ]
                let bar_len = 10;
                let filled = ((pct * bar_len) / 100).max(0).min(bar_len);
                let empty = bar_len - filled;
                
                let bar_filled: String = (0..filled).map(|_| '=').collect();
                let bar_empty: String = (0..empty).map(|_| ' ').collect();
                
                let color = if pct < 15 { "\x1b[31m" } else if pct < 50 { "\x1b[33m" } else { "\x1b[32m" };
                
                let out = format!("{}[{}{}] {}%\x1b[0m", color, bar_filled, bar_empty, pct);
                return (out, model.to_string());
            }
        }
    }

    (format!("\x1b[33mPending...\x1b[0m"), "claude-3-5-sonnet-20241022".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::env;

    fn setup_test_dir(name: &str) -> PathBuf {
        let mut d = env::temp_dir();
        d.push(format!("yolo_statusline_{}_{}", name, std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_micros()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn test_render_statusline() {
        let db = PathBuf::from(".test-render.db");
        let _ = fs::remove_file(&db);
        let out = render_statusline(&db).unwrap();
        assert!(out.contains("YOLO EXPERT"));
        assert!(out.contains("Cache Hits: 0"));
    }

    #[test]
    fn test_get_project_name() {
        let name = get_project_name();
        assert!(!name.is_empty());
        
        let orig_dir = env::current_dir().unwrap();
        struct DirGuard(std::path::PathBuf);
        impl Drop for DirGuard { fn drop(&mut self) { let _ = std::env::set_current_dir(&self.0); } }
        let _guard = DirGuard(orig_dir.clone());
        // Root directory has no file_name
        if let Ok(_) = env::set_current_dir("/") {
            let root_name = get_project_name();
            assert_eq!(root_name, "Unknown Project");
        }
        }

    #[test]
    fn test_get_state_info() {
        let d = setup_test_dir("state_info");
        let orig_dir = env::current_dir().unwrap();
        struct DirGuard(std::path::PathBuf);
        impl Drop for DirGuard { fn drop(&mut self) { let _ = std::env::set_current_dir(&self.0); } }
        let _guard = DirGuard(orig_dir.clone());
        env::set_current_dir(&d).unwrap();

        let (p, l, pr) = get_state_info();
        assert_eq!(p, "Phase: None");
        assert_eq!(l, "Plans: 0/0");
        assert_eq!(pr, "Progress: 0%");

        fs::create_dir_all(".yolo-planning").unwrap();
        fs::write(".yolo-planning/STATE.md", "Phase: 1 of 1 (Test)\nPlans: 1/2\nProgress: 50%").unwrap();

        let (p2, l2, pr2) = get_state_info();
        assert_eq!(p2, "Phase: 1 of 1 (Test)");
        assert_eq!(l2, "Plans: 1/2");
        assert_eq!(pr2, "Progress: 50%");

        env::set_current_dir(orig_dir).unwrap();
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn test_get_cache_hits() {
        let d = setup_test_dir("cache_hits");
        let db_path = d.join("test.db");
        
        // Missing DB returns 0
        assert_eq!(get_cache_hits(&db_path), 0);
        
        // Creating DB with values
        let conn = Connection::open(&db_path).unwrap();
        conn.execute("CREATE TABLE tool_usage (tool_name TEXT)", []).unwrap();
        conn.execute("INSERT INTO tool_usage (tool_name) VALUES ('compile_context')", []).unwrap();
        conn.execute("INSERT INTO tool_usage (tool_name) VALUES ('compile_context')", []).unwrap();
        
        assert_eq!(get_cache_hits(&db_path), 2);
        
        // Test invalid DB (e.g., path is a directory)
        assert_eq!(get_cache_hits(&d), 0);
        
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn test_execute_fetch_limits_no_auth() {
        let d = setup_test_dir("no_auth");
        let orig_dir = env::current_dir().unwrap();
        struct DirGuard(std::path::PathBuf);
        impl Drop for DirGuard { fn drop(&mut self) { let _ = std::env::set_current_dir(&self.0); } }
        let _guard = DirGuard(orig_dir.clone());
        env::set_current_dir(&d).unwrap();
        
        unsafe {
            env::remove_var("ANTHROPIC_API_KEY");
            env::remove_var("YOLO_OAUTH_TOKEN");
            env::set_var("HOME", d.to_str().unwrap());
        }

        let res = execute_fetch_limits();
        assert!(res.is_err());
        assert_eq!(res.unwrap_err(), "No Auth");

        let cache_path = get_cache_path();
        let content = fs::read_to_string(&cache_path).unwrap_or_default();
        assert!(content.contains("\"status\": \"auth\""));
        
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn test_execute_fetch_limits_with_auth() {
        let d = setup_test_dir("with_auth");
        let orig_dir = env::current_dir().unwrap();
        struct DirGuard(std::path::PathBuf);
        impl Drop for DirGuard { fn drop(&mut self) { let _ = std::env::set_current_dir(&self.0); } }
        let _guard = DirGuard(orig_dir.clone());
        env::set_current_dir(&d).unwrap();
        unsafe {
            env::set_var("ANTHROPIC_API_KEY", "sk-ant-fake-key-for-test-coverage");
        }
        
        // This will attempt network fetch. Since key is invalid, it returns 401 or network error.
        let res = execute_fetch_limits();
        
        let cache_path = get_cache_path();
        let content = fs::read_to_string(&cache_path).unwrap_or_default();
        
        if res.is_ok() {
            assert!(content.contains("\"status\":\"ok\"") || content.contains("\"status\": \"ok\""));
        } else {
            assert!(content.contains("\"status\":\"fail\"") || content.contains("\"status\": \"fail\""));
        }

        unsafe {
            env::remove_var("ANTHROPIC_API_KEY");
        }
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn test_execute_fetch_limits_bearer_token() {
        let d = setup_test_dir("bearer_auth");
        let orig_dir = env::current_dir().unwrap();
        struct DirGuard(std::path::PathBuf);
        impl Drop for DirGuard { fn drop(&mut self) { let _ = std::env::set_current_dir(&self.0); } }
        let _guard = DirGuard(orig_dir.clone());
        env::set_current_dir(&d).unwrap();
        unsafe {
            env::set_var("YOLO_OAUTH_TOKEN", "ya29.fake-bearer-token-with-length-gt-10");
        }
        
        let _ = execute_fetch_limits(); 
        
        // This hits the is_bearer branch.
        let cache_path = get_cache_path();
        let content = fs::read_to_string(&cache_path).unwrap_or_default();
        assert!(content.contains("\"status\""));

        unsafe {
            env::remove_var("YOLO_OAUTH_TOKEN");
        }
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn test_get_limits_and_model() {
        let d = setup_test_dir("limits_model");
        let orig_dir = env::current_dir().unwrap();
        struct DirGuard(std::path::PathBuf);
        impl Drop for DirGuard { fn drop(&mut self) { let _ = std::env::set_current_dir(&self.0); } }
        let _guard = DirGuard(orig_dir.clone());
        env::set_current_dir(&d).unwrap();

        let cache_path = get_cache_path();
        
        unsafe {
            env::remove_var("ANTHROPIC_API_KEY");
            env::remove_var("YOLO_OAUTH_TOKEN");
            env::set_var("HOME", d.to_str().unwrap());
        }
        
        // 1. Missing cache -> returns Pending...
        let _ = fs::remove_file(&cache_path);
        let (out1, model1) = get_limits_and_model();
        assert!(out1.contains("Pending") || out1.contains("fail") || out1.contains("auth")); // Depending on if it ran sync fetch internally!
        
        // Wait, get_limits_and_model runs execute_fetch_limits synchronously if cache is missing. 
        // So out1 will reflect the immediate fetch result!

        // 2. Auth error
        fs::write(&cache_path, r#"{"status": "auth", "model": "test-model"}"#).unwrap();
        let (out2, model2) = get_limits_and_model(); // Will only read cache if < 5s old!
        assert!(out2.contains("auth expired"));
        assert_eq!(model2, "test-model");

        // 3. Fail error
        fs::write(&cache_path, r#"{"status": "fail"}"#).unwrap();
        let (out3, _) = get_limits_and_model();
        assert!(out3.contains("fetch failed"));

        // 4. Ok limits - high (> 50)
        fs::write(&cache_path, r#"{"status": "ok", "tokens_pct": 80}"#).unwrap();
        let (out4, _) = get_limits_and_model();
        assert!(out4.contains("80%"));
        assert!(out4.contains("==")); // progress bar

        // 5. Ok limits - medium (< 50)
        fs::write(&cache_path, r#"{"status": "ok", "tokens_pct": 40}"#).unwrap();
        let (out5, _) = get_limits_and_model();
        assert!(out5.contains("40%"));

        // 6. Ok limits - low (< 15)
        fs::write(&cache_path, r#"{"status": "ok", "tokens_pct": 10}"#).unwrap();
        let (out6, _) = get_limits_and_model();
        assert!(out6.contains("10%"));

        // 7. Invalid JSON -> Pending
        fs::write(&cache_path, r#"invalid json"#).unwrap();
        let (out7, _) = get_limits_and_model();
        assert!(out7.contains("Pending"));
        
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn test_background_fetch_trigger() {
        // Just ensuring it doesn't panic
        trigger_background_fetch();
    }
}
