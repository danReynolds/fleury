#!/usr/bin/env python3
"""Record the real native setup demo on a POSIX PTY, with pyte answering probes.

Install tool/inline-pty-requirements.txt, compile packages/samples/bin/inline.dart,
then run: python tool/record_inline_showcase.py /path/to/compiled-demo
The shell context is a fixture; every live UI frame comes from the native app.
"""
import argparse
import codecs
import copy
import fcntl
import json
import os
from pathlib import Path
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time

import pyte

ROOT = Path(__file__).resolve().parents[1]


def scene(binary, handoff=False, full_screen=False, repeat=False):
    # This process keeps the controlling terminal alive after the demo exits,
    # so we can inspect its modes without silently restoring them ourselves.
    original = termios.tcgetattr(0)
    options = [*(['--handoff'] if handoff else []), *(['--full-screen'] if full_screen else []),
               *(['--repeat'] if repeat else [])]
    print("~/projects $ ls\nnotes/    sandbox/\n\n~/projects $ project-setup"
          + ''.join(' ' + option for option in options), flush=True)
    result = subprocess.run([binary, *options], check=False)
    assert result.returncode == 0, result.returncode
    restored = termios.tcgetattr(0)
    # macOS sets PENDIN (pending-input retype status) after returning to cooked
    # mode. Compare the configuration, excluding this kernel-maintained bit.
    for modes in (original, restored):
        modes[3] &= ~getattr(termios, "PENDIN", 0)
    assert restored == original, f"terminal modes changed: {original!r} -> {restored!r}"
    print("~/projects $ ", end="", flush=True)


