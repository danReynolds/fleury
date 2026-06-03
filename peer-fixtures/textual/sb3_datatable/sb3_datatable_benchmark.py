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

from sb3_datatable_app import Sb3DataTableApp, expected_selected_tsv, row_id

SCHEMA_VERSION = 1
PEER_ID = "textual"
PEER_NAME = "Textual"
PEER_VERSION = "8.2.7"
PEER_URL = "https://pypi.org/project/textual/"
SCENARIO_ID = "SB.3"
DEFAULT_WARMUPS = 1
DEFAULT_ITERATIONS = 3
DEFAULT_ROWS = 100_000
DEFAULT_SIZE = (80, 24)


@dataclass(frozen=True)
class Options:
    warmup_iterations: int
    measured_iterations: int
    rows: int
    size: tuple[int, int]
    print_json: bool
    output_path: str | None


@dataclass(frozen=True)
class Sample:
    mount_us: int
    first_render_us: int
    arrow_move_us: int
    page_move_us: int
    jump_to_end_us: int
    copy_selected_row_us: int
    semantic_or_test_query_us: int
    rss_delta_bytes: int
    row_count: int
    cursor_row: int
    selected_row_id: str
    scroll_y: int
    max_scroll_y: int
    visible_window_rows: int
    virtual_height: int
    visible_window_bounded: bool
    selection_correct: bool
    copy_exact: bool


async def main() -> None:
    options = parse_args()

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
        print("Textual SB.3 DataTable fixture")
        print(f"Run: {artifact['runId']}")
        print(f"Rows: {options.rows}")
        print(f"Iterations: {options.measured_iterations}")
        print(f"mountUs p95: {metrics['mountUs']['p95']}")
        print(f"pageMoveUs p95: {metrics['pageMoveUs']['p95']}")
        print(f"copySelectedRowUs p95: {metrics['copySelectedRowUs']['p95']}")
        if options.output_path is not None:
            print(f"Saved {options.output_path}")


async def run_sample(options: Options) -> Sample:
    app = Sb3DataTableApp(row_count=options.rows)
    rss_before = current_rss_bytes()
    mount_start = now_ns()
    async with app.run_test(size=options.size) as pilot:
        mount_us = elapsed_us(mount_start)

        first_render_start = now_ns()
        await pilot.pause()
        first_render_us = elapsed_us(first_render_start)

        arrow_move_us = await press_us(pilot, "down")
        page_move_us = await press_us(pilot, "pagedown")
        jump_to_end_us = await press_us(pilot, "end")
        copy_selected_row_us = await press_us(pilot, "ctrl+c")

        query_start = now_ns()
        state = app.state_snapshot()
        copied = app.last_copied_tsv
        semantic_or_test_query_us = elapsed_us(query_start)

    rss_after = current_rss_bytes()
    expected_id = row_id(options.rows - 1)
    expected_copy = expected_selected_tsv(options.rows - 1)
    visible_limit = options.size[1] + 8
    return Sample(
        mount_us=mount_us,
        first_render_us=first_render_us,
        arrow_move_us=arrow_move_us,
        page_move_us=page_move_us,
        jump_to_end_us=jump_to_end_us,
        copy_selected_row_us=copy_selected_row_us,
        semantic_or_test_query_us=semantic_or_test_query_us,
        rss_delta_bytes=max(0, rss_after - rss_before),
        row_count=state.row_count,
        cursor_row=state.cursor_row,
        selected_row_id=state.selected_row_id,
        scroll_y=state.scroll_y,
        max_scroll_y=state.max_scroll_y,
        visible_window_rows=state.visible_window_rows,
        virtual_height=state.virtual_height,
        visible_window_bounded=state.visible_window_rows <= visible_limit,
        selection_correct=(
            state.cursor_row == options.rows - 1
            and state.selected_row_id == expected_id
        ),
        copy_exact=(copied == expected_copy and "\x1b" not in copied),
    )


async def press_us(pilot: Pilot[Any], key: str) -> int:
    start = now_ns()
    await pilot.press(key)
    await pilot.pause()
    return elapsed_us(start)


