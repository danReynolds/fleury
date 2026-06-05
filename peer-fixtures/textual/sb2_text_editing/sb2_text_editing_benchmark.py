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

from sb2_text_editing_app import Sb2TextEditingApp, generate_fixture

SCHEMA_VERSION = 1
PEER_ID = "textual"
PEER_NAME = "Textual"
PEER_VERSION = "8.2.7"
PEER_URL = "https://pypi.org/project/textual/"
SCENARIO_ID = "SB.2"
DEFAULT_WARMUPS = 1
DEFAULT_ITERATIONS = 5
DEFAULT_TEXT_CHARS = 10_000
DEFAULT_WIRE_STEPS = 8
DEFAULT_WIRE_INTERVAL_MS = 60
DEFAULT_SIZE = (90, 28)


@dataclass(frozen=True)
class Options:
    warmup_iterations: int
    measured_iterations: int
    text_chars: int
    wire: bool
    wire_steps: int
    wire_interval_ms: int
    size: tuple[int, int]
    print_json: bool
    output_path: str | None


@dataclass(frozen=True)
class Sample:
    cursor_move_us: list[int]
    insertion_deletion_us: list[int]
    selection_us: list[int]
    undo_redo_us: list[int]
    history_navigation_us: list[int]
    completion_accept_us: int
    paste_complete_us: int
    semantic_or_test_query_us: int
    rss_delta_bytes: int
    mixed_width_valid: bool
    selection_and_undo_correct: bool
    redacted_correct: bool


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
        print("Textual SB.2 text editing fixture")
        print(f"Run: {artifact['runId']}")
        print(f"Text chars: {options.text_chars}")
        print(f"Iterations: {options.measured_iterations}")
        print(f"cursorMoveUs p95: {metrics['cursorMoveUs']['p95']}")
        print(f"pasteCompleteUs p95: {metrics['pasteCompleteUs']['p95']}")
        print(f"semanticOrTestQueryUs p95: {metrics['semanticOrTestQueryUs']['p95']}")
        if options.output_path is not None:
            print(f"Saved {options.output_path}")


class Sb2WireTextEditingApp(Sb2TextEditingApp):
    def __init__(self, *, text_chars: int, steps: int, interval_seconds: float) -> None:
        super().__init__(generate_fixture(text_chars=text_chars))
        self._wire_steps = steps
        self._wire_interval_seconds = interval_seconds
        self._wire_step = 0

    def on_mount(self) -> None:
        super().on_mount()
        asyncio.create_task(self._drive_wire())

    async def _drive_wire(self) -> None:
        await asyncio.sleep(self._wire_interval_seconds)
        while self._wire_step < self._wire_steps:
            step = self._wire_step % 8
            if step == 0:
                self.focus_editor_end()
                self._editor.move_cursor_relative(columns=-12)
                self._editor.move_cursor_relative(columns=6)
            elif step == 1:
                self._editor.insert("x")
                self._editor.action_delete_left()
            elif step == 2:
                self.replace_selection()
            elif step == 3:
                self._editor.undo()
                self._editor.redo()
            elif step == 4:
                self.paste_large_text()
            elif step == 5:
                self.focus_composer()
                self.set_composer_text("git che")
                self.action_accept_completion()
            elif step == 6:
                self.set_composer_text(self.fixture.history_draft)
                self.action_history_previous()
                self.action_history_next()
            elif step == 7:
                self.focus_secret()
            self._wire_step += 1
            await asyncio.sleep(self._wire_interval_seconds)
        self.exit()


def run_wire(options: Options) -> None:
    app = Sb2WireTextEditingApp(
        text_chars=options.text_chars,
        steps=options.wire_steps,
        interval_seconds=options.wire_interval_ms / 1000,
    )
    app.run()


