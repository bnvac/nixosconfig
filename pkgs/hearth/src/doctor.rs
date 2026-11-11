//! hearth doctor — check that the system works, in plain words, with the fix
//! for anything that doesn't.
//!
//!   hearth doctor            the full report (menu: System → System check)
//!   hearth doctor --notify   quiet: one notification, only if something's wrong
//!                            (a weekly timer runs this)

use crate::util::{ago, extend_path, home, load_x_env, notify, ok, output, runtime_dir, state_dir, which};
use std::env;
use std::fs;
use std::io::IsTerminal;
use std::net::{TcpStream, ToSocketAddrs};
use std::path::Path;
use std::time::{Duration, SystemTime};

#[derive(Clone, Copy, PartialEq, PartialOrd)]
enum Level {
    Good,
    Note,
    Warn,
    Bad,
}

struct Check {
    level: Level,
    area: &'static str,
    said: String,
    fix: Option<String>,
}

fn check(level: Level, area: &'static str, said: impl Into<String>, fix: Option<&str>) -> Check {
    Check { level, area, said: said.into(), fix: fix.map(String::from) }
}

fn secs_since(t: SystemTime) -> u64 {
    SystemTime::now().duration_since(t).map(|d| d.as_secs()).unwrap_or(0)
}

// ── the checks ──────────────────────────────────────────────────────────────

fn services(user: bool) -> Check {
    let area = if user { "Your services" } else { "System services" };
    let mut args = vec!["--failed", "--no-legend", "--plain"];
    if user {
        args.insert(0, "--user");
    }
    match output("systemctl", &args) {
        None => check(Level::Note, area, "couldn't ask systemd", None),
        Some(s) if s.is_empty() => check(Level::Good, area, "all running", None),
        Some(s) => {
            let names: Vec<&str> = s.lines().filter_map(|l| l.split_whitespace().next()).collect();
            let how = if user { "systemctl --user status" } else { "systemctl status" };
            let first = names.first().copied().unwrap_or("NAME");
            check(Level::Bad, area, format!("failed: {}", names.join(", ")), Some(&format!("see why: {how} {first}")))
        }
    }
}

fn disk() -> Vec<Check> {
    let mut out = Vec::new();
    let Some(df) = output("df", ["-P", "-k", "/", home().to_str().unwrap_or("/")]) else { return out };
    let mut seen = Vec::new();
    for line in df.lines().skip(1) {
        let f: Vec<&str> = line.split_whitespace().collect();
        if f.len() < 6 || seen.contains(&f[0]) {
            continue;
        }
        seen.push(f[0]);
        let used: u64 = f[4].trim_end_matches('%').parse().unwrap_or(0);
        let free_gb = f[3].parse::<u64>().unwrap_or(0) as f64 / 1_048_576.0;
        let said = format!("{} is {used}% full, {free_gb:.0} GB free", f[5]);
        out.push(match used {
            95.. => check(Level::Bad, "Disk", said, Some("free space: debloat")),
            85.. => check(Level::Warn, "Disk", said, Some("free space: debloat")),
            _ => check(Level::Good, "Disk", said, None),
        });
    }
    out
}

fn generations() -> Check {
    let n = fs::read_dir("/nix/var/nix/profiles")
        .map(|d| {
            d.filter_map(Result::ok)
                .filter(|e| {
                    let n = e.file_name();
                    let n = n.to_string_lossy();
                    n.starts_with("system-") && n.ends_with("-link")
                })
                .count()
        })
        .unwrap_or(0);
    if n > 15 {
        check(Level::Warn, "Old versions", format!("{n} system versions kept"), Some("debloat clean keeps the last 5"))
    } else {
        check(Level::Good, "Old versions", format!("{n} system versions kept for rollback"), None)
    }
}

