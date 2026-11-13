//! nix2 displays — screens: mirror, extend, pick one, resolution, refresh
//! rate, rotation, which one is the main screen. (Super+Alt+p, Super+F3, or
//! menu → System → Displays.)
//!
//! Like a normal display settings window, a change asks "Keep this layout?"
//! and goes back by itself after 15 seconds — so a mode the screen can't show
//! never leaves you stuck. A layout you keep is remembered for exactly that
//! set of screens (autorandr) and comes back whenever they're plugged in.
//!
//!   nix2 displays                 the menu
//!   nix2 displays status          what's connected and how it's set
//!   nix2 displays mirror          same picture on every screen
//!   nix2 displays extend [right|left|above|below]   second screen next to the main one
//!   nix2 displays only NAME       just that screen
//!   nix2 displays auto            every screen at its best mode, side by side
//!   … --dry-run                   print the xrandr command, change nothing

use crate::util::{dmenu, extend_path, load_x_env, notify, ok, output, which, Pick};
use std::io::Write;
use std::process::{Command, Stdio};
use std::thread::sleep;
use std::time::{Duration, Instant};

#[derive(Clone, Debug, PartialEq)]
pub struct Mode {
    pub w: u32,
    pub h: u32,
    pub rates: Vec<String>,
    pub current: Option<String>,
    pub preferred: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Output {
    pub name: String,
    pub connected: bool,
    pub primary: bool,
    /// (width, height, x, y) as shown on screen, when the output is on.
    pub geom: Option<(u32, u32, i32, i32)>,
    pub rotation: String,
    pub modes: Vec<Mode>,
}

/// One screen in a layout.
#[derive(Clone, Debug, PartialEq)]
pub struct Place {
    pub name: String,
    pub mode: (u32, u32),
    pub rate: Option<String>,
    pub pos: (i32, i32),
    pub rotate: String,
    pub primary: bool,
    /// Mirror onto a screen with another resolution: show an area this big.
    pub scale_from: Option<(u32, u32)>,
}

impl Place {
    /// The space it takes up on the desktop.
    pub fn size(&self) -> (u32, u32) {
        let (w, h) = self.scale_from.unwrap_or(self.mode);
        if self.rotate == "left" || self.rotate == "right" {
            (h, w)
        } else {
            (w, h)
        }
    }
}

fn geometry(tok: &str) -> Option<(u32, u32, i32, i32)> {
    let (size, rest) = tok.split_once('+')?;
    let (w, h) = size.split_once('x')?;
    let (x, y) = rest.split_once('+')?;
    Some((
        w.parse().ok()?,
        h.parse().ok()?,
        x.parse().ok()?,
        y.parse().ok()?,
    ))
}

/// `xrandr --query` → the outputs and their modes.
pub fn parse(text: &str) -> Vec<Output> {
    let mut outs: Vec<Output> = Vec::new();
    for line in text.lines() {
        if line.starts_with("Screen ") {
            continue;
        }
        if !line.starts_with(char::is_whitespace) {
            let mut t = line.split_whitespace();
            let (Some(name), Some(state)) = (t.next(), t.next()) else {
                continue;
            };
            let mut o = Output {
                name: name.to_string(),
                connected: state == "connected",
                primary: false,
                geom: None,
                rotation: "normal".into(),
                modes: Vec::new(),
            };
            for tok in t {
                if tok.starts_with('(') {
                    break;
                }
                match tok {
                    "primary" => o.primary = true,
                    "left" | "right" | "inverted" => o.rotation = tok.into(),
                    _ => {
                        if let Some(g) = geometry(tok) {
                            o.geom = Some(g);
                        }
                    }
                }
            }
            outs.push(o);
        } else if let Some(o) = outs.last_mut() {
            let mut t = line.split_whitespace();
            let Some((w, h)) = t.next().and_then(|m| {
                let (w, h) = m.split_once('x')?;
                Some((w.parse::<u32>().ok()?, h.parse::<u32>().ok()?)) // "1920x1080i" (interlaced) is skipped
            }) else {
                continue;
            };
            let mut m = Mode {
                w,
                h,
                rates: Vec::new(),
                current: None,
                preferred: false,
            };
            for r in t {
                // "60.00*+" (current, preferred) — or "60.00 +": a lone "+"
                // marks the mode as preferred when it isn't the current one.
                if r == "+" {
                    m.preferred = true;
                    continue;
                }
                let rate = r.trim_end_matches(['*', '+']).to_string();
                if rate.parse::<f32>().is_err() {
                    continue;
                }
                if r.contains('*') {
                    m.current = Some(rate.clone());
                }
                if r.contains('+') {
                    m.preferred = true;
                }
                m.rates.push(rate);
            }
            if !m.rates.is_empty() && !o.modes.iter().any(|x| x.w == w && x.h == h) {
                o.modes.push(m);
            }
        }
    }
    outs
}

fn connected(outs: &[Output]) -> Vec<&Output> {
    outs.iter()
        .filter(|o| o.connected && !o.modes.is_empty())
        .collect()
}

/// The mode a screen is best at: the one it asks for, else its biggest.
fn best(o: &Output) -> (u32, u32) {
    o.modes
        .iter()
        .find(|m| m.preferred)
        .or_else(|| o.modes.iter().max_by_key(|m| m.w * m.h))
        .map(|m| (m.w, m.h))
        .unwrap_or((1024, 768))
}

/// The mode it's in now (rotation undone), else its best.
fn mode_now(o: &Output) -> (u32, u32) {
    o.modes
        .iter()
        .find(|m| m.current.is_some())
        .map(|m| (m.w, m.h))
        .unwrap_or_else(|| best(o))
}

fn rate_now(o: &Output) -> Option<String> {
    o.modes.iter().find_map(|m| m.current.clone())
}

fn place(o: &Output, mode: (u32, u32), pos: (i32, i32), primary: bool) -> Place {
    Place {
        name: o.name.clone(),
        mode,
        rate: None,
        pos,
        rotate: "normal".into(),
        primary,
        scale_from: None,
    }
}

/// What's on screen right now, as a layout (to go back to).
pub fn current(outs: &[Output]) -> Vec<Place> {
    connected(outs)
        .into_iter()
        .filter_map(|o| {
            let (_, _, x, y) = o.geom?;
            let mut p = place(o, mode_now(o), (x, y), o.primary);
            p.rate = rate_now(o);
            p.rotate = o.rotation.clone();
            Some(p)
        })
        .collect()
}

/// The main screen: the one marked primary, else the built-in panel, else the first.
fn main_screen<'a>(outs: &[&'a Output]) -> Option<&'a Output> {
    outs.iter()
        .find(|o| o.primary && o.geom.is_some())
        .or_else(|| outs.iter().find(|o| is_builtin(&o.name)))
        .or_else(|| outs.first())
        .copied()
}

