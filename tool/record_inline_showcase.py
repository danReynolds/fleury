#!/usr/bin/env python3
"""Record the real native setup demo on a POSIX PTY, with pyte answering probes.

Install tool/inline-pty-requirements.txt, compile packages/samples/bin/inline.dart,
then run: python tool/record_inline_showcase.py /path/to/compiled-demo
The shell context is a fixture; every live UI frame comes from the native app.
"""
import argparse
import codecs
import fcntl
import json
import os
from pathlib import Path
import select
import signal
import struct
import subprocess
import sys
import termios
import time

import pyte

ROOT = Path(__file__).resolve().parents[1]


def scene(binary):
    # This process keeps the controlling terminal alive after the demo exits,
    # so we can inspect its modes without silently restoring them ourselves.
    original = termios.tcgetattr(0)
    print("~/projects $ ls\nnotes/    sandbox/\n\n~/projects $ project-setup", flush=True)
    result = subprocess.run([binary], check=False)
    assert result.returncode == 0, result.returncode
    restored = termios.tcgetattr(0)
    # macOS sets PENDIN (pending-input retype status) after returning to cooked
    # mode. Compare the configuration, excluding this kernel-maintained bit.
    for modes in (original, restored):
        modes[3] &= ~getattr(termios, "PENDIN", 0)
    assert restored == original, f"terminal modes changed: {original!r} -> {restored!r}"
    print("~/projects $ ", end="", flush=True)


def record(binary, destination):
    master, slave = os.openpty()
    cols, rows = 84, 30
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    class Screen(pyte.HistoryScreen):
        def write_process_input(self, data):
            os.write(master, data.encode())

    screen = Screen(cols, rows, history=100)
    stream = pyte.Stream(screen)
    decoder = codecs.getincrementaldecoder("utf-8")()
    events = []
    raw = bytearray()
    start = time.monotonic()

    def attach_terminal():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    child = subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve()), "--scene", binary],
        stdin=slave, stdout=slave, stderr=slave, preexec_fn=attach_terminal,
        env={**os.environ, "TERM": "xterm-256color", "FLEURY_KEYBOARD": "legacy",
             "FLEURY_SYNC_OUTPUT": "0"},
    )

    def text():
        return "\n".join(screen.display)

    def pump(timeout=0.05):
        if select.select([master], [], [], timeout)[0]:
            chunk = os.read(master, 65536)
            raw.extend(chunk)
            decoded = decoder.decode(chunk)
            if decoded:
                events.append([round(time.monotonic() - start, 4), "o", decoded])
                stream.feed(decoded)

    def wait_for(predicate, label):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            pump()
            if predicate():
                return
            if child.poll() is not None:
                break
        raise AssertionError(f"{label}\n{text()}")

    def pause(seconds):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            pump()

    def click(label):
        row = next(i for i, line in enumerate(screen.display) if label in line)
        col = screen.display[row].index(label) + 1
        os.write(master, f"\x1b[<0;{col+1};{row+1}M\x1b[<0;{col+1};{row+1}m".encode())

    try:
        wait_for(lambda: "Include tests" in text(), "initial form")
        assert "notes/    sandbox/" in text(), "lost the previous shell output"
        pause(1.2)
        os.write(master, b"\x01")  # Home, then delete the default name.
        os.write(master, b"\x0b")  # Ctrl+K: delete to end of line.
        for char in b"orbit_tools":
            os.write(master, bytes([char]))
            pause(0.11)
        pause(0.6)
        click("Library")
        wait_for(lambda: "other projects can import" in text(), "template change")
        pause(1.4)
        click("Review")
        wait_for(lambda: "dev_dependencies:" in text() and "Generate config" in text(), "review page")
        assert "lib/orbit_tools.dart" in text(), text()
        assert "dev_dependencies:" in text(), text()
        assert "notes/    sandbox/" in text(), "region growth lost shell context"
        pause(3.2)
        os.write(master, b"\x1b")  # Escape goes back without losing the form.
        wait_for(lambda: "Include tests" in text() and "Review" in text(), "back to the form")
        assert "orbit_tools" in text(), text()
        pause(1.2)
        click("Review")
        wait_for(lambda: "dev_dependencies:" in text() and "Generate config" in text(), "second review")
        pause(1.0)
        os.write(master, b"\r")  # Review autofocus makes Enter confirm.
        wait_for(lambda: child.poll() is not None, "clean command exit")
        pause(0.2)
        assert child.returncode == 0, text()
        assert "Configuration ready for orbit_tools" in text(), text()
        assert "Your project, at a glance." not in text(), "live form survived completion"
        assert "notes/    sandbox/" in text(), "completion lost earlier output"
        assert b"1049" not in raw and b"\x1b[2J" not in raw, "used fullscreen rendering"
        # A final no-op output event holds the result long enough to read it.
        pause(1.8)
        events.append([round(time.monotonic() - start, 4), "o", ""])
        header = {"version": 2, "width": cols, "height": rows,
                  "title": "Fleury inline project setup",
                  "env": {"TERM": "xterm-256color", "SHELL": "fixture"}}
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text("\n".join(json.dumps(item) for item in [header, *events]) + "\n")
        print(f"Recorded {events[-1][0]:.1f}s of native PTY output → {destination}")
        print("PASS: shared form, offset clicks, review growth, Back, keyboard finish, terminal restoration")
    finally:
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGKILL)
            child.kill()
        child.wait(timeout=5)
        os.close(slave)
        os.close(master)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--scene":
        scene(sys.argv[2])
    else:
        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument("binary", help="Compiled inline demo executable")
        parser.add_argument("--output", type=Path,
                            default=ROOT / "website/public/recordings/inline-setup.cast")
        args = parser.parse_args()
        record(str(Path(args.binary).resolve()), args.output)
