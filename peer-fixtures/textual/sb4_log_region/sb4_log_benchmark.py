from __future__ import annotations

import argparse
import asyncio
import json
import math
import platform
import resource
import socket
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

import textual
from textual.pilot import Pilot

from sb4_log_app import (
    Sb4LogRegionApp,
    append_filter_query,
    expected_copied_text,
    log_key,
)

SCHEMA_VERSION = 1
PEER_ID = "textual"
PEER_NAME = "Textual"
PEER_VERSION = "8.2.7"
PEER_URL = "https://pypi.org/project/textual/"
SCENARIO_ID = "SB.4"
DEFAULT_WARMUPS = 1
DEFAULT_ITERATIONS = 3
DEFAULT_ROWS = 100_000
DEFAULT_APPEND = 1_000
DEFAULT_WIRE_STEPS = 5
DEFAULT_WIRE_INTERVAL_MS = 100
DEFAULT_SIZE = (120, 32)


@dataclass(frozen=True)
class Options:
    warmup_iterations: int
    measured_iterations: int
    rows: int
    append_count: int
    wire: bool
    wire_steps: int
    wire_interval_ms: int
    size: tuple[int, int]
    print_json: bool
    output_path: str | None


@dataclass(frozen=True)
class Sample:
    mount_us: int
    first_render_us: int
    append_burst_us: int
    scrollback_jump_us: int
    scroll_to_tail_us: int
    copy_selected_entry_us: int
    filter_query_us: int
    semantic_or_test_query_us: int
    rss_delta_bytes: int
    unsafe_artifact_leak_count: int
    entry_count_after_append: int
    line_count_after_filter: int
    filter_match_count: int
    selected_key: str
    scroll_y: int
    max_scroll_y: int
    visible_window_rows: int
    tail_anchoring_correct: bool
    copy_text_sanitized: bool
    filter_result_correct: bool
    scrollback_selected_correct: bool


