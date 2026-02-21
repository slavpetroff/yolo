use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};
use chrono::Utc;
use sha2::{Sha256, Digest};
use std::process::Command;
use regex::Regex;
use super::{log_event, collect_metrics};

#[derive(serde::Serialize)]
struct GateResult {
    gate: String,
    result: String,
    evidence: String,
    autonomy: String,
    ts: String,
}

pub fn execute_gate(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 7 {
        return Ok((
            json!({
                "gate": "unknown",
                "result": "error",
                "evidence": "insufficient arguments",
                "ts": "unknown"
            }).to_string(),
            2
        ));
    }

    let gate_type = &args[2];
    let phase = &args[3];
    let plan = &args[4];
    let task = &args[5];
    let contract_path_str = &args[6];

    let planning_dir = cwd.join(".yolo-planning");
    let config_path = planning_dir.join("config.json");

    let mut v2_hard = false;
    let mut autonomy = String::from("unknown");

    if config_path.exists() {
        if let Ok(config_str) = fs::read_to_string(&config_path) {
            if let Ok(config) = serde_json::from_str::<Value>(&config_str) {
                if let Some(v) = config.get("v2_hard_gates").and_then(|v| v.as_bool()) {
                    v2_hard = v;
                }
                if let Some(a) = config.get("autonomy").and_then(|a| a.as_str()) {
                    autonomy = a.to_string();
                }
            }
        }
    }

    let ts = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();

    if !v2_hard {
        let res = GateResult {
            gate: gate_type.to_string(),
            result: "skip".to_string(),
            evidence: "v2_hard_gates=false".to_string(),
            autonomy,
            ts,
        };
        return Ok((serde_json::to_string(&res).unwrap(), 0));
    }

    let cwd_clone = cwd.to_path_buf();
    let gate_type_clone = gate_type.clone();
    let phase_clone = phase.clone();
    let plan_clone = plan.clone();
    let task_clone = task.clone();
    let autonomy_clone = autonomy.clone();

    let emit_res = move |result: &str, evidence: &str| -> (String, i32) {
        let ts = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();

        // Log event via native Rust module
        let event_type = if result == "fail" { "gate_failed" } else { "gate_passed" };
        let log_data = vec![
            ("gate".to_string(), gate_type_clone.clone()),
            ("task".to_string(), task_clone.clone()),
            ("evidence".to_string(), evidence.to_string()),
        ];
        let _ = log_event::log(
            event_type,
            &phase_clone,
            Some(&plan_clone),
            &log_data,
            &cwd_clone,
        );

        // Collect metrics via native Rust module
        let metric_name = format!("gate_{}", result);
        let metric_data = vec![
            ("gate".to_string(), gate_type_clone.clone()),
            ("task".to_string(), task_clone.clone()),
        ];
        let _ = collect_metrics::collect(
            &metric_name,
            &phase_clone,
            Some(&plan_clone),
            &metric_data,
            &cwd_clone,
        );

        let res = GateResult {
            gate: gate_type_clone.clone(),
            result: result.to_string(),
            evidence: evidence.to_string(),
            autonomy: autonomy_clone.clone(),
            ts,
        };
        let code = if result == "fail" { 2 } else { 0 };
        (serde_json::to_string(&res).unwrap(), code)
    };

    match gate_type.as_str() {
        "contract_compliance" => {
            let contract_path = Path::new(contract_path_str);
            if !contract_path.exists() {
                return Ok(emit_res("fail", "contract file not found"));
            }

            let contract_content = fs::read_to_string(contract_path).unwrap_or_default();
            let mut contract_json = match serde_json::from_str::<Value>(&contract_content) {
                Ok(v) => v,
                Err(_) => return Ok(emit_res("fail", "invalid contract JSON")),
            };

            let stored_hash = contract_json.get("contract_hash").and_then(|v| v.as_str()).unwrap_or("").to_string();

            if !stored_hash.is_empty() {
                if let Some(obj) = contract_json.as_object_mut() {
                    obj.remove("contract_hash");
                }
                
                let without_hash = format!("{}\n", serde_json::to_string_pretty(&contract_json).unwrap_or_default());
                let mut hasher = Sha256::new();
                hasher.update(without_hash.as_bytes());
                let computed_hash = format!("{:x}", hasher.finalize());

                if stored_hash != computed_hash {
                    return Ok(emit_res("fail", "contract hash mismatch"));
                }
            }

            let task_count = contract_json.get("task_count").and_then(|v| v.as_i64()).unwrap_or(0);
            let task_num: i64 = task.parse().unwrap_or(0);

            if task_num > task_count || task_num < 1 {
                return Ok(emit_res("fail", &format!("task {} outside range 1-{}", task_num, task_count)));
            }

            Ok(emit_res("pass", "hash verified, task in range"))
        }

        "protected_file" => {
            let contract_path = Path::new(contract_path_str);
            if !contract_path.exists() {
                return Ok(emit_res("pass", "no contract, fail-open"));
            }

            let contract_content = fs::read_to_string(contract_path).unwrap_or_default();
            let contract_json = match serde_json::from_str::<Value>(&contract_content) {
                Ok(v) => v,
                Err(_) => return Ok(emit_res("pass", "invalid contract JSON, fail-open")),
            };

            let forbidden = match contract_json.get("forbidden_paths").and_then(|v| v.as_array()) {
                Some(arr) => arr.iter().filter_map(|v| v.as_str()).collect::<Vec<&str>>(),
                None => return Ok(emit_res("pass", "no forbidden paths defined")),
            };

            if forbidden.is_empty() {
                return Ok(emit_res("pass", "no forbidden paths defined"));
            }

            let output = Command::new("git")
                .args(["diff", "--name-only", "--cached"])
                .current_dir(cwd)
                .output()
                .ok();

            let mut blocked = String::new();

            if let Some(out) = output {
                if out.status.success() {
                    let staged_files = String::from_utf8_lossy(&out.stdout);
                    for file in staged_files.lines() {
                        let file = file.trim();
                        if file.is_empty() { continue; }
                        for &f in &forbidden {
                            if file == f || file.starts_with(&format!("{}/", f)) {
                                blocked.push_str(file);
                                blocked.push(' ');
                            }
                        }
                    }
                }
            }

            if !blocked.is_empty() {
                Ok(emit_res("fail", &format!("forbidden files staged: {}", blocked.trim_end())))
            } else {
                Ok(emit_res("pass", "no forbidden files staged"))
            }
        }

        "required_checks" => {
            let contract_path = Path::new(contract_path_str);
            if !contract_path.exists() {
                return Ok(emit_res("pass", "no contract, fail-open"));
            }

            let contract_content = fs::read_to_string(contract_path).unwrap_or_default();
            let contract_json = match serde_json::from_str::<Value>(&contract_content) {
                Ok(v) => v,
                Err(_) => return Ok(emit_res("pass", "invalid contract JSON, fail-open")),
            };

            let checks = match contract_json.get("verification_checks").and_then(|v| v.as_array()) {
                Some(arr) => arr.iter().filter_map(|v| v.as_str()).collect::<Vec<&str>>(),
                None => return Ok(emit_res("pass", "no verification checks defined")),
            };

            if checks.is_empty() {
                return Ok(emit_res("pass", "no verification checks defined"));
            }

            let mut failed_checks = String::new();

            for check in checks {
                // To replace eval, we use bash -c
                let output = Command::new("bash")
                    .current_dir(cwd)
                    .arg("-c")
                    .arg(check)
                    .output();

                let success = match output {
                    Ok(o) => {
                        if !o.status.success() {
                            println!("Bash failed with: {}", String::from_utf8_lossy(&o.stderr));
                        }
                        o.status.success()
                    }
                    Err(e) => {
                        println!("Failed to spawn bash: {:?}", e);
                        false
                    }
                };
                
                if !success {
                    failed_checks.push_str(check);
                    failed_checks.push_str("; ");
                }
            }

            if !failed_checks.is_empty() {
                Ok(emit_res("fail", &format!("checks failed: {}", failed_checks.trim_end())))
            } else {
                Ok(emit_res("pass", "all verification checks passed"))
            }
        }

        "commit_hygiene" => {
            let output = Command::new("git")
                .args(["log", "-1", "--pretty=%s"])
                .current_dir(cwd)
                .output()
                .ok();

            let last_msg = if let Some(out) = output {
                if out.status.success() {
                    String::from_utf8_lossy(&out.stdout).trim().to_string()
                } else {
                    "".to_string()
                }
            } else {
                "".to_string()
            };

            if last_msg.is_empty() {
                return Ok(emit_res("pass", "no commits to check"));
            }

            let re = Regex::new(r"^(feat|fix|test|refactor|perf|docs|style|chore)\(.+\): .+").unwrap();
            if re.is_match(&last_msg) {
                Ok(emit_res("pass", "commit format valid"))
            } else {
                Ok(emit_res("fail", &format!("commit format invalid: {}", last_msg)))
            }
        }

        "artifact_persistence" => {
            let phases_dir = planning_dir.join("phases");
            if !phases_dir.exists() {
                return Ok(emit_res("pass", "no phases dir"));
            }

            let phase_dir = fs::read_dir(&phases_dir)
                .into_iter()
                .flatten()
                .filter_map(|e| e.ok())
                .filter(|e| {
                    if let Some(name) = e.file_name().to_str() {
                        name.starts_with(&format!("{}-", phase)) && e.path().is_dir()
                    } else {
                        false
                    }
                })
                .map(|e| e.path())
                .next();

            if let Some(pdir) = phase_dir {
                let mut missing = String::new();
                let plan_num_target: i64 = plan.parse().unwrap_or(0);

                if let Ok(entries) = fs::read_dir(&pdir) {
                    for entry in entries.flatten() {
                        if let Some(name) = entry.file_name().to_str() {
                            if name.ends_with("-PLAN.md") {
                                if let Some(prefix) = name.split('-').next() {
                                    if let Ok(plan_num) = prefix.parse::<i64>() {
                                        if plan_num < plan_num_target {
                                            let summary_name = name.replace("-PLAN.md", "-SUMMARY.md");
                                            let summary_path = pdir.join(summary_name);
                                            if !summary_path.exists() {
                                                missing.push_str(&format!("plan-{} ", plan_num));
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if !missing.is_empty() {
                    Ok(emit_res("fail", &format!("missing SUMMARY.md for: {}", missing.trim_end())))
                } else {
                    Ok(emit_res("pass", "all prior plan artifacts present"))
                }
            } else {
                Ok(emit_res("pass", "phase dir not found"))
            }
        }

        "verification_threshold" => {
            let phases_dir = planning_dir.join("phases");
            let phase_dir = match fs::read_dir(&phases_dir) {
                Ok(entries) => entries
                    .filter_map(|e| e.ok())
                    .find(|e| {
                        if let Some(name) = e.file_name().to_str() {
                            name.starts_with(&format!("{}-", phase)) && e.path().is_dir()
                        } else {
                            false
                        }
                    })
                    .map(|e| e.path()),
                Err(_) => None,
            };

            if let Some(pdir) = phase_dir {
                let verification_file = pdir.join("VERIFICATION.md");
                if !verification_file.exists() {
                    let mut tier = "standard".to_string();
                    if config_path.exists() {
                        if let Ok(config_str) = fs::read_to_string(&config_path) {
                            if let Ok(config) = serde_json::from_str::<Value>(&config_str) {
                                if let Some(v) = config.get("verification_tier").and_then(|v| v.as_str()) {
                                    tier = v.to_string();
                                }
                            }
                        }
                    }
                    if tier == "quick" || tier == "skip" {
                        return Ok(emit_res("pass", &format!("verification not required (tier={})", tier)));
                    }
                    return Ok(emit_res("fail", &format!("VERIFICATION.md missing (tier={})", tier)));
                }

                let content = fs::read_to_string(&verification_file).unwrap_or_default().to_lowercase();
                if content.contains("pass") || content.contains("passed") || content.contains("all checks pass") {
                    Ok(emit_res("pass", "verification passed"))
                } else if content.contains("fail") || content.contains("failed") {
                    Ok(emit_res("fail", "verification failed"))
                } else {
                    Ok(emit_res("pass", "verification status unclear, fail-open"))
                }
            } else {
                Ok(emit_res("pass", "phase dir not found"))
            }
        }

        "forbidden_commands" => {
            let contract_path = Path::new(contract_path_str);
            if !contract_path.exists() {
                return Ok(emit_res("pass", "no contract, fail-open"));
            }

            let contract_content = fs::read_to_string(contract_path).unwrap_or_default();
            let contract_json = match serde_json::from_str::<Value>(&contract_content) {
                Ok(v) => v,
                Err(_) => return Ok(emit_res("pass", "invalid contract JSON, fail-open")),
            };

            let forbidden_count = contract_json.get("forbidden_commands").and_then(|v| v.as_array()).map(|a| a.len()).unwrap_or(0);
            if forbidden_count == 0 {
                return Ok(emit_res("pass", "no forbidden commands defined"));
            }

            let event_log = planning_dir.join(".event-log.jsonl");
            if !event_log.exists() {
                return Ok(emit_res("pass", "no event log, fail-open"));
            }

            let log_content = fs::read_to_string(&event_log).unwrap_or_default();
            let mut violations = Vec::new();

            for line in log_content.lines().rev().take(5) {
                if line.contains("\"bash_guard_block\"") {
                    violations.push(line.to_string());
                }
            }

            if !violations.is_empty() {
                let first_violation = &violations[0];
                let mut preview = "unknown".to_string();
                if let Ok(v) = serde_json::from_str::<Value>(first_violation) {
                    if let Some(p) = v.get("command_preview").and_then(|v| v.as_str()) {
                        preview = p.to_string();
                    }
                }
                Ok(emit_res("fail", &format!("destructive command attempted: {}", preview)))
            } else {
                Ok(emit_res("pass", "no forbidden command violations"))
            }
        }

        _ => Ok(emit_res("fail", &format!("unknown gate type: {}", gate_type))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;
    use tempfile::TempDir;
    use serde_json::json;
    use sha2::{Sha256, Digest};

    fn setup_test_env() -> (TempDir, PathBuf) {
        let dir = TempDir::new().unwrap();
        let planning_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning_dir).unwrap();
        
        let config_path = planning_dir.join("config.json");
        fs::write(&config_path, json!({"v2_hard_gates": true, "autonomy": "test"}).to_string()).unwrap();
        
        (dir, planning_dir)
    }

    #[test]
    fn test_execute_gate_missing_args() {
        let args = vec!["yolo".to_string(), "hard-gate".to_string()];
        let (output, code) = execute_gate(&args, Path::new(".")).unwrap();
        assert_eq!(code, 2);
        let res: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(res["gate"], "unknown");
        assert_eq!(res["result"], "error");
    }

    #[test]
    fn test_execute_gate_v2_hard_false() {
        let (dir, planning_dir) = setup_test_env();
        let config_path = planning_dir.join("config.json");
        fs::write(&config_path, json!({"v2_hard_gates": false}).to_string()).unwrap();

        let args = vec!["yolo".into(), "hard-gate".into(), "unknown_gate".into(), "1".into(), "1".into(), "1".into(), "contract.json".into()];
        let (output, code) = execute_gate(&args, dir.path()).unwrap();
        
        assert_eq!(code, 0);
        let res: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(res["result"], "skip");
    }

    #[test]
    fn test_contract_compliance_missing_file() {
        let (dir, _) = setup_test_env();
        let args = vec!["yolo".into(), "hard-gate".into(), "contract_compliance".into(), "1".into(), "1".into(), "1".into(), "missing.json".into()];
        let (output, code) = execute_gate(&args, dir.path()).unwrap();
        
        assert_eq!(code, 2);
        let res: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(res["result"], "fail");
        assert_eq!(res["evidence"], "contract file not found");
    }

    #[test]
    fn test_contract_compliance_valid() {
        let (dir, _) = setup_test_env();
        
        // Restore contract_path setup
        let contract_path = dir.path().join("contract.json");
        let mut contract_json = json!({
            "task_count": 2,
            "forbidden_paths": []
        });

        let without_hash = format!("{}\n", serde_json::to_string_pretty(&contract_json).unwrap());
        let mut hasher = Sha256::new();
        hasher.update(without_hash.as_bytes());
        let computed_hash = format!("{:x}", hasher.finalize());

        contract_json["contract_hash"] = json!(computed_hash);
        fs::write(&contract_path, contract_json.to_string()).unwrap();

        let args = vec![
            "yolo".into(), "hard-gate".into(), "contract_compliance".into(),
            "1".into(), "1".into(), "1".into(), contract_path.to_str().unwrap().into()
        ];
        let (output, code) = execute_gate(&args, dir.path()).unwrap();
        
        assert_eq!(code, 0);
        let res: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(res["result"], "pass");
    }

    #[test]
    fn test_forbidden_commands_fail_open() {
        let (dir, _planning_dir) = setup_test_env();
        let args = vec![
            "yolo".into(), "hard-gate".into(), "forbidden_commands".into(),
            "1".into(), "1".into(), "1".into(), "contract.json".into()
        ];
        let (out, code) = execute_gate(&args, dir.path()).unwrap();
        
        assert_eq!(code, 0);
        let res: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(res["result"], "pass");
    }

    #[test]
    fn test_artifact_persistence_missing_summary() {
        let (dir, planning_dir) = setup_test_env();

        let phase_dir = planning_dir.join("phases").join("1-Test");
        fs::create_dir_all(&phase_dir).unwrap();
        
        fs::write(phase_dir.join("1-PLAN.md"), "plan 1").unwrap();
        // missing 1-SUMMARY.md
        fs::write(phase_dir.join("2-PLAN.md"), "plan 2").unwrap();

        let args = vec![
            "yolo".into(), "hard-gate".into(), "artifact_persistence".into(),
            "1".into(), "2".into(), "0".into(), "contract.json".into()
        ];
        let (out, code) = execute_gate(&args, dir.path()).unwrap();
        
        assert_eq!(code, 2);
        let res: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(res["result"], "fail");
        assert!(res["evidence"].as_str().unwrap().contains("plan-1"));
    }

    #[test]
    fn test_verification_threshold_missing() {
        let (dir, planning_dir) = setup_test_env();
        
        let phase_dir = planning_dir.join("phases").join("1-Test");
        fs::create_dir_all(&phase_dir).unwrap();
        
        let args = vec![
            "yolo".into(), "hard-gate".into(), "verification_threshold".into(),
            "1".into(), "1".into(), "0".into(), "contract.json".into()
        ];
        let (out, code) = execute_gate(&args, dir.path()).unwrap();
        
        assert_eq!(code, 2);
        let res: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(res["result"], "fail");
    }

    #[test]
    fn test_unknown_gate() {
        let (dir, _) = setup_test_env();
        let args = vec![
            "yolo".into(), "hard-gate".into(), "unknown_gate_name".into(),
            "1".into(), "1".into(), "0".into(), "contract.json".into()
        ];
        let (out, code) = execute_gate(&args, dir.path()).unwrap();
        
        assert_eq!(code, 2);
        let res: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(res["result"], "fail");
    }

    #[test]
    fn test_protected_file_no_forbidden() {
        let (dir, _) = setup_test_env();
        let contract_path = dir.path().join("contract.json");
        fs::write(&contract_path, json!({"forbidden_paths": []}).to_string()).unwrap();

        let args = vec![
            "yolo".into(), "hard-gate".into(), "protected_file".into(),
            "1".into(), "1".into(), "1".into(), contract_path.to_str().unwrap().into()
        ];
        let (out, code) = execute_gate(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let res: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(res["result"], "pass");
    }

    #[test]
    fn test_required_checks_success() {
        let (dir, _) = setup_test_env();
        let contract_path = dir.path().join("contract.json");
        fs::write(&contract_path, json!({"verification_checks": ["true"]}).to_string()).unwrap();

        let args = vec![
            "yolo".into(), "hard-gate".into(), "required_checks".into(),
            "1".into(), "1".into(), "1".into(), contract_path.to_str().unwrap().into()
        ];
        let (out, code) = execute_gate(&args, dir.path()).unwrap();
        println!("test_required_checks_success output: {}", out);
        assert_eq!(code, 0);
    }

    #[test]
    fn test_required_checks_fail() {
        let (dir, _) = setup_test_env();
        let contract_path = dir.path().join("contract.json");
        fs::write(&contract_path, json!({"verification_checks": ["false"]}).to_string()).unwrap();

        let args = vec![
            "yolo".into(), "hard-gate".into(), "required_checks".into(),
            "1".into(), "1".into(), "1".into(), contract_path.to_str().unwrap().into()
        ];
        let (out, code) = execute_gate(&args, dir.path()).unwrap();
        println!("test_required_checks_fail output: {}", out);
        assert_eq!(code, 2);
    }

    #[test]
    fn test_commit_hygiene_valid() {
        let (dir, _) = setup_test_env();
        
        Command::new("git").arg("init").current_dir(dir.path()).output().unwrap();
        Command::new("git").args(["commit", "--allow-empty", "-m", "feat(test): valid commit"]).current_dir(dir.path()).output().unwrap();

        let args = vec![
            "yolo".into(), "hard-gate".into(), "commit_hygiene".into(),
            "1".into(), "1".into(), "1".into(), "contract.json".into()
        ];
        let (out, code) = execute_gate(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
    }

    #[test]
    fn test_verification_threshold_pass() {
        let (dir, planning_dir) = setup_test_env();
        let phase_dir = planning_dir.join("phases").join("1-Test");
        fs::create_dir_all(&phase_dir).unwrap();
        fs::write(phase_dir.join("VERIFICATION.md"), "All checks passed successfully.").unwrap();

        let args = vec![
            "yolo".into(), "hard-gate".into(), "verification_threshold".into(),
            "1".into(), "1".into(), "0".into(), "contract.json".into()
        ];
        let (out, code) = execute_gate(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
    }

    #[test]
    fn test_verification_threshold_fail() {
        let (dir, planning_dir) = setup_test_env();
        let phase_dir = planning_dir.join("phases").join("1-Test");
        fs::create_dir_all(&phase_dir).unwrap();
        fs::write(phase_dir.join("VERIFICATION.md"), "Tests failed.").unwrap();

        let args = vec![
            "yolo".into(), "hard-gate".into(), "verification_threshold".into(),
            "1".into(), "1".into(), "0".into(), "contract.json".into()
        ];
        let (out, code) = execute_gate(&args, dir.path()).unwrap();
        assert_eq!(code, 2);
    }
}
