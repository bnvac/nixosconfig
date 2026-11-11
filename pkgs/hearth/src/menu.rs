//! The menu (Super+Alt+Space): pick a category, then an action. Backspace
//! with nothing typed goes back to the main list; Escape closes.
//!
//! Entries come from /etc/nixmenu/menu.tsv (built from the modules and
//! settings.nix → menu) and ~/.config/nixmenu/menu (yours, no rebuild):
//!     Category | Label | command          run it
//!     Category | Label | term: command    in a terminal, wait for Enter
//!     Category | Label | tty: command     a full-screen terminal program
//!     Category | Label | url: https://…   open as an app window
//!     hide  | Label                        hide a built-in entry
//!     order | System, Self-hosted, …       category order
//! Running Docker containers that publish a port show up under Self-hosted.

use crate::util::{config_dir, dmenu, extend_path, ok, output, which, Pick};
use std::collections::HashSet;
use std::env;
use std::fs;
use std::os::unix::process::CommandExt;
use std::process::Command;

const STARTER: &str = "\
# Your own nixmenu entries (Super+Alt+Space). Changes apply instantly.
#   Category | Label | command          run it
#   Category | Label | term: command    run in a terminal, wait for Enter
#   Category | Label | tty: command     a full-screen terminal program
#   Category | Label | url: https://…   open as an app window
#   hide  | Label                        hide a built-in entry
#   order | System, Self-hosted, …       category order (listed ones first)
# Examples (remove the # to use):
# My stuff | Notes | tty: nvim ~/notes
# My stuff | Disk usage | term: df -h
# Self-hosted | Home server | url: http://192.168.1.10:9000
# hide | Toggle live snow
";

struct Entry {
    cat: String,
    label: String,
    mode: String,
    run: String,
}

struct Menu {
    entries: Vec<Entry>,
    hidden: HashSet<String>,
}

impl Menu {
    fn add(&mut self, cat: &str, label: &str, mode: &str, run: &str) {
        if !self.hidden.contains(label) {
            self.entries.push(Entry {
                cat: cat.into(),
                label: label.into(),
                mode: mode.into(),
                run: run.into(),
            });
        }
    }
}

/// First published host port of a `docker ps` Ports column, e.g.
/// "0.0.0.0:8096->8096/tcp, :::8096->8096/tcp" → 8096.
pub fn first_port(ports: &str) -> Option<&str> {
    ports.split(", ").find_map(|item| {
        let (left, _) = item.split_once("->")?;
        let p = left.rsplit(':').next()?;
        (!p.is_empty() && p.bytes().all(|b| b.is_ascii_digit())).then_some(p)
    })
}

