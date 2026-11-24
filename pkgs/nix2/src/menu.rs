//! The menu (Super+Alt+Space): folders of actions. A category can hold
//! sub-folders ("System/Updates" is the Updates folder inside System); they
//! show first, marked ›. Backspace with nothing typed goes up a folder;
//! Escape closes. Typing anything that isn't on the list searches everything.
//!
//! Toggles are one line for one thing ("VPN: on ●"): picking it switches it
//! the other way. Their run field is "state-command␟on-command␟off-command"
//! (state exits 0 when it's on), mode toggle (quiet, with a notification) or
//! toggleterm (in a terminal: for ones that ask for your password).
//!
//! Entries come from /etc/nixmenu/menu.tsv (built from the modules and
//! settings.nix → menu) and ~/.config/nixmenu/menu (yours, no rebuild):
//!     Category | Label | command          run it
//!     Category | Label | term: command    in a terminal, wait for Enter
//!     Category | Label | tty: command     a full-screen terminal program
//!     Category | Label | url: https://…   open as an app window
//!     Folder/Sub | Label | …               an entry inside a sub-folder
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
#   Folder/Sub | Label | command        inside a sub-folder (made as needed)
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
                && ["exec", "term", "tty", "url", "toggle", "toggleterm"].contains(&f[2]))
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

    // Top-level folders: your `order` first, then the rest as they appeared.
    let mut order_top: Vec<String> = Vec::new();
    for c in order
        .iter()
        .cloned()
        .chain(menu.entries.iter().map(|e| top_of(&e.cat).to_string()))
    {
        if !order_top.contains(&c) && menu.entries.iter().any(|e| top_of(&e.cat) == c) {
            order_top.push(c);
        }
    }

    let mut path = args.first().cloned().unwrap_or_default();
    loop {
        let (folders, items) = if path.is_empty() {
            (order_top.clone(), Vec::new())
        } else {
            children(&menu.entries, &path)
        };
        if !path.is_empty() && folders.is_empty() && items.is_empty() {
            path.clear(); // a folder that doesn't exist (any more)
            continue;
        }
        let mut rows: Vec<String> = folders.iter().map(|f| folder_row(f)).collect();
        rows.extend(items.iter().map(|e| item_row(e)));
        if path.is_empty() {
            rows.push(EVERYTHING.to_string());
        }
        let prompt = if path.is_empty() {
            "parajynx:".to_string()
        } else {
            format!("{}:", path.replace('/', " › "))
        };
        let sel = match dmenu(&prompt, &rows, true) {
            Pick::Chose(s) => s,
            Pick::Back => {
                path = up(&path);
                continue;
            }
            Pick::Cancel => return 0,
        };
        if let Some(f) = folders.iter().find(|f| folder_row(f) == sel) {
            path = if path.is_empty() {
                f.clone()
            } else {
                format!("{path}/{f}")
            };
            continue;
        }
        if let Some(e) = items.iter().find(|e| item_row(e) == sel) {
            return launch(e);
        }
        // "Search everything", or words typed that aren't on the list: every
        // entry whose name (or folder) matches, wherever it lives.
        let words = if sel == EVERYTHING {
            String::new()
        } else {
            sel
        };
        let found = search(&menu.entries, &words);
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
                    return launch(e);
                }
            }
            Pick::Back => {}
            Pick::Cancel => return 0,
        }
    }
}

fn top_of(cat: &str) -> &str {
    cat.split('/').next().unwrap_or(cat)
}

fn up(path: &str) -> String {
    path.rsplit_once('/')
        .map(|(a, _)| a.to_string())
        .unwrap_or_default()
}

/// What's directly inside a folder: its sub-folders (in the order they first
/// appear) and its own entries.
fn children<'a>(entries: &'a [Entry], path: &str) -> (Vec<String>, Vec<&'a Entry>) {
    let prefix = format!("{path}/");
    let mut folders: Vec<String> = Vec::new();
    let mut items = Vec::new();
    for e in entries {
        if e.cat == path {
            items.push(e);
        } else if let Some(rest) = e.cat.strip_prefix(&prefix) {
            let f = rest.split('/').next().unwrap_or(rest).to_string();
            if !f.is_empty() && !folders.contains(&f) {
                folders.push(f);
            }
        }
    }
    (folders, items)
}

fn folder_row(name: &str) -> String {
    format!("{name}  ›")
}

