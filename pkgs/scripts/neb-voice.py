"""neb-voice — talk to Neb without opening anything (Super+Alt+n).

One small notification in the corner that updates in place:
  🎙 Listening…  →  💭 Thinking…  →  Neb: <the answer>   (and he says it out loud)
Press the key again while it's listening to stop and send right away.

Uses the same record / speech-to-text / text-to-speech commands as Neb's own
settings (~/.local/share/neb/settings.json), and sends the turn to the Neb
server, so an open Neb terminal shows the exchange too.
"""

import fcntl
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

NEB = "http://127.0.0.1:7000"
HOME = Path(os.environ.get("NEB_HOME") or Path.home() / ".local/share/neb")
PIDFILE = HOME / "voice.rec.pid"


def settings() -> dict:
    try:
        return json.loads((HOME / "settings.json").read_text()).get("voice", {})
    except (OSError, ValueError):
        return {}


def expand(argv: list, **subs: str) -> list:
    out = []
    for a in argv:
        for k, v in subs.items():
            a = a.replace("{" + k + "}", v)
        out.append(os.path.expanduser(a))
    return out


class Note:
    """One notification, replaced in place each time it's updated."""

    def __init__(self) -> None:
        self.id = ""

    def show(self, body: str, icon: str = "audio-input-microphone", ms: int = 0) -> None:
        argv = ["notify-send", "-a", "Neb", "-i", icon, "-p", "-t", str(ms)]
        if self.id:
            argv += ["-r", self.id]
        try:
            out = subprocess.run(argv + ["Neb", body], capture_output=True, text=True, timeout=5)
            self.id = out.stdout.strip() or self.id
        except (OSError, subprocess.SubprocessError):
            print(f"neb: {body}", file=sys.stderr)


def post(path: str, body: dict, timeout: float) -> dict:
    req = urllib.request.Request(NEB + path, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read() or b"{}")


def state(s: str) -> None:            # mirrors the voice state into Neb's terminal/dashboard
    try:
        post("/api/notify", {"state": s}, 3)
    except (OSError, ValueError):
        pass


def stop_listening() -> int:
    """Second press: end the recording now, so the turn goes off immediately."""
    try:
        os.kill(int(PIDFILE.read_text()), signal.SIGINT)
    except (OSError, ValueError):
        pass
    return 0


def main() -> int:
    HOME.mkdir(parents=True, exist_ok=True)
    lock = open(HOME / "voice.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return stop_listening()

    v, note = settings(), Note()
    if not all(k in v for k in ("record", "stt", "tts", "play")):
        note.show("Voice isn't set up — the assistant module seeds it on first start.", "dialog-warning", 6000)
        return 1

    with tempfile.TemporaryDirectory(prefix="neb-") as d:
        wav = Path(d) / "heard.wav"
        note.show("🎙  Listening…")
        state("listening")
        try:
            rec = subprocess.Popen(expand(v["record"], wav=str(wav)), stdin=subprocess.DEVNULL,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            PIDFILE.write_text(str(rec.pid))
            rec.wait()
        finally:
            PIDFILE.unlink(missing_ok=True)
        note.show("💭  Thinking…", "dialog-information")
        state("transcribing")
        try:
            heard = subprocess.run(expand(v["stt"], wav=str(wav)), capture_output=True, text=True,
                                   stdin=subprocess.DEVNULL, timeout=120).stdout
        except (OSError, subprocess.SubprocessError) as e:
            note.show(f"Couldn't hear you: {e}", "dialog-warning", 5000)
            state("idle")
            return 1

    text = re.sub(r"\s+", " ", re.sub(r"\[[^\]]*\]|\([^)]*\)", " ", heard)).strip()
    if not text:
        note.show("Didn't catch that.", "audio-input-microphone-muted", 2500)
        state("idle")
        return 0

    try:
        r = post("/ask", {"text": text, "origin": "voice"}, 300)
    except (OSError, ValueError) as e:
        note.show(f"Neb isn't answering ({e}). Is the assistant running?", "dialog-warning", 6000)
        state("idle")
        return 1
    reply = r.get("reply") or r.get("error") or "…"
    extra = "\n\n(say yes or no — press the key again)" if r.get("pending") else ""
    note.show(f"You: {text}\n\n{reply}{extra}", "dialog-information", 15000)

    state("speaking")
    with tempfile.TemporaryDirectory(prefix="neb-") as d:
        out = str(Path(d) / "reply.wav")
        try:
            subprocess.run(expand(v["tts"], out=out), input=reply, text=True, check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
            subprocess.run(expand(v["play"], out=out), stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)
        except (OSError, subprocess.SubprocessError):
            pass            # the answer is already on screen
    state("idle")
    return 0


if __name__ == "__main__":
    sys.exit(main())