async def main(options: Options) -> None:
    for _ in range(options.warmup_iterations):
        await run_sample(options)

    samples = []
    for _ in range(options.measured_iterations):
        samples.append(await run_sample(options))

    artifact = build_artifact(options, samples)
    json_text = json.dumps(artifact, indent=2)
    if options.output_path is not None:
        output = Path(options.output_path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(f"{json_text}\n", encoding="utf-8")

    if options.print_json:
        print(json_text)
    else:
        metrics = artifact["metrics"]
        print("Textual SB.4 LogRegion fixture")
        print(f"Run: {artifact['runId']}")
        print(f"Rows: {options.rows}")
        print(f"Append: {options.append_count}")
        print(f"Iterations: {options.measured_iterations}")
        print(f"appendBurstUs p95: {metrics['appendBurstUs']['p95']}")
        print(f"filterQueryUs p95: {metrics['filterQueryUs']['p95']}")
        print(f"unsafeArtifactLeakCount: {metrics['unsafeArtifactLeakCount']}")
        if options.output_path is not None:
            print(f"Saved {options.output_path}")


class Sb4WireLogRegionApp(Sb4LogRegionApp):
    def __init__(
        self,
        *,
        row_count: int,
        append_count: int,
        steps: int,
        interval_seconds: float,
    ) -> None:
        super().__init__(row_count=row_count)
        self._wire_append_count = append_count
        self._wire_steps = steps
        self._wire_interval_seconds = interval_seconds

    def on_mount(self) -> None:
        super().on_mount()
        asyncio.create_task(self._drive_wire())

    async def _drive_wire(self) -> None:
        await asyncio.sleep(self._wire_interval_seconds)
        for _ in range(self._wire_steps):
            self.append_burst(self._wire_append_count)
            await asyncio.sleep(self._wire_interval_seconds)
        self.exit()


def run_wire(options: Options) -> None:
    app = Sb4WireLogRegionApp(
        row_count=options.rows,
        append_count=options.append_count,
        steps=options.wire_steps,
        interval_seconds=options.wire_interval_ms / 1000,
    )
    app.run()


async def run_sample(options: Options) -> Sample:
    app = Sb4LogRegionApp(row_count=options.rows)
    rss_before = current_rss_bytes()
    mount_start = now_ns()
    async with app.run_test(size=options.size) as pilot:
        mount_us = elapsed_us(mount_start)

        first_render_start = now_ns()
        await pilot.pause()
        first_render_us = elapsed_us(first_render_start)

        append_start = now_ns()
        app.append_burst(options.append_count)
        await pilot.pause()
        append_burst_us = elapsed_us(append_start)
        append_state = app.state_snapshot()

        scrollback_index = options.rows // 2
        scrollback_start = now_ns()
        app.jump_to_scrollback(scrollback_index)
        await pilot.pause()
        scrollback_jump_us = elapsed_us(scrollback_start)
        scrollback_state = app.state_snapshot()

        tail_start = now_ns()
        app.scroll_to_tail()
        await pilot.pause()
        scroll_to_tail_us = elapsed_us(tail_start)
        tail_state = app.state_snapshot()

        copy_start = now_ns()
        await pilot.press("ctrl+c")
        await pilot.pause()
        copy_selected_entry_us = elapsed_us(copy_start)
        copied = app.last_copied_text

        filter_start = now_ns()
        filter_match_count = app.filter_query(append_filter_query(options.rows))
        await pilot.pause()
        filter_query_us = elapsed_us(filter_start)

        query_start = now_ns()
        state = app.state_snapshot()
        semantic_or_test_query_us = elapsed_us(query_start)

    rss_after = current_rss_bytes()
    expected_last_index = options.rows + options.append_count - 1
    expected_last_key = log_key(expected_last_index)
    return Sample(
        mount_us=mount_us,
        first_render_us=first_render_us,
        append_burst_us=append_burst_us,
        scrollback_jump_us=scrollback_jump_us,
        scroll_to_tail_us=scroll_to_tail_us,
        copy_selected_entry_us=copy_selected_entry_us,
        filter_query_us=filter_query_us,
        semantic_or_test_query_us=semantic_or_test_query_us,
        rss_delta_bytes=max(0, rss_after - rss_before),
        unsafe_artifact_leak_count=state.unsafe_artifact_leak_count,
        entry_count_after_append=append_state.entry_count,
        line_count_after_filter=state.line_count,
        filter_match_count=filter_match_count,
        selected_key=state.selected_key,
        scroll_y=state.scroll_y,
        max_scroll_y=state.max_scroll_y,
        visible_window_rows=state.visible_window_rows,
        tail_anchoring_correct=(
            append_state.tail_anchored
            and tail_state.tail_anchored
            and tail_state.selected_key == expected_last_key
            and tail_state.line_count == options.rows + options.append_count
        ),
        copy_text_sanitized=(
            copied == expected_copied_text(expected_last_index)
            and "\x1b" not in copied
            and "secret-" not in copied
            and "\n" not in copied
            and "\r" not in copied
        ),
        filter_result_correct=(
            filter_match_count == options.append_count
            and state.line_count == options.append_count
            and state.selected_key == expected_last_key
        ),
        scrollback_selected_correct=(
            scrollback_state.selected_key == log_key(scrollback_index)
            and scrollback_state.scroll_y <= scrollback_state.max_scroll_y
        ),
    )


async def press_us(pilot: Pilot[Any], key: str) -> int:
    start = now_ns()
    await pilot.press(key)
    await pilot.pause()
    return elapsed_us(start)


def build_artifact(options: Options, samples: list[Sample]) -> dict[str, Any]:
    root = Path(__file__).resolve().parent
    captured_at = datetime.now(timezone.utc)
    run_id = f"textual-sb4-log-region-{timestamp_for_id(captured_at)}"
    last = samples[-1]
    app_lines = source_line_count(root / "sb4_log_app.py")
    test_lines = source_line_count(root / "test_sb4_log_region.py")
    unsafe_leak_count = max(sample.unsafe_artifact_leak_count for sample in samples)

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "fleuryPeerBenchmarkRun",
        "runId": run_id,
        "peerId": PEER_ID,
        "scenarioId": SCENARIO_ID,
        "capturedAt": captured_at.isoformat().replace("+00:00", "Z"),
        "source": {
            "name": PEER_NAME,
            "version": PEER_VERSION,
            "url": PEER_URL,
        },
        "environment": {
            "machine": socket.gethostname(),
            "operatingSystem": sys.platform,
            "operatingSystemVersion": platform.platform(),
            "runtime": f"Python {platform.python_version()} / Textual {textual.__version__}",
            "terminalMode": "textual-run-test-harness",
            "terminalSize": {
                "columns": options.size[0],
                "rows": options.size[1],
            },
        },
        "fixture": {
            "workingDirectory": "peer-fixtures/textual/sb4_log_region",
            "command": [
                "python",
                "sb4_log_benchmark.py",
                f"--warmup={options.warmup_iterations}",
                f"--iterations={options.measured_iterations}",
                f"--rows={options.rows}",
                f"--append={options.append_count}",
                "--json",
            ],
            "warmupIterations": options.warmup_iterations,
            "measuredIterations": options.measured_iterations,
        },
        "metrics": {
            "mountUs": stats(sample.mount_us for sample in samples),
            "firstRenderUs": stats(sample.first_render_us for sample in samples),
            "appendBurstUs": stats(sample.append_burst_us for sample in samples),
            "scrollbackJumpUs": stats(
                sample.scrollback_jump_us for sample in samples
            ),
            "scrollToTailUs": stats(sample.scroll_to_tail_us for sample in samples),
            "copySelectedEntryUs": stats(
                sample.copy_selected_entry_us for sample in samples
            ),
            "filterQueryUs": stats(sample.filter_query_us for sample in samples),
            "semanticOrTestQueryUs": stats(
                sample.semantic_or_test_query_us for sample in samples
            ),
            "unsafeArtifactLeakCount": unsafe_leak_count,
            "rssDeltaBytes": max(sample.rss_delta_bytes for sample in samples),
            "lineOfCodeCount": app_lines,
            "testLineOfCodeCount": test_lines,
            "entryCountAfterAppend": last.entry_count_after_append,
            "appendCount": options.append_count,
            "lineCountAfterFilter": last.line_count_after_filter,
            "filterMatchCount": last.filter_match_count,
            "selectedKey": last.selected_key,
            "finalScrollY": last.scroll_y,
            "finalMaxScrollY": last.max_scroll_y,
            "visibleWindowRowEstimate": last.visible_window_rows,
        },
        "correctness": [
            {
                "gate": "tail anchoring is correct",
                "pass": all(sample.tail_anchoring_correct for sample in samples),
                "evidence": (
                    "After append and explicit tail scroll, Textual Log stayed "
                    f"anchored at {log_key(options.rows + options.append_count - 1)}."
                ),
            },
            {
                "gate": "copy text is sanitized",
                "pass": all(sample.copy_text_sanitized for sample in samples),
                "evidence": (
                    "Selected-entry copy matched the generated sanitized log line "
                    "and contained no escape, secret, or newline artifacts."
                ),
            },
            {
                "gate": "unsafe output leak count is zero",
                "pass": unsafe_leak_count == 0,
                "evidence": "Fixture-owned sanitizer removed ANSI/OSC/control payloads before Textual Log ingestion.",
            },
        ],
        "ergonomics": {
            "lineOfCodeCount": app_lines,
            "testLineOfCodeCount": test_lines,
            "appFile": "sb4_log_app.py",
            "testFile": "test_sb4_log_region.py",
            "peerOwnedLogWidget": True,
            "appOwnedSanitization": True,
            "appOwnedFiltering": True,
            "appOwnedSelectedEntryCopy": True,
            "semanticGraphAvailable": False,
            "testQueryViaWidgetAndAppState": True,
        },
        "artifacts": [
            {
                "kind": "source",
                "path": "peer-fixtures/textual/sb4_log_region/sb4_log_app.py",
            },
            {
                "kind": "test",
                "path": "peer-fixtures/textual/sb4_log_region/test_sb4_log_region.py",
            },
        ],
        "notes": [
            "This is a Textual run_test peer fixture, not a real-terminal run.",
            "Textual 8.2.7 supplies the Log widget, append rendering, scroll state, focus, and test harness.",
            "Sanitization/redaction, filtering, selected-entry state, and copy/export are app-owned fixture code because Textual Log does not provide Fleury-equivalent primitives for those SB.4 behaviors.",
            "Textual exposes public widget/app state for this fixture, not a Fleury-style semantic app graph.",
            "Timing is local-machine evidence and should not be used as a public superiority claim without repeated peer runs.",
        ],
    }