fn is_builtin(name: &str) -> bool {
    ["eDP", "LVDS", "DSI"].iter().any(|p| name.starts_with(p))
}

/// "Laptop screen" for the built-in panel, the connector name otherwise.
pub fn label(o: &Output) -> String {
    if is_builtin(&o.name) {
        format!("Laptop screen ({})", o.name)
    } else {
        o.name.clone()
    }
}

/// Same picture everywhere: the biggest mode every screen has; when they
/// share none, each screen at its best, scaled to show the main screen's area.
pub fn mirror(outs: &[Output]) -> Vec<Place> {
    let on = connected(outs);
    let Some(main) = main_screen(&on) else {
        return Vec::new();
    };
    let common = main
        .modes
        .iter()
        .filter(|m| {
            on.iter()
                .all(|o| o.modes.iter().any(|x| x.w == m.w && x.h == m.h))
        })
        .max_by_key(|m| m.w * m.h)
        .map(|m| (m.w, m.h));
    on.iter()
        .map(|o| match common {
            Some(mode) => place(o, mode, (0, 0), o.name == main.name),
            None => {
                let mut p = place(o, best(o), (0, 0), o.name == main.name);
                if o.name != main.name {
                    p.scale_from = Some(best(main));
                }
                p
            }
        })
        .collect()
}

