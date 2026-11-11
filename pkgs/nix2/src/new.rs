//! nix2 new [kind] [name] — start a project in ~/projects/NAME with its
//! toolchain ready: a shell.nix (compiler, language server, formatter), an
//! .envrc so the tools load the moment you `cd` in (direnv), a .gitignore,
//! a hello-world, and a git repo. Nothing gets installed system-wide.

use crate::util::{ask, extend_path, home, ok, which};
use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;

struct Kind {
    key: &'static str,
    about: &'static str,
    packages: &'static str,
    ignore: &'static str,
    files: &'static [(&'static str, &'static str)],
    run: &'static str,
    /// The `just` recipes: the same commands in every language.
    just: &'static str,
}

const KINDS: &[Kind] = &[
    Kind {
        key: "rust",
        about: "Rust (cargo, rust-analyzer, clippy)",
        packages: "cargo rustc rust-analyzer clippy rustfmt bacon",
        ignore: "target/\n",
        files: &[
            ("Cargo.toml", "[package]\nname = \"NAME\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n[dependencies]\n"),
            ("src/main.rs", "fn main() {\n    println!(\"Hello from NAME!\");\n}\n"),
        ],
        run: "cargo run",
        just: "# just — this project's commands (`just` lists them)\n\nrun *args:\n    cargo run -- {{args}}\n\ntest:\n    cargo test\n\n# rebuild + rerun on every save\nwatch:\n    bacon run\n\nrelease:\n    cargo build --release\n\nfmt:\n    cargo fmt && cargo clippy --fix --allow-dirty --allow-staged\n",
    },
    Kind {
        key: "python",
        about: "Python (ruff, pyright, pytest)",
        packages: "python3 ruff pyright python3Packages.pytest",
        ignore: "__pycache__/\n.venv/\n*.pyc\n",
        files: &[("main.py", "def main():\n    print(\"Hello from NAME!\")\n\n\nif __name__ == \"__main__\":\n    main()\n")],
        run: "python main.py",
        just: "# just — this project's commands (`just` lists them)\n\nrun *args:\n    python main.py {{args}}\n\ntest:\n    pytest\n\n# rerun on every save\nwatch:\n    watchexec -e py -r -- python main.py\n\nfmt:\n    ruff format . && ruff check --fix .\n",
    },
    Kind {
        key: "c++",
        about: "C / C++ (CMake, Ninja, clangd, gdb)",
        packages: "gcc cmake ninja clang-tools gdb",
        ignore: "build/\n.cache/\ncompile_commands.json\n",
        files: &[
            (
                "CMakeLists.txt",
                "cmake_minimum_required(VERSION 3.20)\nproject(NAME CXX)\nset(CMAKE_CXX_STANDARD 20)\nset(CMAKE_EXPORT_COMPILE_COMMANDS ON)\nadd_executable(NAME src/main.cpp)\n",
            ),
            ("src/main.cpp", "#include <iostream>\n\nint main() {\n    std::cout << \"Hello from NAME!\\n\";\n}\n"),
        ],
        run: "cmake -B build -G Ninja && cmake --build build && ./build/NAME",
        just: "# just — this project's commands (`just` lists them)\n\nbuild:\n    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug\n    cmake --build build\n\nrun *args: build\n    ./build/NAME {{args}}\n\ntest: build\n    ctest --test-dir build --output-on-failure\n\n# rebuild + rerun on every save\nwatch:\n    watchexec -e cpp,hpp,c,h,txt -r -- just run\n\nrelease:\n    cmake -S . -B build-release -G Ninja -DCMAKE_BUILD_TYPE=Release\n    cmake --build build-release\n\nfmt:\n    clang-format -i src/*\n",
    },
    Kind {
        key: "go",
        about: "Go (gopls)",
        packages: "go gopls",
        ignore: "/NAME\n",
        files: &[
            ("go.mod", "module NAME\n\ngo 1.22\n"),
            ("main.go", "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(\"Hello from NAME!\")\n}\n"),
        ],
        run: "go run .",
        just: "# just — this project's commands (`just` lists them)\n\nrun *args:\n    go run . {{args}}\n\ntest:\n    go test ./...\n\n# rebuild + rerun on every save\nwatch:\n    watchexec -e go -r -- go run .\n\nrelease:\n    go build -trimpath -ldflags='-s -w' -o NAME .\n\nfmt:\n    gofmt -w .\n",
    },
    Kind {
        key: "node",
        about: "JavaScript / TypeScript (Node.js)",
        packages: "nodejs typescript typescript-language-server",
        ignore: "node_modules/\ndist/\n",
        files: &[
            ("package.json", "{\n  \"name\": \"NAME\",\n  \"version\": \"0.1.0\",\n  \"type\": \"module\",\n  \"scripts\": { \"start\": \"node index.js\" }\n}\n"),
            ("index.js", "console.log(\"Hello from NAME!\");\n"),
        ],
        run: "npm start",
        just: "# just — this project's commands (`just` lists them)\n\nrun *args:\n    node index.js {{args}}\n\ntest:\n    node --test\n\n# rerun on every save\nwatch:\n    node --watch index.js\n",
    },
    Kind {
        key: "board",
        about: "Microcontroller board, C++ (PlatformIO: Pico, ESP32, Arduino…)",
        packages: "platformio",
        ignore: ".pio/\n",
        files: &[
            (
                "platformio.ini",
                "; Which board: change `board` (and `platform` to match), e.g.\n\
                 ;   Raspberry Pi Pico   platform = raspberrypi   board = pico\n\
                 ;   ESP32               platform = espressif32   board = esp32dev\n\
                 ;   Arduino Uno         platform = atmelavr      board = uno\n\
                 ; Every board: pio boards <name>\n\
                 [env:board]\nplatform = raspberrypi\nboard = pico\nframework = arduino\nmonitor_speed = 115200\n",
            ),
            (
                "src/main.cpp",
                "#include <Arduino.h>\n\nvoid setup() {\n    Serial.begin(115200);\n    pinMode(LED_BUILTIN, OUTPUT);\n}\n\nvoid loop() {\n    digitalWrite(LED_BUILTIN, !digitalRead(LED_BUILTIN));\n    Serial.println(\"Hello from NAME!\");\n    delay(500);\n}\n",
            ),
        ],
        run: "just flash && just monitor",
        just: "# just — this project's commands (`just` lists them)\n\nbuild:\n    pio run\n\n# build and upload to the board (Pico: hold BOOTSEL while plugging in, the first time)\nflash:\n    pio run -t upload\n\n# the board's serial output (quit: Ctrl+c)\nmonitor:\n    pio device monitor\n\n# rebuild on every save\nwatch:\n    watchexec -e cpp,h,ini -- pio run\n\nclean:\n    pio run -t clean\n",
    },
    Kind {
        key: "micropython",
        about: "Microcontroller board, Python (MicroPython / CircuitPython: Pico, ESP32…)",
        packages: "mpremote",
        ignore: "",
        files: &[(
            "main.py",
            "# Runs on the board. Copy it over with: just flash\nfrom machine import Pin\nimport time\n\nled = Pin(\"LED\", Pin.OUT)\nwhile True:\n    led.toggle()\n    print(\"Hello from NAME!\")\n    time.sleep(0.5)\n",
        )],
        run: "just flash && just repl",
        just: "# just — this project's commands (`just` lists them)\n# The board needs MicroPython on it first: https://micropython.org/download\n\n# copy main.py to the board and restart it\nflash:\n    mpremote cp main.py :main.py + reset\n\n# run main.py on the board without saving it there\nrun:\n    mpremote run main.py\n\n# the board's Python prompt (quit: Ctrl+])\nrepl:\n    mpremote repl\n\n# copy to the board on every save\nwatch:\n    watchexec -e py -- just flash\n",
    },
    Kind { key: "plain", about: "Plain (just git + direnv; add tools to shell.nix)", packages: "", ignore: "", files: &[], run: "",
           just: "# just — this project's commands (`just` lists them)\n\nhello:\n    echo \"add your own commands here\"\n" },
];