def parse_args() -> Options:
    parser = argparse.ArgumentParser(
        description="Produce a Textual SB.4 LogRegion peer benchmark artifact."
    )
    parser.add_argument("--warmup", type=positive_or_zero_int, default=DEFAULT_WARMUPS)
    parser.add_argument("--iterations", type=positive_int, default=DEFAULT_ITERATIONS)
    parser.add_argument("--rows", type=positive_int, default=DEFAULT_ROWS)
    parser.add_argument("--append", type=positive_int, default=DEFAULT_APPEND)
    parser.add_argument("--size", default=f"{DEFAULT_SIZE[0]}x{DEFAULT_SIZE[1]}")
    parser.add_argument("--wire", action="store_true")
    parser.add_argument("--steps", type=positive_int, default=DEFAULT_WIRE_STEPS)
    parser.add_argument(
        "--interval-ms",
        type=positive_int,
        default=DEFAULT_WIRE_INTERVAL_MS,
    )
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--output")
    args = parser.parse_args()
    return Options(
        warmup_iterations=args.warmup,
        measured_iterations=args.iterations,
        rows=args.rows,
        append_count=args.append,
        wire=args.wire,
        wire_steps=args.steps,
        wire_interval_ms=args.interval_ms,
        size=parse_size(args.size),
        print_json=args.json,
        output_path=args.output,
    )