/// Every screen at its best mode in a row, the main one first.
pub fn auto(outs: &[Output]) -> Vec<Place> {
    let on = connected(outs);
    let Some(main) = main_screen(&on) else {
        return Vec::new();
    };
    let mut row: Vec<&Output> = vec![main];
    row.extend(on.iter().filter(|o| o.name != main.name));
    let mut x = 0;
    row.iter()
        .map(|o| {
            let p = place(o, best(o), (x, 0), o.name == main.name);
            x += p.size().0 as i32;
            p
        })
        .collect()
}

/// The main screen plus one more, on the given side of it.
pub fn extend(outs: &[Output], side: &str, second: Option<&str>) -> Vec<Place> {
    let on = connected(outs);
    let Some(main) = main_screen(&on) else {
        return Vec::new();
    };
    let other = second
        .and_then(|n| on.iter().find(|o| o.name == n))
        .or_else(|| on.iter().find(|o| o.name != main.name));
    let Some(other) = other else {
        return current(outs); // nothing to extend onto: leave it as it is
    };
    // The main screen stays at the mode you have it in; the one being added
    // comes up at its best.
    let (mw, mh) = if main.geom.is_some() {
        mode_now(main)
    } else {
        best(main)
    };
    let (ow, oh) = best(other);
    let (mpos, opos) = match side {
        "left" => ((ow as i32, 0), (0, 0)),
        "above" => ((0, oh as i32), (0, 0)),
        "below" => ((0, 0), (0, mh as i32)),
        _ => ((0, 0), (mw as i32, 0)),
    };
    vec![
        place(main, (mw, mh), mpos, true),
        place(other, (ow, oh), opos, false),
    ]
}

pub fn only(outs: &[Output], name: &str) -> Vec<Place> {
    connected(outs)
        .into_iter()
        .filter(|o| o.name == name)
        .map(|o| place(o, best(o), (0, 0), true))
        .collect()
}

/// After a screen changed size: close gaps and overlaps, keeping the order.
/// Only for a plain row or column; anything fancier is left as it is.
pub fn reflow(layout: &mut [Place]) {
    if layout.len() < 2 || layout.iter().all(|p| p.pos == layout[0].pos) {
        return; // one screen, or mirrored
    }
    if layout.iter().all(|p| p.pos.1 == layout[0].pos.1) {
        layout.sort_by_key(|p| p.pos.0);
        let mut x = 0;
        for p in layout.iter_mut() {
            p.pos = (x, 0);
            x += p.size().0 as i32;
        }
    } else if layout.iter().all(|p| p.pos.0 == layout[0].pos.0) {
        layout.sort_by_key(|p| p.pos.1);
        let mut y = 0;
        for p in layout.iter_mut() {
            p.pos = (0, y);
            y += p.size().1 as i32;
        }
    }
}

/// The xrandr arguments that set this layout (screens not in it go off).
pub fn to_args(layout: &[Place], outs: &[Output]) -> Vec<String> {
    let mut a: Vec<String> = Vec::new();
    for p in layout {
        a.extend(["--output".into(), p.name.clone()]);
        a.extend(["--mode".into(), format!("{}x{}", p.mode.0, p.mode.1)]);
        if let Some(r) = &p.rate {
            a.extend(["--rate".into(), r.clone()]);
        }
        a.extend(["--pos".into(), format!("{}x{}", p.pos.0, p.pos.1)]);
        a.extend(["--rotate".into(), p.rotate.clone()]);
        match p.scale_from {
            Some((w, h)) => a.extend(["--scale-from".into(), format!("{w}x{h}")]),
            None => a.extend(["--scale".into(), "1x1".into()]),
        }
        if p.primary {
            a.push("--primary".into());
        }
    }
    for o in outs {
        if !layout.iter().any(|p| p.name == o.name) && (o.connected || o.geom.is_some()) {
            a.extend(["--output".into(), o.name.clone(), "--off".into()]);
        }
    }
    a
}

