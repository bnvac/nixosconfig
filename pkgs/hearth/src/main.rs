//! hearth — this system's own tools, in one small fast binary.
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
hearth — this system's own tools

  hearth menu [category]     the menu (Super+Alt+Space; also runs as `nixmenu`)
  hearth doctor [--notify]   check that everything works, with fixes for what doesn't
  hearth rollback            go back to an earlier system version
  hearth game start|end      game mode hooks (gamemode runs these for you)
  hearth new [kind] [name]   start a coding project with its tools ready (rust, python, c++, go, node)
  hearth serial [port] [baud] talk to a board over USB serial (lists boards by name)
  hearth printer-notify      watch 3D printers, notify when a print ends
";

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let called = Path::new(args.first().map(String::as_str).unwrap_or("hearth"))
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("hearth");

    let (cmd, rest): (&str, &[String]) = match called {
        "nixmenu" => ("menu", &args[1..]),
        "printer-notify" => ("printer-notify", &args[1..]),
        "hearth-doctor" => ("doctor", &args[1..]),
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
            eprintln!("hearth: unknown command '{other}'\n");
            eprint!("{HELP}");
            2
        }
    };
    ExitCode::from(code.clamp(0, 255) as u8)
}