fn memory() -> Check {
    let info = fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let get = |k: &str| -> u64 {
        info.lines()
            .find(|l| l.starts_with(k))
            .and_then(|l| l.split_whitespace().nth(1))
            .and_then(|v| v.parse().ok())
            .unwrap_or(0)
    };
    let (total, avail) = (get("MemTotal:"), get("MemAvailable:"));
    if total == 0 {
        return check(Level::Note, "Memory", "couldn't read", None);
    }
    let pct = avail * 100 / total;
    let said = format!("{:.1} of {:.1} GB free", avail as f64 / 1_048_576.0, total as f64 / 1_048_576.0);
    if pct < 10 {
        check(Level::Warn, "Memory", said, Some("close something big, or see what: htop"))
    } else {
        check(Level::Good, "Memory", said, None)
    }
}

fn clock() -> Check {
    match output("timedatectl", ["show", "-p", "NTPSynchronized", "--value"]).as_deref() {
        Some("yes") => check(Level::Good, "Clock", "in sync", None),
        Some(_) => check(Level::Warn, "Clock", "not synced with the internet", Some("sudo systemctl restart systemd-timesyncd")),
        None => check(Level::Note, "Clock", "couldn't ask timedatectl", None),
    }
}

fn network() -> Vec<Check> {
    let mut out = Vec::new();
    if ok("systemctl", ["is-active", "--quiet", "tor-transparent"]) {
        out.push(check(Level::Note, "Network", "everything is going through Tor (tormode)", Some("normal internet: tormode off")));
    }
    let dns = ("cache.nixos.org", 443).to_socket_addrs().map(|mut a| a.next());
    let reach = |addr: &str| {
        addr.parse().ok().map(|a| TcpStream::connect_timeout(&a, Duration::from_secs(3)).is_ok()).unwrap_or(false)
    };
    out.push(match dns {
        Ok(Some(addr)) if TcpStream::connect_timeout(&addr, Duration::from_secs(4)).is_ok() => {
            check(Level::Good, "Network", "online", None)
        }
        Ok(_) if reach("1.1.1.1:443") => check(Level::Bad, "Network", "online, but couldn't reach the NixOS servers", None),
        Err(_) if reach("1.1.1.1:443") => {
            check(Level::Bad, "Network", "online, but names don't resolve (DNS)", Some("nmcli connection up <your connection>"))
        }
        _ => check(Level::Bad, "Network", "offline", Some("nmtui, or the network icon")),
    });
    out
}

fn screenshots() -> Check {
    load_x_env();
    if env::var_os("DISPLAY").is_none() {
        return check(Level::Note, "Screenshots", "no desktop session here to test", None);
    }
    for tool in ["maim", "xclip"] {
        if which(tool).is_none() {
            return check(Level::Bad, "Screenshots", format!("{tool} is missing"), Some("rebuild"));
        }
    }
    let shot = runtime_dir().join("hearth-doctor-shot.png");
    let worked = ok("maim", ["-u", "-q", shot.to_str().unwrap_or("/tmp/hearth-doctor-shot.png")])
        && fs::metadata(&shot).map(|m| m.len() > 0).unwrap_or(false);
    let _ = fs::remove_file(&shot);
    if worked {
        check(Level::Good, "Screenshots", "can grab the screen (Print / Shift+Print)", None)
    } else {
        check(Level::Bad, "Screenshots", "maim couldn't grab the screen", Some("run: screenshot full — it shows the exact error"))
    }
}

fn audio() -> Check {
    if which("pactl").is_none() {
        return check(Level::Note, "Audio", "pactl not installed", None);
    }
    match output("pactl", ["get-default-sink"]) {
        None => check(Level::Bad, "Audio", "the sound server isn't answering", Some("systemctl --user restart pipewire wireplumber")),
        Some(s) if s.is_empty() || s == "auto_null" => {
            check(Level::Bad, "Audio", "no output device", Some("pick one: audio (Super+Alt+v)"))
        }
        Some(sink) => {
            let muted = output("pactl", ["get-sink-mute", "@DEFAULT_SINK@"]).is_some_and(|m| m.ends_with("yes"));
            let name = sink.rsplit('.').next().unwrap_or(&sink).to_string();
            if muted {
                check(Level::Warn, "Audio", format!("output {name} is muted"), Some("audio mute"))
            } else {
                check(Level::Good, "Audio", format!("playing through {name}"), None)
            }
        }
    }
}

