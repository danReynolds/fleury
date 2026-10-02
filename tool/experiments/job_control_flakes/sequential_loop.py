#!/usr/bin/env python3
"""TEMPORARY (draft PR experiment, removed before merge): repeats
check_sequential_sessions.py's run() to measure the macOS "natural process
exit" flake, counting failures instead of stopping at the first.

usage: sequential_loop.py --loops N [--dart dart] [--executable path]
"""
import argparse
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from check_sequential_sessions import run  # noqa: E402

parser = argparse.ArgumentParser()
parser.add_argument('--loops', type=int, required=True)
parser.add_argument('--dart', default='dart')
parser.add_argument('--executable')
args = parser.parse_args()
failures = []
started = time.monotonic()
for iteration in range(args.loops):
    try:
        run(args.dart, args.executable)
    except AssertionError as error:
        failures.append((iteration, str(error).splitlines()[0][:160]))
        print(f'SEQ-FAIL iteration={iteration}: {error}', flush=True)
    print(f'SEQ iteration {iteration + 1}/{args.loops} failures={len(failures)} '
          f'elapsed={time.monotonic() - started:.0f}s', flush=True)
print(f'SEQ-SUMMARY iterations={args.loops} failures={len(failures)} {failures}', flush=True)
sys.exit(1 if failures else 0)
