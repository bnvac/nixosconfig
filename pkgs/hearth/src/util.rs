//! Small helpers shared by the tools.

use std::env;
use std::ffi::OsStr;
use std::fs;
use std::io::{self, BufRead, Write};
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub fn home() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

pub fn config_dir() -> PathBuf {
    env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".config"))
}

pub fn state_dir() -> PathBuf {
    env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".local/state"))
}

pub fn runtime_dir() -> PathBuf {
    env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", uid())))
}

pub fn uid() -> u32 {
    fs::metadata("/proc/self").map(|m| m.uid()).unwrap_or(1000)
}

/// Make sure the right commands are reachable, even from a bare environment
/// (gamemode hooks, user services). The Nix build bakes in HEARTH_PATH (this
/// config's patched dmenu and st), which goes first so Backspace-goes-back
/// always works; the system's own commands go last.
pub fn extend_path() {
    let mut path = env::var("PATH").unwrap_or_default();
    if let Some(baked) = option_env!("HEARTH_PATH").filter(|p| !p.is_empty()) {
        path = if path.is_empty() {
            baked.to_string()
        } else {
            format!("{baked}:{path}")
        };
    }
    for extra in ["/run/wrappers/bin", "/run/current-system/sw/bin"] {
        if !path.split(':').any(|p| p == extra) {
            if !path.is_empty() {
                path.push(':');
            }
            path.push_str(extra);
        }
    }
    env::set_var("PATH", path);
}

/// Like `command -v`: the full path of a command on PATH.
pub fn which(cmd: &str) -> Option<PathBuf> {
    if cmd.contains('/') {
        let p = PathBuf::from(cmd);
        return is_exec(&p).then_some(p);
    }
    let paths = env::var_os("PATH")?;
    env::split_paths(&paths)
        .map(|d| d.join(cmd))
        .find(|p| is_exec(p))
}

fn is_exec(p: &Path) -> bool {
    fs::metadata(p)
        .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

/// Run a command; its trimmed stdout if it succeeded.
pub fn output<I, S>(cmd: &str, args: I) -> Option<String>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let out = Command::new(cmd)
        .args(args)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    out.status
        .success()
        .then(|| String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// Run a command quietly; did it succeed?
pub fn ok<I, S>(cmd: &str, args: I) -> bool
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    Command::new(cmd)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

pub fn notify(app: &str, summary: &str, body: &str, critical: bool) {
    notify_with(
        app,
        "",
        if critical { "critical" } else { "normal" },
        summary,
        body,
    );
}

pub fn notify_with(app: &str, icon: &str, urgency: &str, summary: &str, body: &str) {
    let mut c = Command::new("notify-send");
    c.args(["-a", app, "-u", urgency]);
    if !icon.is_empty() {
        c.args(["-i", icon]);
    }
    c.arg(summary)
        .arg(body)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    let _ = c.status();
}

pub enum Pick {
    Chose(String),
    Back,
    Cancel,
}

/// dmenu. With `back`, this config's dmenu exits with status 3 when you press
/// Backspace with nothing typed — reported as `Pick::Back`.
pub fn dmenu(prompt: &str, items: &[String], back: bool) -> Pick {
    let mut c = Command::new("dmenu");
    c.args(["-i", "-l", "20", "-p", prompt])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    if back {
        c.env("DMENU_BACK", "1");
    }
    let Ok(mut child) = c.spawn() else {
        return Pick::Cancel;
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(items.join("\n").as_bytes());
    }
    let Ok(out) = child.wait_with_output() else {
        return Pick::Cancel;
    };
    match out.status.code() {
        Some(0) => {
            let s = String::from_utf8_lossy(&out.stdout)
                .trim_end_matches('\n')
                .to_string();
            if s.is_empty() {
                Pick::Cancel
            } else {
                Pick::Chose(s)
            }
        }
        Some(3) => Pick::Back,
        _ => Pick::Cancel,
    }
}

/// Ask on the terminal; the trimmed answer (None at end of input).
pub fn ask(prompt: &str) -> Option<String> {
    print!("{prompt}");
    let _ = io::stdout().flush();
    let mut line = String::new();
    match io::stdin().lock().read_line(&mut line) {
        Ok(0) | Err(_) => None,
        Ok(_) => Some(line.trim().to_string()),
    }
}

/// Programs started outside X (gamemode hooks, user services) may lack
/// DISPLAY; the dwm session writes it to $XDG_RUNTIME_DIR/x-env at login.
pub fn load_x_env() {
    if env::var_os("DISPLAY").is_some() {
        return;
    }
    if let Ok(s) = fs::read_to_string(runtime_dir().join("x-env")) {
        for line in s.lines() {
            if let Some((k, v)) = line.split_once('=') {
                if !k.is_empty() && !v.is_empty() {
                    env::set_var(k, v);
                }
            }
        }
    }
}

/// "3 days", "5 hours", "just now"
pub fn ago(secs: u64) -> String {
    let (n, unit) = match secs {
        s if s < 90 => return "just now".into(),
        s if s < 5400 => (s / 60, "minute"),
        s if s < 172_800 => (s / 3600, "hour"),
        s => (s / 86_400, "day"),
    };
    format!("{n} {unit}{} ago", if n == 1 { "" } else { "s" })
}
