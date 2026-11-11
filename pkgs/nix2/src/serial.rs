//! nix2 serial [PORT] [BAUD] — talk to a board over USB serial (Arduino,
//! ESP32, Pico, any USB-serial adapter). Lists what's plugged in by name
//! ("Raspberry Pi Pico on ttyACM0"), opens the one you pick in tio, which
//! reconnects by itself when you reflash or replug the board.
//! Quit: Ctrl+t then q.

use crate::util::{ask, extend_path, which};
use std::fs;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

pub struct Port {
    pub dev: String,
    pub name: String,
}

fn read(p: &Path) -> Option<String> {
    fs::read_to_string(p)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

/// Walk up from the tty's device to the USB device that has a product name.
fn describe(sys: &Path) -> String {
    let mut dir = fs::canonicalize(sys.join("device")).ok();
    for _ in 0..4 {
        let Some(d) = dir else { break };
        let product = read(&d.join("product"));
        if product.is_some() || read(&d.join("idVendor")).is_some() {
            let maker = read(&d.join("manufacturer"));
            let ids = match (read(&d.join("idVendor")), read(&d.join("idProduct"))) {
                (Some(v), Some(p)) => format!(" [{v}:{p}]"),
                _ => String::new(),
            };
            return match (maker, product) {
                (Some(m), Some(p)) if !p.starts_with(&m) => format!("{m} {p}{ids}"),
                (_, Some(p)) => format!("{p}{ids}"),
                (Some(m), None) => format!("{m}{ids}"),
                _ => format!("USB serial{ids}"),
            };
        }
        dir = d.parent().map(PathBuf::from);
    }
    "serial port".into()
}

pub fn ports(sys_root: &Path) -> Vec<Port> {
    let mut out: Vec<Port> = fs::read_dir(sys_root)
        .map(|d| {
            d.filter_map(Result::ok)
                .filter_map(|e| {
                    let n = e.file_name().to_string_lossy().to_string();
                    (n.starts_with("ttyUSB") || n.starts_with("ttyACM")).then(|| Port {
                        dev: format!("/dev/{n}"),
                        name: describe(&e.path()),
                    })
                })
                .collect()
        })
        .unwrap_or_default();
    out.sort_by(|a, b| a.dev.cmp(&b.dev));
    out
}

pub fn run(args: &[String]) -> i32 {
    extend_path();
    let baud = args
        .iter()
        .find(|a| a.parse::<u32>().is_ok())
        .cloned()
        .unwrap_or_else(|| "115200".into());
    let port = if let Some(p) = args
        .iter()
        .find(|a| a.starts_with("/dev/") || a.starts_with("tty"))
    {
        if p.starts_with('/') {
            p.clone()
        } else {
            format!("/dev/{p}")
        }
    } else {
        let found = ports(Path::new("/sys/class/tty"));
        match found.len() {
            0 => {
                println!("No serial boards plugged in.");
                println!(
                    "Plug one in over USB (a data cable, not charge-only) and run this again."
                );
                println!("A Pico in BOOTSEL mode shows up as a drive instead; flash it with: picotool load -x FILE.uf2");
                return 1;
            }
            1 => found[0].dev.clone(),
            _ => {
                println!("Boards plugged in:\n");
                for (i, p) in found.iter().enumerate() {
                    println!("  {}  {}  ({})", i + 1, p.name, p.dev);
                }
                let Some(a) = ask("\nWhich one? [1] ") else {
                    return 0;
                };
                let i = if a.is_empty() {
                    1
                } else {
                    a.parse::<usize>().unwrap_or(0)
                };
                match found.get(i.wrapping_sub(1)) {
                    Some(p) => p.dev.clone(),
                    None => {
                        eprintln!("Not one of those.");
                        return 2;
                    }
                }
            }
        }
    };

    if fs::metadata(&port).is_err() {
        eprintln!("{port} isn't there — is the board plugged in?");
        return 1;
    }
    if fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(&port)
        .is_err()
    {
        eprintln!("No permission to open {port}. You need to be in the 'dialout' group");
        eprintln!("(nix² adds you; log out and back in once after installing).");
        return 1;
    }
    println!("{port} at {baud} baud — quit with Ctrl+t then q\n");
    let err = if which("tio").is_some() {
        Command::new("tio").args(["-b", &baud, &port]).exec()
    } else {
        Command::new("picocom").args(["-b", &baud, &port]).exec()
    };
    eprintln!("nix2 serial: couldn't start a serial terminal: {err}");
    1
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;

    #[test]
    fn lists_boards_by_name() {
        let root = std::env::temp_dir().join(format!("nix2-serial-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        // /sys/bus/usb/devices/1-1 (the board) / 1-1:1.0 (its interface)
        let usb = root.join("devices/1-1");
        let intf = usb.join("1-1:1.0");
        fs::create_dir_all(&intf).unwrap();
        fs::write(usb.join("manufacturer"), "Raspberry Pi\n").unwrap();
        fs::write(usb.join("product"), "Pico\n").unwrap();
        fs::write(usb.join("idVendor"), "2e8a\n").unwrap();
        fs::write(usb.join("idProduct"), "000a\n").unwrap();
        let tty = root.join("class/ttyACM0");
        fs::create_dir_all(&tty).unwrap();
        symlink(&intf, tty.join("device")).unwrap();
        fs::create_dir_all(root.join("class/ttyS0")).unwrap(); // a built-in port: not listed

        let found = ports(&root.join("class"));
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].dev, "/dev/ttyACM0");
        assert_eq!(found[0].name, "Raspberry Pi Pico [2e8a:000a]");
        let _ = fs::remove_dir_all(&root);
    }
}