pub fn run(args: &[String]) -> i32 {
    extend_path();
    let sysmenu = env::var("NIXMENU_FILE").unwrap_or_else(|_| "/etc/nixmenu/menu.tsv".into());
    let usermenu = config_dir().join("nixmenu/menu");
    if !usermenu.exists() {
        if let Some(dir) = usermenu.parent() {
            if fs::create_dir_all(dir).is_ok() {
                let _ = fs::write(&usermenu, STARTER);
            }
        }
    }

    // Your file, pass 1: hides and order apply to the built-ins too.
    let mut menu = Menu {
        entries: Vec::new(),
        hidden: HashSet::new(),
    };
    let mut order: Vec<String> = Vec::new();
    let mut userlines: Vec<String> = Vec::new();
    if let Ok(text) = fs::read_to_string(&usermenu) {
        for raw in text.lines() {
            let line = raw.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let Some((c, rest)) = line.split_once(" | ") else {
                continue;
            };
            match c.trim() {
                "hide" => {
                    menu.hidden.insert(rest.trim().to_string());
                }
                "order" => order.extend(
                    rest.split(',')
                        .map(|x| x.trim().to_string())
                        .filter(|x| !x.is_empty()),
                ),
                _ => userlines.push(line.to_string()),
            }
        }
    }

    // Built-in entries: category, label, mode, needs (or -), command.
    if let Ok(text) = fs::read_to_string(&sysmenu) {
        for line in text.lines() {
            let f: Vec<&str> = line.splitn(5, '\t').collect();
            if f.len() < 5 || f[0].is_empty() {
                continue;
            }
            if f[3] != "-" && which(f[3]).is_none() {
                continue;
            }
            menu.add(f[0], f[1], f[2], f[4]);
        }
    }

    // Your entries (commands may themselves contain " | ").
    for line in &userlines {
        let Some((c, rest)) = line.split_once(" | ") else {
            continue;
        };
        let Some((l, r)) = rest.split_once(" | ") else {
            continue;
        };
        let (c, l, r) = (c.trim(), l.trim(), r.trim());
        let (mode, cmd) = ["term", "tty", "url"]
            .iter()
            .find_map(|m| r.strip_prefix(&format!("{m}:")).map(|x| (*m, x.trim())))
            .unwrap_or(("exec", r));
        menu.add(c, l, mode, cmd);
    }

    // Docker containers — only if Docker is already running (asking a
    // socket-activated daemon would start it just for the menu).
    if which("docker").is_some() && ok("systemctl", ["is-active", "--quiet", "docker.service"]) {
        if let Some(ps) = output("docker", ["ps", "--format", "{{.Names}}\t{{.Ports}}"]) {
            for line in ps.lines() {
                let (name, ports) = line.split_once('\t').unwrap_or((line, ""));
                if let Some(port) = first_port(ports) {
                    menu.add(
                        "Self-hosted",
                        &format!("{name} (docker :{port})"),
                        "url",
                        &format!("http://127.0.0.1:{port}"),
                    );
                }
            }
        }
    }

    if menu.entries.is_empty() {
        eprintln!("nixmenu: no entries ({sysmenu} missing?)");
        return 1;
    }

    // Categories: your `order` first, then the rest as they appeared.
    let mut cats: Vec<String> = Vec::new();
    for c in order.iter().chain(menu.entries.iter().map(|e| &e.cat)) {
        if !cats.contains(c) && menu.entries.iter().any(|e| &e.cat == c) {
            cats.push(c.clone());
        }
    }

    let mut cat = args.first().cloned().unwrap_or_default();
    loop {
        if cat.is_empty() {
            match dmenu("nix:", &cats, true) {
                Pick::Chose(c) => cat = c,
                Pick::Back => continue, // Backspace at the top: stay
                Pick::Cancel => return 0,
            }
        }
        let shown: Vec<String> = menu
            .entries
            .iter()
            .filter(|e| e.cat == cat)
            .map(|e| e.label.clone())
            .collect();
        if shown.is_empty() {
            cat.clear(); // typed something that isn't a category
            continue;
        }
        let sel = match dmenu(&format!("{cat}:"), &shown, true) {
            Pick::Chose(s) => s,
            Pick::Back => {
                cat.clear();
                continue;
            }
            Pick::Cancel => return 0,
        };
        if let Some(e) = menu.entries.iter().find(|e| e.cat == cat && e.label == sel) {
            return launch(&e.mode, &e.run);
        }
        // typed something that isn't an entry: show the same section again
    }
}

fn launch(mode: &str, run: &str) -> i32 {
    let err = match mode {
        "term" => Command::new("st")
            .args([
                "-e",
                "sh",
                "-c",
                &format!("{run}; echo; printf '[enter] '; read -r _"),
            ])
            .exec(),
        "tty" => Command::new("st").args(["-e", "sh", "-c", run]).exec(),
        "url" => {
            if which("chromium").is_some() {
                Command::new("chromium").arg(format!("--app={run}")).exec()
            } else {
                Command::new("xdg-open").arg(run).exec()
            }
        }
        _ => Command::new("sh").args(["-c", run]).exec(),
    };
    eprintln!("nixmenu: couldn't start {run}: {err}");
    1
}

#[cfg(test)]
mod tests {
    use super::first_port;

    #[test]
    fn ports() {
        assert_eq!(
            first_port("0.0.0.0:8096->8096/tcp, :::8096->8096/tcp"),
            Some("8096")
        );
        assert_eq!(first_port("6379/tcp"), None);
        assert_eq!(first_port(""), None);
        assert_eq!(first_port("127.0.0.1:3001->3001/tcp"), Some("3001"));
    }
}
