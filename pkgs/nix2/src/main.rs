//! nix2 — this system's own tools, in one small fast binary.
//!
//! Called by a tool's name (a link named `nixmenu`, `printer-notify`…) it runs
//! that tool; otherwise the first argument picks one.

mod doctor;
mod game;
mod menu;
mod new;
mod printer;
mod rollback;
mod serial;
mod util;

use std::env;
use std::path::Path;
use std::process::ExitCode;

const HELP: &str = "\
nix2 — this system's own tools

  nix2 menu [category]       the menu (also Super+Alt+Space)
  nix2 doctor [--notify]     check the system, with a fix for anything wrong
  nix2 rollback              go back to an earlier system version
  nix2 new [kind] [name]     start a project with its tools ready
  nix2 serial [port] [baud]  talk to a board over USB serial
  nix2 game start|end        game mode hooks (gamemode runs these)
  nix2 printer-notify        a notification when a 3D print ends

Project kinds: rust, python, c++, go, node, board, micropython
";

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let called = Path::new(args.first().map(String::as_str).unwrap_or("nix2"))
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("nix2");

    let (cmd, rest): (&str, &[String]) = match called {
        "nixmenu" => ("menu", &args[1..]),
        "printer-notify" => ("printer-notify", &args[1..]),
        "nix2-doctor" => ("doctor", &args[1..]),
        _ => match args.get(1) {
            Some(c) => (c.as_str(), &args[2..]),
            None => ("help", &[]),
        },
    };

    let code = match cmd {
        "menu" => menu::run(rest),
        "doctor" => doctor::run(rest),
        "rollback" => rollback::run(rest),
        "game" => game::run(rest),
        "new" => new::run(rest),
        "serial" => serial::run(rest),
        "printer-notify" => printer::run(rest),
        "help" | "-h" | "--help" => {
            print!("{HELP}");
            0
        }
        other => {
            eprintln!("nix2: unknown command '{other}'\n");
            eprint!("{HELP}");
            2
        }
    };
    ExitCode::from(code.clamp(0, 255) as u8)
}