/// Folder-safe project name: letters, digits, - and _.
fn clean_name(s: &str) -> String {
    let n: String = s
        .trim()
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '-'
            }
        })
        .collect();
    n.trim_matches('-').to_string()
}

fn find(key: &str) -> Option<&'static Kind> {
    let key = key.to_lowercase();
    let key = match key.as_str() {
        "c" | "cpp" | "cxx" => "c++",
        "py" => "python",
        "rs" => "rust",
        "js" | "ts" | "javascript" | "typescript" => "node",
        "golang" => "go",
        "pio" | "platformio" | "arduino" | "esp32" | "pico" => "board",
        "mpy" | "circuitpython" => "micropython",
        k => k,
    }
    .to_string();
    KINDS.iter().find(|k| k.key == key)
}

fn shell_nix(packages: &str) -> String {
    format!(
        "# The tools for this project. They load when you cd in (direnv), or run: nix-shell\n\
         {{ pkgs ? import <nixpkgs> {{ }} }}:\n\
         pkgs.mkShell {{\n  packages = with pkgs; [ {packages} just watchexec ];\n}}\n"
    )
}

fn create(dir: &Path, kind: &Kind, name: &str) -> std::io::Result<()> {
    fs::create_dir_all(dir)?;
    fs::write(dir.join("shell.nix"), shell_nix(kind.packages))?;
    fs::write(dir.join(".envrc"), "use nix\n")?;
    fs::write(dir.join("justfile"), kind.just.replace("NAME", name))?;
    fs::write(
        dir.join(".gitignore"),
        format!(".direnv/\n{}", kind.ignore.replace("NAME", name)),
    )?;
    let run = if kind.run.is_empty() {
        String::new()
    } else {
        format!("\nRun it:\n\n    {}\n", kind.run.replace("NAME", name))
    };
    fs::write(dir.join("README.md"), format!("# {name}\n{run}"))?;
    for (path, text) in kind.files {
        let p = dir.join(path);
        if let Some(parent) = p.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(p, text.replace("NAME", name))?;
    }
    Ok(())
}