fn query() -> Vec<Output> {
    output("xrandr", ["--query"])
        .map(|s| parse(&s))
        .unwrap_or_default()
}

fn describe(outs: &[Output]) -> String {
    let mut s = String::new();
    for o in connected(outs) {
        let state = match o.geom {
            Some((w, h, x, y)) => {
                let rate = rate_now(o)
                    .map(|r| format!(" at {r} Hz"))
                    .unwrap_or_default();
                let rot = if o.rotation == "normal" {
                    String::new()
                } else {
                    format!(", turned {}", o.rotation)
                };
                let main = if o.primary { ", main screen" } else { "" };
                format!("{w}x{h}{rate}, placed at {x},{y}{rot}{main}")
            }
            None => "plugged in, off".into(),
        };
        s.push_str(&format!("  {:<28} {}\n", label(o), state));
    }
    s
}

/// "Keep this layout?" with a countdown. true = keep.
fn confirm(secs: u64) -> bool {
    let child = Command::new("dmenu")
        .args([
            "-i",
            "-l",
            "2",
            "-p",
            &format!("Keep this layout? (goes back in {secs} s)"),
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn();
    let Ok(mut child) = child else {
        return true; // no dmenu to ask with: don't undo what was asked for
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(b"Keep it\nGo back");
    }
    let end = Instant::now() + Duration::from_secs(secs);
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if Instant::now() < end => sleep(Duration::from_millis(100)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return false;
            }
        }
    }
    child
        .wait_with_output()
        .map(|o| o.status.success() && String::from_utf8_lossy(&o.stdout).trim() == "Keep it")
        .unwrap_or(false)
}

/// Run xrandr with a layout's arguments. "--scale 1x1" (undo an earlier
/// scaled mirror) is refused by drivers that can't scale at all — there's
/// nothing to undo on those, so try again without it.
fn xrandr(args: &[String]) -> bool {
    if ok("xrandr", args) {
        return true;
    }
    let plain = without_unscale(args);
    plain.len() != args.len() && ok("xrandr", &plain)
}

pub fn without_unscale(args: &[String]) -> Vec<String> {
    let mut out = Vec::with_capacity(args.len());
    let mut i = 0;
    while i < args.len() {
        if args[i] == "--scale" && args.get(i + 1).is_some_and(|v| v == "1x1") {
            i += 2;
        } else {
            out.push(args[i].clone());
            i += 1;
        }
    }
    out
}

/// Things that depend on the screen layout: the wallpaper, and the saved
/// layout for this set of screens.
fn settle(save: bool) {
    if save && which("autorandr").is_some() {
        // One profile per set of screens: named after what's plugged in.
        let print = output("autorandr", ["--fingerprint"]).unwrap_or_default();
        let hash = print.bytes().fold(0xcbf2_9ce4_8422_2325_u64, |h, b| {
            (h ^ u64::from(b)).wrapping_mul(0x0100_0000_01b3)
        });
        ok(
            "autorandr",
            [
                "--save",
                &format!("nix2-{:08x}", hash & 0xffff_ffff),
                "--force",
            ],
        );
    }
    if which("displays-refresh").is_some() {
        ok("displays-refresh", [] as [&str; 0]);
    }
}

/// Apply a layout, ask to keep it, go back if not. Returns the exit code.
fn apply(layout: Vec<Place>, outs: &[Output], dry: bool, ask: bool) -> i32 {
    if layout.is_empty() {
        eprintln!("displays: no screen to show that on");
        return 1;
    }
    let args = to_args(&layout, outs);
    if dry {
        println!("xrandr {}", args.join(" "));
        return 0;
    }
    let before = to_args(&current(outs), outs);
    if args == before {
        return 0;
    }
    if !xrandr(&args) {
        xrandr(&before);
        notify(
            "Displays",
            "That layout didn't work",
            "The screens are back as they were.",
            true,
        );
        return 1;
    }
    if ask && !confirm(15) {
        xrandr(&before);
        settle(false);
        return 0;
    }
    settle(true);
    0
}