fn graphics() -> Vec<Check> {
    let mut out = Vec::new();
    let has_vulkan = |dir: &str| {
        fs::read_dir(dir)
            .map(|d| d.filter_map(Result::ok).any(|e| e.file_name().to_string_lossy().starts_with("libvulkan_")))
            .unwrap_or(false)
    };
    if !Path::new("/dev/dri").exists() {
        out.push(check(Level::Note, "Graphics", "no GPU device here", None));
        return out;
    }
    out.push(if has_vulkan("/run/opengl-driver/lib") {
        check(Level::Good, "Graphics", "Vulkan driver present", None)
    } else {
        check(Level::Bad, "Graphics", "no Vulkan driver — games and Proton won't start", Some("rebuild (hardware.graphics)"))
    });
    if which("steam").is_some() {
        out.push(if has_vulkan("/run/opengl-driver-32/lib") {
            check(Level::Good, "Steam", "32-bit graphics present", None)
        } else {
            check(Level::Bad, "Steam", "32-bit graphics missing — Steam games won't start", Some("rebuild"))
        });
        let vdf = home().join(".local/share/Steam/config/config.vdf");
        match fs::read_to_string(&vdf) {
            Ok(s) if s.contains("CompatToolMapping") => {
                out.push(check(Level::Good, "Steam", "Steam Play on for all games", None))
            }
            Ok(_) => out.push(check(Level::Warn, "Steam", "Steam Play isn't on for all games", Some("close Steam, then: steam-setup"))),
            Err(_) => out.push(check(Level::Note, "Steam", "not set up yet — start Steam once", None)),
        }
    }
    out
}

fn updates() -> Vec<Check> {
    let mut out = Vec::new();
    let current = fs::read_link("/run/current-system").ok();
    if let (Ok(ready), Some(cur)) = (fs::read_link("/var/lib/nixos-prebuild/result"), &current) {
        if &ready != cur {
            out.push(check(Level::Note, "Updates", "new NixOS packages are pre-built and waiting", Some("rebuild (takes seconds)")));
        }
    }
    if let Ok(meta) = fs::symlink_metadata("/nix/var/nix/profiles/per-user/root/channels") {
        if let Ok(t) = meta.modified() {
            let days = secs_since(t) / 86_400;
            out.push(if days > 45 {
                check(Level::Warn, "Updates", format!("NixOS packages are {days} days old"), Some("rebuild --upgrade"))
            } else {
                check(Level::Good, "Updates", format!("NixOS packages from {}", ago(secs_since(t))), None)
            });
        }
    }
    if which("update-mine").is_some() {
        if let Some(s) = output("update-mine", ["--status"]) {
            let newer: Vec<&str> = s
                .lines()
                .filter(|l| l.contains("available"))
                .filter_map(|l| l.trim().split(':').next())
                .collect();
            if !newer.is_empty() {
                out.push(check(Level::Note, "Your apps", format!("newer commits: {}", newer.join(", ")), Some("rebuild")));
            }
        }
    }
    out
}

fn backups() -> Option<Check> {
    which("backup")?;
    let stamp = state_dir().join("backup/last-success");
    Some(match fs::metadata(&stamp).and_then(|m| m.modified()) {
        Err(_) => check(Level::Warn, "Backups", "no backup has finished yet", Some("plug in the drive, then: backup now")),
        Ok(t) => {
            let s = secs_since(t);
            if s > 14 * 86_400 {
                check(Level::Warn, "Backups", format!("last backup {}", ago(s)), Some("plug in the drive, then: backup now"))
            } else {
                check(Level::Good, "Backups", format!("last backup {}", ago(s)), None)
            }
        }
    })
}