async def run_sample(options: Options) -> Sample:
    fixture = generate_fixture(text_chars=options.text_chars)
    app = Sb2TextEditingApp(fixture)
    rss_before = current_rss_bytes()
    async with app.run_test(size=options.size) as pilot:
        await pilot.pause()
        app.focus_editor_end()
        await pilot.pause()

        cursor_move_us = [
            await press_us(pilot, "left"),
            await press_us(pilot, "ctrl+left"),
            await press_us(pilot, "home"),
            await press_us(pilot, "end"),
        ]

        insertion_deletion_us = [
            await press_us(pilot, "x"),
            await press_us(pilot, "backspace"),
        ]
        insertion_deletion_worked = "x" not in app._editor.text[-8:]

        selection_us = [
            await press_us(pilot, "shift+left"),
        ]
        selection_start = now_ns()
        app.replace_selection()
        await pilot.pause()
        selection_us.append(elapsed_us(selection_start))
        selection_replacement_inserted = fixture.selection_replacement in app._editor.text

        undo_redo_us = [
            await press_us(pilot, "ctrl+z"),
        ]
        undo_removed_replacement = fixture.selection_replacement not in app._editor.text
        undo_redo_us.append(await press_us(pilot, "ctrl+y"))
        redo_restored_replacement = fixture.selection_replacement in app._editor.text

        paste_start = now_ns()
        app.paste_large_text()
        await pilot.pause()
        paste_complete_us = elapsed_us(paste_start)
        paste_inserted = fixture.paste_marker in app._editor.text

        app.focus_composer()
        app.set_composer_text("git che")
        await pilot.pause()
        completion_accept_us = await press_us(pilot, "tab")
        completion_accepted = app._composer.value == "git checkout" and app.completion_accepted

        app.set_composer_text(fixture.history_draft)
        await pilot.pause()
        history_navigation_us = [
            await press_us(pilot, "up"),
            await press_us(pilot, "down"),
        ]
        history_restored_draft = app._composer.value == fixture.history_draft

        app.focus_secret()
        await pilot.pause()
        query_start = now_ns()
        state = app.state_snapshot()
        semantic_or_test_query_us = elapsed_us(query_start)

    rss_after = current_rss_bytes()
    mixed_width_valid = (
        state.contains_paste_marker
        and state.contains_cjk
        and state.contains_emoji
        and state.contains_combining
    )
    selection_and_undo_correct = (
        insertion_deletion_worked
        and selection_replacement_inserted
        and undo_removed_replacement
        and redo_restored_replacement
        and paste_inserted
        and completion_accepted
        and history_restored_draft
    )
    redacted_correct = state.password_input_mode and not state.raw_secret_in_display
    return Sample(
        cursor_move_us=cursor_move_us,
        insertion_deletion_us=insertion_deletion_us,
        selection_us=selection_us,
        undo_redo_us=undo_redo_us,
        history_navigation_us=history_navigation_us,
        completion_accept_us=completion_accept_us,
        paste_complete_us=paste_complete_us,
        semantic_or_test_query_us=semantic_or_test_query_us,
        rss_delta_bytes=max(0, rss_after - rss_before),
        mixed_width_valid=mixed_width_valid,
        selection_and_undo_correct=selection_and_undo_correct,
        redacted_correct=redacted_correct,
    )


async def press_us(pilot: Pilot[Any], key: str) -> int:
    start = now_ns()
    await pilot.press(key)
    await pilot.pause()
    return elapsed_us(start)


def build_artifact(options: Options, samples: list[Sample]) -> dict[str, Any]:
    root = Path(__file__).resolve().parent
    captured_at = datetime.now(timezone.utc)
    run_id = f"textual-sb2-text-editing-{timestamp_for_id(captured_at)}"
    app_lines = source_line_count(root / "sb2_text_editing_app.py")
    benchmark_lines = source_line_count(root / "sb2_text_editing_benchmark.py")
    test_lines = source_line_count(root / "test_sb2_text_editing.py")

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
            "workingDirectory": "peer-fixtures/textual/sb2_text_editing",
            "command": [
                "python",
                "sb2_text_editing_benchmark.py",
                f"--warmup={options.warmup_iterations}",
                f"--iterations={options.measured_iterations}",
                f"--text-chars={options.text_chars}",
                "--json",
            ],
            "warmupIterations": options.warmup_iterations,
            "measuredIterations": options.measured_iterations,
        },
        "metrics": {
            "cursorMoveUs": stats(
                value for sample in samples for value in sample.cursor_move_us
            ),
            "insertionDeletionUs": stats(
                value for sample in samples for value in sample.insertion_deletion_us
            ),
            "selectionUs": stats(value for sample in samples for value in sample.selection_us),
            "undoRedoUs": stats(value for sample in samples for value in sample.undo_redo_us),
            "historyNavigationUs": stats(
                value for sample in samples for value in sample.history_navigation_us
            ),
            "completionAcceptUs": stats(sample.completion_accept_us for sample in samples),
            "pasteCompleteUs": stats(sample.paste_complete_us for sample in samples),
            "semanticOrTestQueryUs": stats(
                sample.semantic_or_test_query_us for sample in samples
            ),
            "rssDeltaBytes": max(sample.rss_delta_bytes for sample in samples),
            "lineOfCodeCount": app_lines,
            "benchmarkLineOfCodeCount": benchmark_lines,
            "testLineOfCodeCount": test_lines,
            "textCharsRequested": options.text_chars,
            "adapterOwnedFeatureCount": 2,
        },
        "correctness": [
            {
                "gate": "mixed-width text remains valid",
                "pass": all(sample.mixed_width_valid for sample in samples),
                "evidence": "Textual TextArea retained emoji, CJK, combining text, and paste marker.",
            },
            {
                "gate": "selection and undo state are correct",
                "pass": all(sample.selection_and_undo_correct for sample in samples),
                "evidence": (
                    "Textual TextArea handled selection replacement and undo/redo; "
                    "history/completion are fixture-owned adapters."
                ),
            },
            {
                "gate": "redacted value stays redacted",
                "pass": all(sample.redacted_correct for sample in samples),
                "evidence": "Password Input display did not contain the raw secret.",
            },
        ],
        "ergonomics": {
            "lineOfCodeCount": app_lines,
            "benchmarkLineOfCodeCount": benchmark_lines,
            "testLineOfCodeCount": test_lines,
            "appFile": "sb2_text_editing_app.py",
            "benchmarkFile": "sb2_text_editing_benchmark.py",
            "testFile": "test_sb2_text_editing.py",
            "peerOwnedTextArea": True,
            "peerOwnedInput": True,
            "peerOwnedUndoRedo": True,
            "appOwnedHistory": True,
            "appOwnedCompletion": True,
            "semanticGraphAvailable": False,
            "testQueryViaWidgetState": True,
        },
        "artifacts": [
            {
                "kind": "source",
                "path": "peer-fixtures/textual/sb2_text_editing/sb2_text_editing_app.py",
            },
            {
                "kind": "benchmark",
                "path": "peer-fixtures/textual/sb2_text_editing/sb2_text_editing_benchmark.py",
            },
            {
                "kind": "test",
                "path": "peer-fixtures/textual/sb2_text_editing/test_sb2_text_editing.py",
            },
        ],
        "notes": [
            "This is a Textual run_test peer fixture, not a real-terminal run.",
            "Textual 8.2.7 supplies TextArea, password Input, built-in cursor movement, selection, paste/edit APIs, and undo/redo.",
            "Submission history and completion acceptance are app-owned adapters in this fixture because Textual does not expose a Fleury-equivalent command composer history/completion contract for SB.2.",
            "Textual exposes widget/app state for this fixture, not a Fleury-style semantic app graph.",
            "Timing is local-machine evidence and should not be used as a public superiority claim without repeated peer runs.",
        ],
    }