/// One of the listed items (something else typed in counts as cancel).
fn pick(prompt: &str, items: &[String]) -> Option<String> {
    match dmenu(prompt, items, false) {
        Pick::Chose(s) if items.contains(&s) => Some(s),
        _ => None,
    }
}

fn menu(outs: &[Output]) -> Option<Vec<Place>> {
    let on = connected(outs);
    let main = main_screen(&on)?;
    let mut items: Vec<String> = Vec::new();
    let others: Vec<&&Output> = on.iter().filter(|o| o.name != main.name).collect();
    if !others.is_empty() {
        items.push("Mirror: the same picture on every screen".into());
        for o in &others {
            for side in ["right", "left", "above", "below"] {
                items.push(format!(
                    "Extend: {} {} the {}",
                    label(o),
                    side_words(side),
                    label(main)
                ));
            }
        }
        for o in &on {
            items.push(format!("Only {}", label(o)));
        }
        if on.len() > 2 {
            items.push("All screens side by side".into());
        }
        items.push("Main screen (where the bar and new windows go)…".into());
    }
    items.push("Resolution…".into());
    items.push("Refresh rate…".into());
    items.push("Rotate…".into());
    if which("arandr").is_some() {
        items.push("Arrange by dragging (opens ARandR)".into());
    }

    let choice = pick("Displays:", &items)?;
    if choice.starts_with("Mirror") {
        return Some(mirror(outs));
    }
    if choice == "All screens side by side" {
        return Some(auto(outs));
    }
    if choice.starts_with("Arrange") {
        let _ = Command::new("arandr").spawn();
        return None;
    }
    if let Some(rest) = choice.strip_prefix("Only ") {
        let o = on.iter().find(|o| label(o) == rest)?;
        return Some(only(outs, &o.name));
    }
    if choice.starts_with("Extend: ") {
        for o in &others {
            for side in ["right", "left", "above", "below"] {
                if choice
                    == format!(
                        "Extend: {} {} the {}",
                        label(o),
                        side_words(side),
                        label(main)
                    )
                {
                    return Some(extend(outs, side, Some(&o.name)));
                }
            }
        }
        return None;
    }

    // The rest change one screen within the layout that's showing now.
    let mut layout = current(outs);
    if layout.is_empty() {
        layout = auto(outs);
    }
    let target = if layout.len() == 1 {
        layout[0].name.clone()
    } else {
        let names: Vec<String> = layout
            .iter()
            .filter_map(|p| on.iter().find(|o| o.name == p.name).map(|o| label(o)))
            .collect();
        let l = pick("Which screen?", &names)?;
        on.iter().find(|o| label(o) == l)?.name.clone()
    };
    let out = on.iter().find(|o| o.name == target)?;
    let idx = layout.iter().position(|p| p.name == target)?;

    if choice.starts_with("Main screen") {
        for p in layout.iter_mut() {
            p.primary = p.name == target;
        }
    } else if choice.starts_with("Resolution") {
        let modes: Vec<String> = out
            .modes
            .iter()
            .map(|m| {
                format!(
                    "{}x{}{}",
                    m.w,
                    m.h,
                    if m.preferred { "  (recommended)" } else { "" }
                )
            })
            .collect();
        let m = pick(&format!("Resolution for {}:", label(out)), &modes)?;
        let (w, h) = m.split_whitespace().next()?.split_once('x')?;
        layout[idx].mode = (w.parse().ok()?, h.parse().ok()?);
        layout[idx].rate = None;
        layout[idx].scale_from = None;
        reflow(&mut layout);
    } else if choice.starts_with("Refresh") {
        let (w, h) = layout[idx].mode;
        let mode = out.modes.iter().find(|m| m.w == w && m.h == h)?;
        let rates: Vec<String> = mode.rates.iter().map(|r| format!("{r} Hz")).collect();
        let r = pick(
            &format!("Refresh rate for {} at {w}x{h}:", label(out)),
            &rates,
        )?;
        layout[idx].rate = Some(r.trim_end_matches(" Hz").to_string());
    } else if choice.starts_with("Rotate") {
        let turns = [
            ("Normal", "normal"),
            ("Turned left (portrait)", "left"),
            ("Turned right (portrait)", "right"),
            ("Upside down", "inverted"),
        ];
        let names: Vec<String> = turns.iter().map(|t| t.0.to_string()).collect();
        let r = pick(&format!("Rotate {}:", label(out)), &names)?;
        layout[idx].rotate = turns.iter().find(|t| t.0 == r)?.1.to_string();
        reflow(&mut layout);
    } else {
        return None;
    }
    Some(layout)
}