fn battery() -> Option<Check> {
    let bat = fs::read_dir("/sys/class/power_supply")
        .ok()?
        .filter_map(Result::ok)
        .map(|e| e.path())
        .find(|p| p.file_name().is_some_and(|n| n.to_string_lossy().starts_with("BAT")))?;
    let num = |name: &str| fs::read_to_string(bat.join(name)).ok()?.trim().parse::<f64>().ok();
    let (full, design) = num("energy_full").zip(num("energy_full_design")).or_else(|| num("charge_full").zip(num("charge_full_design")))?;
    let health = (full / design * 100.0).round();
    Some(if health < 70.0 {
        check(Level::Warn, "Battery", format!("holds {health}% of its original charge"), Some("it's wearing out; consider a replacement"))
    } else {
        check(Level::Good, "Battery", format!("holds {health}% of its original charge"), None)
    })
}

fn temperature() -> Option<Check> {
    let hottest = fs::read_dir("/sys/class/thermal")
        .ok()?
        .filter_map(Result::ok)
        .filter_map(|e| fs::read_to_string(e.path().join("temp")).ok()?.trim().parse::<i64>().ok())
        .max()?;
    let c = hottest / 1000;
    Some(match c {
        95.. => check(Level::Bad, "Temperature", format!("{c}°C — too hot"), Some("check fans and dust; see what's busy: htop")),
        85.. => check(Level::Warn, "Temperature", format!("{c}°C — running hot"), Some("see what's busy: htop")),
        _ => check(Level::Good, "Temperature", format!("{c}°C"), None),
    })
}

// ── report ──────────────────────────────────────────────────────────────────

pub fn run(args: &[String]) -> i32 {
    extend_path();
    let quiet = args.iter().any(|a| a == "--notify");

    let mut all = vec![services(false), services(true)];
    all.extend(disk());
    all.push(generations());
    all.push(memory());
    all.push(clock());
    all.extend(network());
    all.push(screenshots());
    all.push(audio());
    all.extend(graphics());
    all.extend(updates());
    all.extend(backups());
    all.extend(battery());
    all.extend(temperature());

    let worst = all.iter().map(|c| c.level).fold(Level::Good, |a, b| if b > a { b } else { a });
    let problems: Vec<&Check> = all.iter().filter(|c| c.level >= Level::Warn).collect();

    if quiet {
        if !problems.is_empty() {
            let body: Vec<String> = problems.iter().map(|c| format!("{}: {}", c.area, c.said)).collect();
            notify(
                "System check",
                &format!("{} thing{} to look at", problems.len(), if problems.len() == 1 { "" } else { "s" }),
                &format!("{}\nDetails: menu → System → System check", body.join("\n")),
                worst == Level::Bad,
            );
        }
        return if worst == Level::Bad { 1 } else { 0 };
    }

    let color = std::io::stdout().is_terminal();
    let paint = |code: &str, s: &str| if color { format!("\x1b[{code}m{s}\x1b[0m") } else { s.to_string() };
    println!("{}\n", paint("1", "Hearth system check"));
    for c in &all {
        let (mark, code) = match c.level {
            Level::Good => ("✓", "32"),
            Level::Note => ("·", "36"),
            Level::Warn => ("!", "33"),
            Level::Bad => ("✗", "31"),
        };
        println!("  {} {:<16} {}", paint(code, mark), c.area, c.said);
        if let Some(fix) = &c.fix {
            if c.level >= Level::Note {
                println!("    {:<16} → {}", "", paint("2", fix));
            }
        }
    }
    println!();
    println!(
        "{}",
        match worst {
            Level::Bad => paint("31", "Something needs fixing — see ✗ above."),
            Level::Warn => paint("33", "Working, with a few things worth a look."),
            _ => paint("32", "Everything looks good."),
        }
    );
    if worst == Level::Bad {
        1
    } else {
        0
    }
}
