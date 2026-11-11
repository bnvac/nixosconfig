//! hearth game start|end — gamemode runs these when a game starts and when
//! the last one closes. While you play: notifications wait, the live
//! wallpaper freezes and the snow stops (both cost GPU time). Everything goes
//! back exactly as it was afterwards. (gamemode itself sets the CPU to
//! performance.)

use crate::util::{extend_path, load_x_env, notify, ok, output, runtime_dir};
use std::fs;

fn wallpaper_pids() -> Vec<String> {
    output("pgrep", ["-f", "linux-wallpaperengine"])
        .map(|s| s.lines().map(String::from).collect())
        .unwrap_or_default()
}

fn snow_running() -> bool {
    ok("pgrep", ["-f", "(^|/)xsnow( |$)"])
}

pub fn run(args: &[String]) -> i32 {
    extend_path();
    load_x_env();
    let state = runtime_dir().join("hearth-game");
    match args.first().map(String::as_str) {
        Some("start") => {
            if state.exists() {
                return 0; // a second game; already in game mode
            }
            let was_paused = output("dunstctl", ["is-paused"]).is_some_and(|s| s == "true");
            let snow = snow_running();
            let walls = wallpaper_pids();

            notify("Game mode", "Game mode on", "Notifications wait until you're done.", false);
            if !was_paused {
                ok("dunstctl", ["set-paused", "true"]);
            }
            if snow {
                ok("snow", ["off"]);
            }
            for pid in &walls {
                ok("kill", ["-STOP", pid]);
            }
            let saved = format!(
                "paused={}\nsnow={}\nwallpaper={}\n",
                was_paused,
                snow,
                walls.join(",")
            );
            let _ = fs::write(&state, saved);
            0
        }
        Some("end") => {
            let saved = fs::read_to_string(&state).unwrap_or_default();
            let get = |k: &str| {
                saved
                    .lines()
                    .find_map(|l| l.strip_prefix(&format!("{k}=")))
                    .unwrap_or("")
                    .to_string()
            };
            for pid in get("wallpaper").split(',').filter(|p| !p.is_empty()) {
                ok("kill", ["-CONT", pid]);
            }
            if get("snow") == "true" {
                ok("snow", ["on"]);
            }
            if get("paused") != "true" {
                ok("dunstctl", ["set-paused", "false"]);
            }
            let _ = fs::remove_file(&state);
            0
        }
        _ => {
            eprintln!("usage: hearth game start|end");
            2
        }
    }
}