pub fn run(args: &[String]) -> i32 {
    extend_path();
    let kind = match args.first() {
        Some(k) => match find(k) {
            Some(k) => k,
            None => {
                eprintln!(
                    "nix2 new: unknown kind '{k}' — one of: {}",
                    KINDS.iter().map(|k| k.key).collect::<Vec<_>>().join(", ")
                );
                return 2;
            }
        },
        None => {
            println!("New project — what kind?\n");
            for (i, k) in KINDS.iter().enumerate() {
                println!("  {}  {}", i + 1, k.about);
            }
            let Some(a) = ask("\nNumber or name: ") else {
                return 0;
            };
            match a
                .parse::<usize>()
                .ok()
                .and_then(|i| KINDS.get(i.wrapping_sub(1)))
                .or_else(|| find(&a))
            {
                Some(k) => k,
                None if a.is_empty() => return 0,
                None => {
                    eprintln!("Not one of those.");
                    return 2;
                }
            }
        }
    };
    let raw = match args.get(1) {
        Some(n) => n.clone(),
        None => ask("Project name: ").unwrap_or_default(),
    };
    let name = clean_name(&raw);
    if name.is_empty() {
        return 0;
    }
    let base = env::var_os("NIX2_PROJECTS")
        .map(Into::into)
        .unwrap_or_else(|| home().join("projects"));
    let dir = base.join(&name);
    if dir.exists() {
        eprintln!("{} already exists — pick another name.", dir.display());
        return 1;
    }
    if let Err(e) = create(&dir, kind, &name) {
        eprintln!("nix2 new: couldn't create {}: {e}", dir.display());
        return 1;
    }
    let d = dir.to_str().unwrap_or(".");
    ok("git", ["-C", d, "init", "-q"]);
    ok("git", ["-C", d, "add", "-A"]);
    if which("direnv").is_some() {
        let _ = Command::new("direnv").args(["allow", d]).status();
    }

    println!("\nCreated {}", dir.display());
    println!(
        "  cd ~/{}   — the tools load by themselves (first time: a short download)",
        dir.strip_prefix(home()).unwrap_or(&dir).display()
    );
    println!("  just        — lists this project's commands (watch = rerun on every save)");
    if !kind.run.is_empty() {
        println!("  try:        {}", kind.run.replace("NAME", &name));
    }
    println!("  Need another tool? Add it to shell.nix.");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names() {
        assert_eq!(clean_name(" My Cool App! "), "My-Cool-App");
        assert_eq!(clean_name("ok_name-2"), "ok_name-2");
        assert_eq!(clean_name("///"), "");
    }

    #[test]
    fn kinds() {
        assert_eq!(find("cpp").map(|k| k.key), Some("c++"));
        assert_eq!(find("TS").map(|k| k.key), Some("node"));
        assert!(find("cobol").is_none());
    }

    #[test]
    fn scaffold() {
        let dir = env::temp_dir().join(format!("nix2-new-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        create(&dir, find("rust").unwrap(), "demo").unwrap();
        assert!(fs::read_to_string(dir.join("Cargo.toml"))
            .unwrap()
            .contains("name = \"demo\""));
        assert!(fs::read_to_string(dir.join("shell.nix"))
            .unwrap()
            .contains("rust-analyzer"));
        assert_eq!(fs::read_to_string(dir.join(".envrc")).unwrap(), "use nix\n");
        assert!(fs::read_to_string(dir.join("justfile"))
            .unwrap()
            .contains("cargo test"));
        let _ = fs::remove_dir_all(&dir);
    }
}
