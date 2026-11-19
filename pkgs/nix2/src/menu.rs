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
//! Generated menus in ~/.local/state/nixmenu/*.tsv (same format as the system
//! file) are read too: `homelab-discover` writes your home server's services there.

use crate::util::{config_dir, dmenu, extend_path, ok, output, state_dir, which, Pick};
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

/// Lines of a generated menu file: category, label, mode, needs (ignored here), command.
/// Only the modes the menu knows are accepted; anything malformed is skipped.
pub fn parse_tsv(text: &str) -> Vec<(&str, &str, &str, &str)> {
    text.lines()
        .filter_map(|line| {
            let f: Vec<&str> = line.splitn(5, '\t').collect();
            (f.len() == 5
                && !f[0].is_empty()
                && !f[1].is_empty()
                && ["exec", "term", "tty", "url"].contains(&f[2]))
            .then(|| (f[0], f[1], f[2], f[4]))
        })
        .collect()
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

    // Generated entries (e.g. another machine's homelab services), same TSV format.
    if let Ok(dir) = fs::read_dir(state_dir().join("nixmenu")) {
        let mut files: Vec<_> = dir
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|x| x == "tsv"))
            .collect();
        files.sort();
        for f in files {
            if let Ok(text) = fs::read_to_string(&f) {
                for (c, l, m, r) in parse_tsv(&text) {
                    menu.add(c, l, m, r);
                }
            }
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

    // The top level: the categories, then "Search everything". Typing the
    // name of any entry there (not a category) finds it too.
    let mut top = cats.clone();
    top.push(EVERYTHING.to_string());

    let mut cat = args.first().cloned().unwrap_or_default();
    loop {
        if cat.is_empty() {
            match dmenu("nix:", &top, true) {
                Pick::Chose(c) => cat = c,
                Pick::Back => continue, // Backspace at the top: stay
                Pick::Cancel => return 0,
            }
        }
        if !cats.contains(&cat) {
            // "Search everything", or words typed at the top: every entry
            // whose name matches, wherever it lives.
            let words = if cat == EVERYTHING {
                String::new()
            } else {
                cat.clone()
            };
            let found = search(&menu.entries, &words);
            cat.clear();
            if found.is_empty() {
                continue;
            }
            let rows: Vec<String> = found.iter().map(|e| row(e)).collect();
            let prompt = if words.is_empty() {
                "Everything:".to_string()
            } else {
                format!("\"{words}\":")
            };
            match dmenu(&prompt, &rows, true) {
                Pick::Chose(sel) => {
                    if let Some(e) = found.iter().find(|e| row(e) == sel) {
                        return launch(&e.mode, &e.run);
                    }
                }
                Pick::Back => {}
                Pick::Cancel => return 0,
            }
            continue;
        }
        let shown: Vec<String> = menu
            .entries
            .iter()
            .filter(|e| e.cat == cat)
            .map(|e| e.label.clone())
            .collect();
        if shown.is_empty() {
            cat.clear();
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

const EVERYTHING: &str = "🔍 Search everything";

/// How an entry shows in a search: its name, then where it lives.
fn row(e: &Entry) -> String {
    format!("{}   ·  {}", e.label, e.cat)
}

/// Entries whose name (or category) holds every typed word, in any order and
/// case; all of them for no words. Best first: name starts with the words.
fn search<'a>(entries: &'a [Entry], words: &str) -> Vec<&'a Entry> {
    let words: Vec<String> = words.split_whitespace().map(str::to_lowercase).collect();
    let mut hits: Vec<&Entry> = entries
        .iter()
        .filter(|e| {
            let hay = format!("{} {}", e.label, e.cat).to_lowercase();
            words.iter().all(|w| hay.contains(w.as_str()))
        })
        .collect();
    if let Some(first) = words.first() {
        hits.sort_by_key(|e| !e.label.to_lowercase().starts_with(first.as_str()));
    }
    hits
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
    use super::{first_port, parse_tsv, search, Entry};

    fn e(cat: &str, label: &str) -> Entry {
        Entry {
            cat: cat.into(),
            label: label.into(),
            mode: "exec".into(),
            run: "true".into(),
        }
    }

    #[test]
    fn finds_entries_anywhere() {
        let all = vec![
            e("System", "Shutdown timer (turn off later)"),
            e("Games", "Steam"),
            e("Games", "Steam won't start? Fix it"),
            e("Proton", "VPN: connect to the fastest server"),
        ];
        let names = |q: &str| {
            search(&all, q)
                .iter()
                .map(|x| x.label.clone())
                .collect::<Vec<_>>()
        };
        assert_eq!(names("steam").len(), 2);
        assert_eq!(names("STEAM")[0], "Steam");
        assert_eq!(
            names("vpn fastest"),
            vec!["VPN: connect to the fastest server"]
        );
        assert_eq!(names("proton"), vec!["VPN: connect to the fastest server"]); // by category too
        assert_eq!(names("timer off"), vec!["Shutdown timer (turn off later)"]);
        assert!(names("banana").is_empty());
        assert_eq!(search(&all, "").len(), 4);
    }

    #[test]
    fn generated_menu_files() {
        let text = "Self-hosted\tGitea (live)\turl\t-\thttp://git.home.arpa\n\
                    broken line\n\
                    Self-hosted\tBad mode\tsudo\t-\trm -rf /\n\
                    \tno category\turl\t-\thttp://x\n\
                    Games\tMinecraft on\tterm\t-\thomelab minecraft on | tee log";
        assert_eq!(
            parse_tsv(text),
            vec![
                ("Self-hosted", "Gitea (live)", "url", "http://git.home.arpa"),
                (
                    "Games",
                    "Minecraft on",
                    "term",
                    "homelab minecraft on | tee log"
                ),
            ]
        );
    }

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