def parse_size(value: str) -> tuple[int, int]:
    try:
        columns_text, rows_text = value.lower().split("x", 1)
        columns = int(columns_text)
        rows = int(rows_text)
    except ValueError as error:
        raise argparse.ArgumentTypeError("--size must be COLUMNSxROWS") from error
    if columns <= 0 or rows <= 0:
        raise argparse.ArgumentTypeError("--size dimensions must be positive")
    return columns, rows


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be positive")
    return parsed


def positive_or_zero_int(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("value must be zero or positive")
    return parsed


def now_ns() -> int:
    return time.perf_counter_ns()


def elapsed_us(start_ns: int) -> int:
    return max(0, (time.perf_counter_ns() - start_ns) // 1_000)


def current_rss_bytes() -> int:
    value = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    if sys.platform == "darwin":
        return int(value)
    return int(value) * 1024


def stats(values: Iterable[int]) -> dict[str, int]:
    ordered = sorted(int(value) for value in values)
    if not ordered:
        return {"min": 0, "median": 0, "p95": 0, "p99": 0, "max": 0, "samples": 0}
    return {
        "min": ordered[0],
        "median": percentile(ordered, 0.50),
        "p95": percentile(ordered, 0.95),
        "p99": percentile(ordered, 0.99),
        "max": ordered[-1],
        "samples": len(ordered),
    }


def percentile(ordered: list[int], fraction: float) -> int:
    if len(ordered) == 1:
        return ordered[0]
    index = math.ceil((len(ordered) - 1) * fraction)
    return ordered[min(index, len(ordered) - 1)]


def source_line_count(path: Path) -> int:
    count = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            count += 1
    return count


def timestamp_for_id(value: datetime) -> str:
    return value.strftime("%Y-%m-%dT%H-%M-%SZ")


if __name__ == "__main__":
    parsed_options = parse_args()
    if parsed_options.wire:
        run_wire(parsed_options)
    else:
        asyncio.run(main(parsed_options))
