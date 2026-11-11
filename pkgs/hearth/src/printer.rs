//! printer-notify — a desktop notification when a 3D print finishes or fails.
//!
//! Watches each Moonraker printer's print_stats over its HTTP API and
//! notifies when the state changes. Nothing is stored; it just reacts to
//! state changes. Printers come from $PRINTER_HOSTS (space-separated Moonraker
//! base URLs, set by the printing module from settings.printers) or the
//! command line; $PRINTER_POLL sets the seconds between checks (default 15).

use crate::util::notify_with;
use std::collections::HashMap;
use std::env;
use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::thread::sleep;
use std::time::Duration;

/// "http://ender.local:7125/" → ("ender.local", 7125, "")
fn parse(url: &str) -> Option<(String, u16, String)> {
    let rest = url.strip_prefix("http://")?;
    let (hostport, path) = rest.split_once('/').map(|(h, p)| (h, format!("/{p}"))).unwrap_or((rest, String::new()));
    let (host, port) = match hostport.rsplit_once(':') {
        Some((h, p)) => (h, p.parse().ok()?),
        None => (hostport, 80),
    };
    (!host.is_empty()).then(|| (host.to_string(), port, path.trim_end_matches('/').to_string()))
}

/// The bare host name, for messages.
pub fn short(url: &str) -> &str {
    let s = url.split_once("://").map(|x| x.1).unwrap_or(url);
    let s = s.split(['/', ':']).next().unwrap_or("");
    if s.is_empty() {
        url
    } else {
        s
    }
}

fn get(url: &str) -> Option<String> {
    let (host, port, base) = parse(url)?;
    let addr = (host.as_str(), port).to_socket_addrs().ok()?.next()?;
    let timeout = Duration::from_secs(10);
    let mut conn = TcpStream::connect_timeout(&addr, timeout).ok()?;
    conn.set_read_timeout(Some(timeout)).ok()?;
    conn.set_write_timeout(Some(timeout)).ok()?;
    let req = format!(
        "GET {base}/printer/objects/query?print_stats HTTP/1.0\r\nHost: {host}:{port}\r\nAccept: application/json\r\nConnection: close\r\n\r\n"
    );
    conn.write_all(req.as_bytes()).ok()?;
    let mut buf = Vec::new();
    conn.read_to_end(&mut buf).ok()?;
    let text = String::from_utf8_lossy(&buf);
    let (head, body) = text.split_once("\r\n\r\n")?;
    head.split_whitespace().nth(1).filter(|c| *c == "200")?;
    Some(body.to_string())
}

/// (state, filename) from Moonraker's JSON.
pub fn read_status(body: &str) -> Option<(String, String)> {
    let v: serde_json::Value = serde_json::from_str(body).ok()?;
    let ps = &v["result"]["status"]["print_stats"];
    ps.is_object().then(|| {
        (
            ps["state"].as_str().unwrap_or("").to_string(),
            ps["filename"].as_str().unwrap_or("").to_string(),
        )
    })
}

/// What to say when a printer goes from `prev` to `state`.
pub fn message(prev: &str, state: &str) -> Option<(&'static str, &'static str)> {
    match state {
        "complete" => Some(("✅ Print finished", "normal")),
        "error" => Some(("❌ Print failed", "critical")),
        "cancelled" => Some(("⏹ Print cancelled", "low")),
        "printing" if matches!(prev, "standby" | "complete" | "error" | "cancelled" | "") => {
            Some(("🖨 Print started", "low"))
        }
        _ => None,
    }
}

pub fn run(args: &[String]) -> i32 {
    let mut hosts: Vec<String> = env::var("PRINTER_HOSTS").unwrap_or_default().split_whitespace().map(String::from).collect();
    if hosts.is_empty() {
        hosts = args.to_vec();
    }
    if hosts.is_empty() {
        println!("printer-notify: no printers configured (settings.nix → printers).");
        return 0;
    }
    for h in &hosts {
        if parse(h).is_none() {
            eprintln!("printer-notify: {h}: only plain http://host:port addresses are supported");
        }
    }
    let poll = env::var("PRINTER_POLL").ok().and_then(|s| s.parse().ok()).unwrap_or(15u64).max(1);
    println!("printer-notify: watching {}", hosts.iter().map(|h| short(h)).collect::<Vec<_>>().join(", "));

    let mut last: HashMap<&str, String> = HashMap::new();
    loop {
        for h in &hosts {
            let Some((state, file)) = get(h).as_deref().and_then(read_status) else {
                continue; // printer off or unreachable: try next round
            };
            let prev = last.insert(h, state.clone());
            let Some(prev) = prev.filter(|p| *p != state) else { continue };
            if let Some((title, urgency)) = message(&prev, &state) {
                let name = if file.is_empty() { "print" } else { &file };
                notify_with("Printer", "printer", urgency, title, &format!("{name}\non {}", short(h)));
            }
        }
        sleep(Duration::from_secs(poll));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn urls() {
        assert_eq!(parse("http://ender.local:7125"), Some(("ender.local".into(), 7125, "".into())));
        assert_eq!(parse("http://10.0.0.5/"), Some(("10.0.0.5".into(), 80, "".into())));
        assert_eq!(parse("http://h:80/moon/"), Some(("h".into(), 80, "/moon".into())));
        assert_eq!(parse("https://x"), None);
        assert_eq!(short("http://ender.local:7125/"), "ender.local");
    }

    #[test]
    fn status() {
        let body = r#"{"result":{"eventtime":1,"status":{"print_stats":{"state":"printing","filename":"benchy.gcode"}}}}"#;
        assert_eq!(read_status(body), Some(("printing".into(), "benchy.gcode".into())));
        assert_eq!(read_status("{}"), None);
        assert_eq!(read_status("not json"), None);
    }

    #[test]
    fn transitions() {
        assert_eq!(message("printing", "complete").map(|m| m.0), Some("✅ Print finished"));
        assert_eq!(message("printing", "error").map(|m| m.1), Some("critical"));
        assert_eq!(message("standby", "printing").map(|m| m.0), Some("🖨 Print started"));
        assert_eq!(message("paused", "printing"), None);
        assert_eq!(message("printing", "paused"), None);
    }
}