/// A toggle's (state, on, off) commands.
fn toggle_parts(e: &Entry) -> Option<(&str, &str, &str)> {
    if !e.mode.starts_with("toggle") {
        return None;
    }
    let mut p = e.run.split('\u{1f}');
    Some((p.next()?, p.next()?, p.next()?))
}

fn is_on(state: &str) -> bool {
    ok("sh", ["-c", &format!("{state} >/dev/null 2>&1")])
}

/// How an entry shows inside its folder: toggles say whether they're on.
fn item_row(e: &Entry) -> String {
    match toggle_parts(e) {
        Some((state, _, _)) => {
            if is_on(state) {
                format!("{}: on ●", e.label)
            } else {
                format!("{}: off ○", e.label)
            }
        }
        None => e.label.clone(),
    }
}

const EVERYTHING: &str = "🔍 Search everything";

/// How an entry shows in a search: its name, then where it lives.
fn row(e: &Entry) -> String {
    format!("{}   ·  {}", e.label, e.cat.replace('/', " › "))
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

fn launch(e: &Entry) -> i32 {
    let (mode, run) = (e.mode.as_str(), e.run.as_str());
    let err = match (mode, toggle_parts(e)) {
        (_, Some((state, on, off))) => {
            let (cmd, now) = if is_on(state) {
                (off, "off")
            } else {
                (on, "on")
            };
            if mode == "toggleterm" {
                Command::new("st")
                    .args([
                        "-e",
                        "sh",
                        "-c",
                        &format!("{cmd}; echo; printf '[enter] '; read -r _"),
                    ])
                    .exec()
            } else {
                // Quietly, then say how it went.
                Command::new("sh")
                    .args([
                        "-c",
                        "out=$(sh -c \"$1\" 2>&1) && t=\"$2: $3\" || t=\"$2: didn't work\"; \
                         notify-send -a Menu \"$t\" \"$(printf '%s' \"$out\" | tail -n 3)\" 2>/dev/null",
                        "sh",
                        cmd,
                        &e.label,
                        now,
                    ])
                    .exec()
            }
        }
        ("term", _) => Command::new("st")
            .args([
                "-e",
                "sh",
                "-c",
                &format!("{run}; echo; printf '[enter] '; read -r _"),
            ])
            .exec(),
        ("tty", _) => Command::new("st").args(["-e", "sh", "-c", run]).exec(),
        ("url", _) => {
            if let Some(b) = ["brave", "chromium"]
                .into_iter()
                .find(|b| which(b).is_some())
            {
                Command::new(b).arg(format!("--app={run}")).exec()
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
    use super::{children, first_port, parse_tsv, search, toggle_parts, up, Entry};

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
    fn folders() {
        let all = vec![
            e("System", "Lock screen"),
            e("System/Updates", "Update system"),
            e("System/Updates", "Roll back"),
            e("System/Look/Fonts", "Pick a font"),
            e("System", "Suspend"),
            e("Games", "Steam"),
        ];
        let (f, i) = children(&all, "System");
        assert_eq!(f, vec!["Updates", "Look"]);
        assert_eq!(
            i.iter().map(|x| x.label.as_str()).collect::<Vec<_>>(),
            vec!["Lock screen", "Suspend"]
        );
        let (f, i) = children(&all, "System/Look");
        assert_eq!(f, vec!["Fonts"]);
        assert!(i.is_empty());
        let (f, i) = children(&all, "Nope");
        assert!(f.is_empty() && i.is_empty());
        assert_eq!(up("System/Look/Fonts"), "System/Look");
        assert_eq!(up("System"), "");
        // search finds things in sub-folders by the folder's name too
        assert_eq!(search(&all, "updates").len(), 2);
    }

    #[test]
    fn toggles() {
        let t = Entry {
            cat: "Network".into(),
            label: "VPN".into(),
            mode: "toggle".into(),
            run: "vpn state\u{1f}vpn on\u{1f}vpn off".into(),
        };
        assert_eq!(toggle_parts(&t), Some(("vpn state", "vpn on", "vpn off")));
        assert_eq!(toggle_parts(&e("System", "Lock")), None);
        assert_eq!(
            parse_tsv("Network\tVPN\ttoggle\t-\ta\u{1f}b\u{1f}c"),
            vec![("Network", "VPN", "toggle", "a\u{1f}b\u{1f}c")]
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
