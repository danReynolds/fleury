#!/usr/bin/env python3
"""TEMPORARY (draft PR experiment, removed before merge): repeats
check_inline_tui.py's suspend scenarios to measure the Linux Dart 3.10.4
flake, counting failures instead of stopping at the first.

usage: suspend_loop.py --loops N [--dart dart]
"""
import argparse
from pathlib import Path
import sys
import time

parser = argparse.ArgumentParser()
parser.add_argument('--loops', type=int, required=True)
parser.add_argument('--dart', default='dart')
parser.add_argument('--old-harness', action='store_true',
                    help="origin/main's harness and guard (old_check_inline_tui.py)")
args = parser.parse_args()
if args.old_harness:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from old_check_inline_tui import lifecycle, supervised_suspend  # noqa: E402
else:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from check_inline_tui import lifecycle, supervised_suspend  # noqa: E402
failures = []
started = time.monotonic()
for iteration in range(args.loops):
    for name, scenario in [('lifecycle', lambda: lifecycle(args.dart)),
                           ('supervised_suspend', lambda: supervised_suspend(args.dart))]:
        try:
            scenario()
        except AssertionError as error:
            failures.append((iteration, name, str(error).splitlines()[0][:160]))
            print(f'LOOP-FAIL iteration={iteration} {name}: {error}', flush=True)
    print(f'LOOP iteration {iteration + 1}/{args.loops} '
          f'failures={len(failures)} elapsed={time.monotonic() - started:.0f}s', flush=True)
print(f'LOOP-SUMMARY old_harness={args.old_harness} iterations={args.loops} scenarios={2 * args.loops} '
      f'failures={len(failures)} {failures}', flush=True)
sys.exit(1 if failures else 0)
