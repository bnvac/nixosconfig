//! menu — this system's own tools, in one small fast binary.
//!
//! `menu` on its own opens the menu; `menu <tool>` runs a tool; `menu
//! <category>` opens the menu at that folder. Called by another name (a link
//! named `nixmenu`, `printer-notify`, or the old `nix2`) it still works.

mod displays;
mod doctor;
mod game;
mod menu;
mod new;
mod printer;
mod rollback;
mod serial;
mod util;

use std::env;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Command, ExitCode};

const HELP: &str = "\
menu — this system's tools

  menu                       the menu (also Super+Alt+Space)
  menu \"Network & privacy\"   the menu, opened at that folder
  menu update                pull the newest system and rebuild
  menu setup [set KEY VAL]   this machine's settings (settings.local.nix)
  menu doctor [--fix]        check the system, with a fix for anything wrong
  menu displays [mirror|…]   screens: mirror, extend, resolution, rotation
  menu rollback              go back to an earlier system version
  menu new [kind] [name]     start a project with its tools ready
  menu serial [port] [baud]  talk to a board over USB serial
  menu game start|end        game mode hooks (gamemode runs these)
  menu printer-notify        a notification when a 3D print ends

Project kinds: rust, python, c++, go, node, board, micropython
";

/// Tools that are their own programs: `menu update` runs `nixup`, etc.
fn hand_over(program: &str, rest: &[String]) -> i32 {
    let err = Command::new(program).args(rest).exec();
    eprintln!("menu: couldn't run {program}: {err}");
    1
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let called = Path::new(args.first().map(String::as_str).unwrap_or("menu"))
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("menu");

    let (cmd, rest): (&str, &[String]) = match called {
        "nixmenu" => ("menu", &args[1..]),
        "printer-notify" => ("printer-notify", &args[1..]),
        "nix2-doctor" => ("doctor", &args[1..]),
        // `menu` alone opens the menu; the old `nix2` alone shows the help.
        "menu" if args.len() < 2 => ("menu", &[]),
        _ => match args.get(1) {
            Some(c) => (c.as_str(), &args[2..]),
            None => ("help", &[]),
        },
    };

    let code = match cmd {
        "menu" => menu::run(rest),
        "doctor" => doctor::run(rest),
        "displays" | "display" => displays::run(rest),
        "rollback" => rollback::run(rest),
        "game" => game::run(rest),
        "new" => new::run(rest),
        "serial" => serial::run(rest),
        "printer-notify" => printer::run(rest),
        "update" => hand_over("nixup", rest),
        "setup" => hand_over("nix2-setup", rest),
        "help" | "-h" | "--help" => {
            print!("{HELP}");
            0
        }
        // anything else is a menu folder: `menu Games`, `menu "Network & privacy"`
        _ => menu::run(&args[1..]),
    };
    ExitCode::from(code.clamp(0, 255) as u8)
}