def build_artifact(options: Options, samples: list[Sample]) -> dict[str, Any]:
    root = Path(__file__).resolve().parent
    captured_at = datetime.now(timezone.utc)
    run_id = f"textual-sb3-datatable-{timestamp_for_id(captured_at)}"
    all_visible_bounded = all(sample.visible_window_bounded for sample in samples)
    all_selection_correct = all(sample.selection_correct for sample in samples)
    all_copy_exact = all(sample.copy_exact for sample in samples)
    last = samples[-1]
    app_lines = source_line_count(root / "sb3_datatable_app.py")
    test_lines = source_line_count(root / "test_sb3_datatable.py")

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
            "workingDirectory": "peer-fixtures/textual/sb3_datatable",
            "command": [
                "python",
                "sb3_datatable_benchmark.py",
                f"--warmup={options.warmup_iterations}",
                f"--iterations={options.measured_iterations}",
                f"--rows={options.rows}",
                "--json",
            ],
            "warmupIterations": options.warmup_iterations,
            "measuredIterations": options.measured_iterations,
        },
        "metrics": {
            "mountUs": stats(sample.mount_us for sample in samples),
            "firstRenderUs": stats(sample.first_render_us for sample in samples),
            "arrowMoveUs": stats(sample.arrow_move_us for sample in samples),
            "pageMoveUs": stats(sample.page_move_us for sample in samples),
            "jumpToEndUs": stats(sample.jump_to_end_us for sample in samples),
            "copySelectedRowUs": stats(
                sample.copy_selected_row_us for sample in samples
            ),
            "semanticOrTestQueryUs": stats(
                sample.semantic_or_test_query_us for sample in samples
            ),
            "rssDeltaBytes": max(sample.rss_delta_bytes for sample in samples),
            "lineOfCodeCount": app_lines,
            "testLineOfCodeCount": test_lines,
            "rowCount": options.rows,
            "visibleWindowRowEstimate": last.visible_window_rows,
            "virtualHeight": last.virtual_height,
            "finalCursorRow": last.cursor_row,
            "finalSelectedRowId": last.selected_row_id,
            "finalScrollY": last.scroll_y,
            "finalMaxScrollY": last.max_scroll_y,
        },
        "correctness": [
            {
                "gate": "visible window stays bounded",
                "pass": all_visible_bounded,
                "evidence": (
                    "Textual DataTable scrollable_size.height stayed within "
                    "terminal rows plus margin."
                ),
            },
            {
                "gate": "selection is correct after jump",
                "pass": all_selection_correct,
                "evidence": f"Priority End binding selected {row_id(options.rows - 1)}.",
            },
            {
                "gate": "copy/export is sanitized and exact",
                "pass": all_copy_exact,
                "evidence": "Selected row TSV matched generated source row and contained no escape bytes.",
            },
        ],
        "ergonomics": {
            "lineOfCodeCount": app_lines,
            "testLineOfCodeCount": test_lines,
            "appFile": "sb3_datatable_app.py",
            "testFile": "test_sb3_datatable.py",
            "peerOwnedDataTable": True,
            "appOwnedJumpToEndCommand": True,
            "appOwnedCopyExport": True,
            "semanticGraphAvailable": False,
            "testQueryViaWidgetState": True,
        },
        "artifacts": [
            {
                "kind": "source",
                "path": "peer-fixtures/textual/sb3_datatable/sb3_datatable_app.py",
            },
            {
                "kind": "test",
                "path": "peer-fixtures/textual/sb3_datatable/test_sb3_datatable.py",
            },
        ],
        "notes": [
            "This is a Textual run_test peer fixture, not a real-terminal run.",
            "Textual 8.2.7 supplies the DataTable, cursor movement, paging, focus, and test harness.",
            "Jump-to-final-row and selected-row copy/export are app-owned commands in this fixture so they match the SB.3 contract explicitly.",
            "Textual exposes public widget state for this fixture, not a Fleury-style semantic app graph.",
            "Timing is local-machine evidence and should not be used as a public superiority claim without repeated peer runs.",
        ],
    }


def parse_args() -> Options:
    parser = argparse.ArgumentParser(
        description="Produce a Textual SB.3 DataTable peer benchmark artifact."
    )
    parser.add_argument("--warmup", type=positive_or_zero_int, default=DEFAULT_WARMUPS)
    parser.add_argument("--iterations", type=positive_int, default=DEFAULT_ITERATIONS)
    parser.add_argument("--rows", type=positive_int, default=DEFAULT_ROWS)
    parser.add_argument("--size", default=f"{DEFAULT_SIZE[0]}x{DEFAULT_SIZE[1]}")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--output")
    args = parser.parse_args()
    return Options(
        warmup_iterations=args.warmup,
        measured_iterations=args.iterations,
        rows=args.rows,
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
    asyncio.run(main())