def stats(values: Iterable[int]) -> dict[str, int]:
    sorted_values = sorted(values)
    if not sorted_values:
        raise ValueError("Cannot summarize empty metric samples.")
    return {
        "min": sorted_values[0],
        "median": percentile(sorted_values, 0.50),
        "p95": percentile(sorted_values, 0.95),
        "p99": percentile(sorted_values, 0.99),
        "max": sorted_values[-1],
        "samples": len(sorted_values),
    }


def percentile(sorted_values: list[int], percent: float) -> int:
    index = min(
        len(sorted_values) - 1,
        max(0, math.ceil(len(sorted_values) * percent) - 1),
    )
    return sorted_values[index]


def source_line_count(path: Path) -> int:
    return sum(
        1
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )


def current_rss_bytes() -> int:
    usage = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    if sys.platform == "darwin":
        return int(usage)
    return int(usage * 1024)


def now_ns() -> int:
    return time.perf_counter_ns()


def elapsed_us(start_ns: int) -> int:
    return max(0, (time.perf_counter_ns() - start_ns) // 1000)


def timestamp_for_id(value: datetime) -> str:
    return value.strftime("%Y-%m-%dT%H-%M-%SZ")


def parse_size(value: str) -> tuple[int, int]:
    parts = value.lower().split("x", maxsplit=1)
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("--size must be COLUMNSxROWS")
    try:
        columns = int(parts[0])
        rows = int(parts[1])
    except ValueError as error:
        raise argparse.ArgumentTypeError("--size must be COLUMNSxROWS") from error
    return columns, rows


def parse_args() -> Options:
    parser = argparse.ArgumentParser(description="Textual SB.2 text editing fixture")
    parser.add_argument("--warmup", type=int, default=DEFAULT_WARMUPS)
    parser.add_argument("--iterations", type=int, default=DEFAULT_ITERATIONS)
    parser.add_argument("--text-chars", type=int, default=DEFAULT_TEXT_CHARS)
    parser.add_argument("--rows", type=int, dest="row_workload")
    parser.add_argument("--wire", action="store_true")
    parser.add_argument("--steps", type=int, default=DEFAULT_WIRE_STEPS)
    parser.add_argument("--interval-ms", type=int, default=DEFAULT_WIRE_INTERVAL_MS)
    parser.add_argument("--columns", type=int, default=DEFAULT_SIZE[0])
    parser.add_argument("--terminal-rows", type=int, default=DEFAULT_SIZE[1])
    parser.add_argument("--size")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--output")
    args = parser.parse_args()
    if args.warmup < 0:
        parser.error("--warmup must be non-negative")
    if args.iterations <= 0:
        parser.error("--iterations must be positive")
    text_chars = args.text_chars
    if args.row_workload is not None:
        text_chars = args.row_workload
    columns = args.columns
    terminal_rows = args.terminal_rows
    if args.size is not None:
        columns, terminal_rows = parse_size(args.size)
    if text_chars <= 0:
        parser.error("--text-chars must be positive")
    if args.steps <= 0:
        parser.error("--steps must be positive")
    if args.interval_ms <= 0:
        parser.error("--interval-ms must be positive")
    if columns <= 0 or terminal_rows <= 0:
        parser.error("--columns and --rows must be positive")
    return Options(
        warmup_iterations=args.warmup,
        measured_iterations=args.iterations,
        text_chars=text_chars,
        wire=args.wire,
        wire_steps=args.steps,
        wire_interval_ms=args.interval_ms,
        size=(columns, terminal_rows),
        print_json=args.json,
        output_path=args.output,
    )


if __name__ == "__main__":
    parsed_options = parse_args()
    if parsed_options.wire:
        run_wire(parsed_options)
    else:
        asyncio.run(main(parsed_options))
