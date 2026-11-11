//! hearth rollback — go back to an earlier system version (for when an
//! update broke something). Lists the kept versions with their dates; Enter
//! picks the one before the current. Your files are never touched; only the
//! system software changes, and you can roll forward again the same way.

use crate::util::{ago, ask, extend_path};
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::PathBuf;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

const PROFILES: &str = "/nix/var/nix/profiles";

pub struct Gen {
    pub num: u32,
    pub when: i64,
    pub version: String,
}

/// "system-42-link" → 42
pub fn gen_number(name: &str) -> Option<u32> {
    name.strip_prefix("system-")?.strip_suffix("-link")?.parse().ok()
}

fn generations() -> Vec<Gen> {
    let mut gens: Vec<Gen> = fs::read_dir(PROFILES)
        .map(|d| {
            d.filter_map(Result::ok)
                .filter_map(|e| {
                    let num = gen_number(&e.file_name().to_string_lossy())?;
                    let when = fs::symlink_metadata(e.path()).map(|m| m.mtime()).unwrap_or(0);
                    let version = fs::read_to_string(e.path().join("nixos-version"))
                        .map(|s| s.trim().to_string())
                        .unwrap_or_default();
                    Some(Gen { num, when, version })
                })
                .collect()
        })
        .unwrap_or_default();
    gens.sort_by_key(|g| g.num);
    gens
}

fn current() -> Option<u32> {
    let target = fs::read_link(PathBuf::from(PROFILES).join("system")).ok()?;
    gen_number(&target.file_name()?.to_string_lossy())
}

fn now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

pub fn run(args: &[String]) -> i32 {
    extend_path();
    let gens = generations();
    let Some(cur) = current() else {
        eprintln!("rollback: can't find the current system version in {PROFILES}");
        return 1;
    };
    if gens.len() < 2 {
        println!("There's only one system version kept, so there's nothing to go back to.");
        return 0;
    }

    // `hearth rollback N` skips the question.
    let wanted = if let Some(n) = args.first() {
        n.parse::<u32>().ok()
    } else {
        println!("System versions (newest last):\n");
        for g in &gens {
            let mark = if g.num == cur { "  ← running now" } else { "" };
            let age = ago((now() - g.when).max(0) as u64);
            println!("  {:>4}  {:<18}  {}{}", g.num, age, g.version, mark);
        }
        let default = gens.iter().rev().find(|g| g.num < cur).or_else(|| gens.iter().rev().find(|g| g.num != cur));
        let Some(default) = default else { return 0 };
        println!();
        let Some(answer) = ask(&format!("Go back to which version? [{}]  (q to cancel) ", default.num)) else { return 0 };
        match answer.as_str() {
            "" => Some(default.num),
            "q" | "Q" | "n" | "no" => {
                println!("Nothing changed.");
                return 0;
            }
            s => s.parse().ok(),
        }
    };

    let Some(target) = wanted.filter(|n| gens.iter().any(|g| g.num == *n)) else {
        eprintln!("That isn't one of the versions listed.");
        return 1;
    };
    if target == cur {
        println!("Version {target} is already running.");
        return 0;
    }

    println!("\nSwitching to version {target} (asks for your password)…");
    let set = Command::new("sudo")
        .args(["nix-env", "--profile", &format!("{PROFILES}/system"), "--switch-generation", &target.to_string()])
        .status();
    if !set.is_ok_and(|s| s.success()) {
        eprintln!("rollback: couldn't select version {target}");
        return 1;
    }
    let switched = Command::new("sudo").arg(format!("{PROFILES}/system/bin/switch-to-configuration")).arg("switch").status();
    if switched.is_ok_and(|s| s.success()) {
        println!("\nDone — now on version {target}. It's also the default at the next boot.");
        println!("To return to the newest: hearth rollback {}", gens.last().map(|g| g.num).unwrap_or(cur));
        0
    } else {
        eprintln!("\nVersion {target} is selected but didn't fully start. Rebooting will finish it.");
        1
    }
}

#[cfg(test)]
mod tests {
    use super::gen_number;

    #[test]
    fn numbers() {
        assert_eq!(gen_number("system-42-link"), Some(42));
        assert_eq!(gen_number("system"), None);
        assert_eq!(gen_number("system-x-link"), None);
        assert_eq!(gen_number("default-3-link"), None);
    }
}
