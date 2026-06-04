#!/usr/bin/env python3
"""Framework-agnostic PTY capture for the TUI profiling harness.

Runs ANY command under a real pseudo-terminal (so a TUI thinks it's attached to
a terminal and renders normally), capturing every output byte plus per-read
timestamps. Works from non-interactive shells (pty.openpty makes its own pair).

Output:
  <out>.bin   raw captured bytes (the exact ANSI on the wire)
  <out>.json  {"reads":[[t_ms, nbytes],...], "durationMs", "ttfbMs", "cmd"}

The Dart analyzer turns these into comparable axes (bytes-on-wire by category,
frame count, timing) via the same AnsiByteBreakdown every framework is measured
with. Usage:
  python3 capture_pty.py --out cap --timeout 5 -- <command> [args...]
"""
import argparse, json, os, pty, select, signal, sys, time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--timeout", type=float, default=10.0)
    ap.add_argument("--cols", type=int, default=100)
    ap.add_argument("--rows", type=int, default=30)
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.cmd[1:] if a.cmd and a.cmd[0] == "--" else a.cmd
    if not cmd:
        sys.exit("no command")

    pid, fd = pty.fork()
    if pid == 0:  # child: exec the framework's scenario app under the pty
        os.environ["COLUMNS"], os.environ["LINES"] = str(a.cols), str(a.rows)
        os.environ["TERM"] = os.environ.get("TERM", "xterm-256color")
        try:
            os.execvp(cmd[0], cmd)
        except FileNotFoundError:
            os._exit(127)

    # parent: set window size, read until EOF/timeout, timestamping each read.
    try:
        import fcntl, struct, termios
        fcntl.ioctl(fd, termios.TIOCSWINSZ,
                    struct.pack("HHHH", a.rows, a.cols, 0, 0))
    except Exception:
        pass

    raw = bytearray()
    reads = []
    start = time.monotonic()
    ttfb = None
    while True:
        if time.monotonic() - start > a.timeout:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            break
        r, _, _ = select.select([fd], [], [], 0.1)
        if fd in r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            if not data:
                break
            now = (time.monotonic() - start) * 1000.0
            if ttfb is None:
                ttfb = now
            raw.extend(data)
            reads.append([round(now, 3), len(data)])
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass

    with open(a.out + ".bin", "wb") as f:
        f.write(raw)
    with open(a.out + ".json", "w") as f:
        json.dump({"cmd": cmd, "durationMs": round((time.monotonic()-start)*1000, 3),
                   "ttfbMs": round(ttfb, 3) if ttfb else None,
                   "totalBytes": len(raw), "reads": reads}, f, indent=2)
    print(f"captured {len(raw)} bytes in {len(reads)} reads -> {a.out}.bin")


if __name__ == "__main__":
    main()