fn side_words(side: &str) -> &'static str {
    match side {
        "left" => "to the left of",
        "above" => "above",
        "below" => "below",
        _ => "to the right of",
    }
}

pub fn run(args: &[String]) -> i32 {
    extend_path();
    load_x_env();
    let dry = args.iter().any(|a| a == "--dry-run");
    let args: Vec<&str> = args
        .iter()
        .map(String::as_str)
        .filter(|a| *a != "--dry-run")
        .collect();
    let outs = query();
    if connected(&outs).is_empty() {
        eprintln!("displays: couldn't find any screen (is this a desktop session?)");
        return 1;
    }
    match args.first().copied() {
        None => match menu(&outs) {
            Some(layout) => apply(layout, &outs, dry, true),
            None => 0,
        },
        Some("status") => {
            print!("{}", describe(&outs));
            0
        }
        Some("mirror") => apply(mirror(&outs), &outs, dry, false),
        Some("auto") => apply(auto(&outs), &outs, dry, false),
        Some("extend") => apply(
            extend(&outs, args.get(1).copied().unwrap_or("right"), None),
            &outs,
            dry,
            false,
        ),
        Some("only") => match args.get(1) {
            Some(name) => apply(only(&outs, name), &outs, dry, false),
            None => {
                eprintln!("usage: nix2 displays only NAME   (names: nix2 displays status)");
                2
            }
        },
        Some(_) => {
            eprintln!("usage: nix2 displays [status|mirror|extend [right|left|above|below]|only NAME|auto] [--dry-run]");
            2
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const LAPTOP_HDMI: &str = "\
Screen 0: minimum 320 x 200, current 3840 x 1080, maximum 16384 x 16384
eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 344mm x 194mm
   1920x1080     60.02*+  59.97    48.00
   1680x1050     59.95
   1280x720      60.00    59.99
HDMI-1 connected 2560x1440+1920+0 (normal left inverted right x axis y axis) 597mm x 336mm
   2560x1440     59.95*+ 143.91
   1920x1080     60.00    50.00    59.94
   1920x1080i    60.00    50.00
   1280x720      60.00    50.00
DP-1 disconnected (normal left inverted right x axis y axis)
";

    #[test]
    fn parses_xrandr() {
        let o = parse(LAPTOP_HDMI);
        assert_eq!(o.len(), 3);
        assert!(o[0].primary && o[0].connected);
        assert_eq!(o[0].geom, Some((1920, 1080, 0, 0)));
        assert_eq!(o[0].modes.len(), 3);
        assert_eq!(o[0].modes[0].current.as_deref(), Some("60.02"));
        assert!(o[0].modes[0].preferred);
        assert_eq!(o[1].geom, Some((2560, 1440, 1920, 0)));
        assert_eq!(o[1].modes.len(), 3); // the interlaced line doesn't add a mode
        assert_eq!(o[1].modes[0].rates, vec!["59.95", "143.91"]);
        assert!(!o[2].connected);
        assert_eq!(label(&o[0]), "Laptop screen (eDP-1)");
    }

    #[test]
    fn parses_rotated_and_off() {
        let o = parse(
            "DP-2 connected 1080x1920+0+0 left (normal left inverted right x axis y axis) 300mm x 500mm\n   1920x1080     60.00*+\nHDMI-2 connected (normal left inverted right x axis y axis)\n   1280x720      60.00 +\n",
        );
        assert_eq!(o[0].rotation, "left");
        assert_eq!(o[0].geom, Some((1080, 1920, 0, 0)));
        let now = current(&o);
        assert_eq!(now.len(), 1); // the off screen isn't part of the current layout
        assert_eq!(now[0].mode, (1920, 1080));
        assert_eq!(now[0].size(), (1080, 1920));
        assert_eq!(o[1].geom, None);
        assert!(o[1].modes[0].preferred && o[1].modes[0].current.is_none());
    }

    #[test]
    fn mirror_uses_the_biggest_shared_mode() {
        let o = parse(LAPTOP_HDMI);
        let m = mirror(&o);
        assert_eq!(m.len(), 2);
        assert!(m.iter().all(|p| p.mode == (1920, 1080) && p.pos == (0, 0)));
        assert_eq!(
            to_args(&m, &o).join(" "),
            "--output eDP-1 --mode 1920x1080 --pos 0x0 --rotate normal --scale 1x1 --primary \
             --output HDMI-1 --mode 1920x1080 --pos 0x0 --rotate normal --scale 1x1"
        );
    }

    #[test]
    fn mirror_without_a_shared_mode_scales() {
        let o = parse(
            "eDP-1 connected primary 1366x768+0+0 (normal) 300mm x 200mm\n   1366x768      60.00*+\nHDMI-1 connected (normal)\n   3840x2160     60.00 +\n",
        );
        let m = mirror(&o);
        assert_eq!(m[1].mode, (3840, 2160));
        assert_eq!(m[1].scale_from, Some((1366, 768)));
        assert!(to_args(&m, &o).join(" ").contains("--scale-from 1366x768"));
    }

    #[test]
    fn extend_places_the_second_screen() {
        let o = parse(LAPTOP_HDMI);
        let r = extend(&o, "right", None);
        assert_eq!((r[0].pos, r[1].pos), ((0, 0), (1920, 0)));
        let l = extend(&o, "left", Some("HDMI-1"));
        assert_eq!((l[0].pos, l[1].pos), ((2560, 0), (0, 0)));
        let a = extend(&o, "above", None);
        assert_eq!((a[0].pos, a[1].pos), ((0, 1440), (0, 0)));
        assert!(r[0].primary && !r[1].primary);
    }

    #[test]
    fn only_turns_the_others_off() {
        let o = parse(LAPTOP_HDMI);
        let args = to_args(&only(&o, "HDMI-1"), &o).join(" ");
        assert!(args.starts_with("--output HDMI-1 --mode 2560x1440 --pos 0x0"));
        assert!(args.ends_with("--output eDP-1 --off"));
        assert!(!args.contains("DP-1 --off --output")); // a port with nothing in it is left alone
    }

    #[test]
    fn reflow_closes_gaps_after_a_resize() {
        let o = parse(LAPTOP_HDMI);
        let mut l = current(&o);
        l[0].mode = (1280, 720); // laptop panel made smaller
        reflow(&mut l);
        assert_eq!(l[1].pos, (1280, 0));
        l[0].rotate = "left".into(); // and turned on its side: 720 wide
        reflow(&mut l);
        assert_eq!(l[1].pos, (720, 0));
    }

    #[test]
    fn unscale_can_be_dropped() {
        let o = parse(LAPTOP_HDMI);
        let args = to_args(&mirror(&o), &o);
        let plain = without_unscale(&args).join(" ");
        assert!(!plain.contains("--scale"));
        assert!(plain.contains("--output HDMI-1 --mode 1920x1080 --pos 0x0 --rotate normal"));
    }

    #[test]
    fn current_layout_round_trips() {
        let o = parse(LAPTOP_HDMI);
        assert_eq!(
            to_args(&current(&o), &o).join(" "),
            "--output eDP-1 --mode 1920x1080 --rate 60.02 --pos 0x0 --rotate normal --scale 1x1 --primary \
             --output HDMI-1 --mode 2560x1440 --rate 59.95 --pos 1920x0 --rotate normal --scale 1x1"
        );
    }
}