def record(binary, destination, handoff=False, full_screen=False, repeat=False):
    master, slave = os.openpty()
    cols, rows = 84, 30
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    class Screen(pyte.HistoryScreen):
        # pyte does not implement the alternate buffer used by the real less
        # child. Preserve it here so CPR and restoration checks use its state.
        main_screen = None

        def set_mode(self, *modes, **kwargs):
            if kwargs.get('private') and 1049 in modes:
                self.main_screen = copy.deepcopy((self.buffer, self.cursor, self.history))
                self.buffer.clear()
                self.cursor_position()
            super().set_mode(*modes, **kwargs)

        def reset_mode(self, *modes, **kwargs):
            super().reset_mode(*modes, **kwargs)
            if kwargs.get('private') and 1049 in modes and self.main_screen is not None:
                self.buffer, self.cursor, self.history = self.main_screen
                self.main_screen = None
                self.dirty.update(range(self.lines))

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
        [sys.executable, str(Path(__file__).resolve()), "--scene", binary,
         *(['--handoff'] if handoff else []), *(['--full-screen'] if full_screen else []),
         *(['--repeat'] if repeat else [])],
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
        if not full_screen:
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
        if not full_screen:
            assert "notes/    sandbox/" in text(), "region growth lost shell context"
        pause(3.2)
        if handoff:
            click('View in pager')
            wait_for(lambda: '(END)' in text(), 'real less pager')
            assert 'name: orbit_tools' in text(), text()
            assert 'Generate config' not in text(), 'Fleury painted over the child'
            pause(3.0)
            os.write(master, b'q')
            # A PTY read can split a repaint after its first updated row.
            # Wait for the restored content as well as the status message.
            wait_for(lambda: 'Back from less.' in text()
                     and 'lib/orbit_tools.dart' in text()
                     and 'name: orbit_tools' in text(), 'resumed setup state')
            if not full_screen:
                assert 'notes/    sandbox/' in text(), 'handoff lost earlier output'
            pause(2.0)
        if not repeat:
            os.write(master, b"\x1b")  # Escape goes back without losing the form.
            wait_for(lambda: "Include tests" in text() and "Review" in text(), "back to the form")
            assert "orbit_tools" in text(), text()
            pause(1.2)
            click("Review")
            wait_for(lambda: "dev_dependencies:" in text() and "Generate config" in text(), "second review")
            pause(1.0)
        os.write(master, b"\r")  # Review autofocus makes Enter confirm.
        if repeat:
            wait_for(lambda: "Open setup again?" in text(), "ordinary CLI prompt")
            assert 'Configuration ready for orbit_tools' in text(), text()
            assert 'Generate config' not in text(), 'UI survived its completed runApp'
            # This is cooked CLI input consumed by stdin.readLineSync(), not
            # a widget simulating a prompt inside the first UI.
            pause(2.0)
            os.write(master, b'y')
            pause(0.5)
            os.write(master, b'\r')
            wait_for(lambda: 'Include tests' in text() and 'Review' in text(), 'fresh second UI')
            assert 'A command you can run' in text(), 'second form kept the first form state'
            pause(1.0)
            os.write(master, b'\x01\x0b')
            for char in b'orbit_api':
                os.write(master, bytes([char]))
                pause(0.1)
            pause(0.5)
            click('Review')
            wait_for(lambda: 'bin/orbit_api.dart' in text() and 'Generate config' in text(), 'second configuration')
            pause(2.0)
            os.write(master, b'\r')
            wait_for(lambda: 'Configuration ready for orbit_api' in text() and 'Generate config' not in text(), 'second CLI prompt')
            pause(1.8)
            os.write(master, b'n')
            pause(0.5)
            os.write(master, b'\r')
        wait_for(lambda: child.poll() is not None, "clean command exit")
        pause(0.2)
        assert child.returncode == 0, text()
        assert "Configuration ready for orbit_tools" in text(), text()
        assert "Your project, at a glance." not in text(), "live form survived completion"
        if not repeat:
            assert "notes/    sandbox/" in text(), "completion lost earlier output"
        if repeat:
            assert 'Configuration ready for orbit_api' in text(), text()
            assert raw.count(b'Configuration ready for') == 2, 'expected two completed sessions'
            assert raw.count(b'Open setup again?') == 2, 'expected two ordinary prompts'
        if handoff or full_screen:
            expected_entries = (2 if handoff or repeat else 1) if full_screen else 0
            expected_entries += int(handoff)
            assert raw.count(b'\x1b[?1049h') == expected_entries, 'unexpected alternate-screen entries'
            assert raw.count(b'\x1b[?1049l') == expected_entries, 'unbalanced alternate-screen exit'
        else:
            assert not re.search(rb"\x1b\[\?[\d;]*1049[\d;]*[hl]", raw) and b"\x1b[2J" not in raw, "used fullscreen rendering"
        # A final no-op output event holds the result long enough to read it.
        pause(1.8)
        events.append([round(time.monotonic() - start, 4), "o", ""])
        header = {"version": 2, "width": cols, "height": rows,
                  "title": ("Fleury: UI to CLI and back" if repeat else
                            "Fleury setup and less handoff" if handoff else "Fleury inline project setup"),
                  "env": {"TERM": "xterm-256color", "SHELL": "fixture"}}
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text("\n".join(json.dumps(item) for item in [header, *events]) + "\n")
        print(f"Recorded {events[-1][0]:.1f}s of native PTY output → {destination}")
        print("PASS: shared form, offset clicks, review, keyboard finish, terminal restoration")
        if handoff:
            print('PASS: real less subprocess, exclusive terminal ownership, preserved form and shell')
        if repeat:
            print('PASS: two fresh runApp sessions, cooked CLI prompts, retained summaries, natural process exit')
    finally:
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGKILL)
            child.kill()
        child.wait(timeout=5)
        os.close(slave)
        os.close(master)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--scene":
        scene(sys.argv[2], '--handoff' in sys.argv, '--full-screen' in sys.argv, '--repeat' in sys.argv)
    else:
        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument("binary", help="Compiled inline demo executable")
        flow = parser.add_mutually_exclusive_group()
        flow.add_argument('--handoff', action='store_true', help='Record the real less subprocess and return')
        flow.add_argument('--repeat', action='store_true', help='Record two UIs with ordinary CLI prompts between them')
        parser.add_argument('--full-screen', action='store_true', help='Exercise the same flow in the alternate screen')
        parser.add_argument("--output", type=Path)
        args = parser.parse_args()
        name = 'inline-repeat' if args.repeat else 'inline-handoff' if args.handoff else 'inline-setup'
        if args.full_screen:
            name += '-fullscreen'
        output = args.output or ROOT / f'website/public/recordings/{name}.cast'
        record(str(Path(args.binary).resolve()), output, args.handoff, args.full_screen, args.repeat)
