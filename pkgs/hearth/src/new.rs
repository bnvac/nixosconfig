//! hearth new [kind] [name] — start a project in ~/projects/NAME with its
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
}

const KINDS: &[Kind] = &[
    Kind {
        key: "rust",
        about: "Rust (cargo, rust-analyzer, clippy)",
        packages: "cargo rustc rust-analyzer clippy rustfmt",
        ignore: "target/\n",
        files: &[
            ("Cargo.toml", "[package]\nname = \"NAME\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n[dependencies]\n"),
            ("src/main.rs", "fn main() {\n    println!(\"Hello from NAME!\");\n}\n"),
        ],
        run: "cargo run",
    },
    Kind {
        key: "python",
        about: "Python (ruff, pyright, pytest)",
        packages: "python3 ruff pyright python3Packages.pytest",
        ignore: "__pycache__/\n.venv/\n*.pyc\n",
        files: &[("main.py", "def main():\n    print(\"Hello from NAME!\")\n\n\nif __name__ == \"__main__\":\n    main()\n")],
        run: "python main.py",
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
    },
    Kind { key: "plain", about: "Plain (just git + direnv; add tools to shell.nix)", packages: "", ignore: "", files: &[], run: "" },
];

/// Folder-safe project name: letters, digits, - and _.
fn clean_name(s: &str) -> String {
    let n: String = s
        .trim()
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '-' })
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
        k => k,
    }
    .to_string();
    KINDS.iter().find(|k| k.key == key)
}

fn shell_nix(packages: &str) -> String {
    format!(
        "# The tools for this project. They load when you cd in (direnv), or run: nix-shell\n\
         {{ pkgs ? import <nixpkgs> {{ }} }}:\n\
         pkgs.mkShell {{\n  packages = with pkgs; [ {packages} ];\n}}\n"
    )
}

fn create(dir: &Path, kind: &Kind, name: &str) -> std::io::Result<()> {
    fs::create_dir_all(dir)?;
    fs::write(dir.join("shell.nix"), shell_nix(kind.packages))?;
    fs::write(dir.join(".envrc"), "use nix\n")?;
    fs::write(dir.join(".gitignore"), format!(".direnv/\n{}", kind.ignore.replace("NAME", name)))?;
    let run = if kind.run.is_empty() { String::new() } else { format!("\nRun it:\n\n    {}\n", kind.run.replace("NAME", name)) };
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
                eprintln!("hearth new: unknown kind '{k}' — one of: {}", KINDS.iter().map(|k| k.key).collect::<Vec<_>>().join(", "));
                return 2;
            }
        },
        None => {
            println!("New project — what kind?\n");
            for (i, k) in KINDS.iter().enumerate() {
                println!("  {}  {}", i + 1, k.about);
            }
            let Some(a) = ask("\nNumber or name: ") else { return 0 };
            match a.parse::<usize>().ok().and_then(|i| KINDS.get(i.wrapping_sub(1))).or_else(|| find(&a)) {
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
    let base = env::var_os("HEARTH_PROJECTS").map(Into::into).unwrap_or_else(|| home().join("projects"));
    let dir = base.join(&name);
    if dir.exists() {
        eprintln!("{} already exists — pick another name.", dir.display());
        return 1;
    }
    if let Err(e) = create(&dir, kind, &name) {
        eprintln!("hearth new: couldn't create {}: {e}", dir.display());
        return 1;
    }
    let d = dir.to_str().unwrap_or(".");
    ok("git", ["-C", d, "init", "-q"]);
    ok("git", ["-C", d, "add", "-A"]);
    if which("direnv").is_some() {
        let _ = Command::new("direnv").args(["allow", d]).status();
    }

    println!("\nCreated {}", dir.display());
    println!("  cd ~/{}   — the tools load by themselves (first time: a short download)", dir.strip_prefix(home()).unwrap_or(&dir).display());
    if !kind.run.is_empty() {
        println!("  {}", kind.run.replace("NAME", &name));
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
        let dir = env::temp_dir().join(format!("hearth-new-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        create(&dir, find("rust").unwrap(), "demo").unwrap();
        assert!(fs::read_to_string(dir.join("Cargo.toml")).unwrap().contains("name = \"demo\""));
        assert!(fs::read_to_string(dir.join("shell.nix")).unwrap().contains("rust-analyzer"));
        assert_eq!(fs::read_to_string(dir.join(".envrc")).unwrap(), "use nix\n");
        let _ = fs::remove_dir_all(&dir);
    }
}
