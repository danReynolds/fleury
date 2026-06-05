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

from sb5_markdown_app import (
    MarkdownFixture,
    Sb5StreamingMarkdownApp,
    markdown_chunk_count_for,
    parse_markdown_document,
    sanitize_markdown_chunk,
    unsafe_count_text,
)

SCHEMA_VERSION = 1
PEER_ID = "textual"
PEER_NAME = "Textual"
PEER_VERSION = "8.2.7"
PEER_URL = "https://textual.textualize.io/widgets/markdown/"
SCENARIO_ID = "SB.5"
DEFAULT_WARMUPS = 1
DEFAULT_ITERATIONS = 3
DEFAULT_ROWS = 100_000
DEFAULT_WIRE_STEPS = 16
DEFAULT_WIRE_INTERVAL_MS = 50
DEFAULT_SIZE = (120, 32)


@dataclass(frozen=True)
class Options:
    warmup_iterations: int
    measured_iterations: int
    rows: int
    wire: bool
    wire_steps: int
    wire_interval_ms: int
    size: tuple[int, int]
    print_json: bool
    output_path: str | None


@dataclass(frozen=True)
class Sample:
    total_journey_us: int
    chunk_parse_us: list[int]
    chunk_frame_us: list[int]
    chunk_update_us: list[int]
    final_render_us: int
    copy_selected_block_us: int
    semantic_or_test_query_us: int
    rss_delta_bytes: int
    initial_frame_probe_us: int
    chunk_count: int
    source_byte_count: int
    block_count: int
    heading_count: int
    list_item_count: int
    link_count: int
    unsafe_link_count: int
    code_block_count: int
    code_line_count: int
    selected_block_index: int
    selected_block_kind: str
    unsafe_frame_count: int
    sanitized_block_count: int
    sanitized_chunk_count: int
    truncated_block_count: int
    copied_byte_count: int
    incremental_content_coherent: bool
    unsafe_links_have_visible_fallback: bool
    unsafe_frame_free: bool


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
        print("Textual SB.5 Streaming Markdown fixture")
        print(f"Run: {artifact['runId']}")
        print(f"Rows: {options.rows}")
        print(f"Chunks: {metrics['chunkCount']}")
        print(f"Iterations: {options.measured_iterations}")
        print(f"chunkUpdateUs p95: {metrics['chunkUpdateUs']['p95']}")
        print(f"finalRenderUs p95: {metrics['finalRenderUs']['p95']}")
        print(f"unsafeFrameCount: {metrics['unsafeFrameCount']}")
        if options.output_path is not None:
            print(f"Saved {options.output_path}")


class Sb5WireStreamingMarkdownApp(Sb5StreamingMarkdownApp):
    def __init__(self, *, rows: int, steps: int, interval_seconds: float) -> None:
        super().__init__()
        self._wire_fixture = MarkdownFixture(seed=1)
        self._wire_chunk_count = markdown_chunk_count_for(rows)
        self._wire_steps = steps
        self._wire_interval_seconds = interval_seconds
        self._wire_emitted = 0

    def on_mount(self) -> None:
        super().on_mount()
        asyncio.create_task(self._drive_wire())

    async def _drive_wire(self) -> None:
        await asyncio.sleep(self._wire_interval_seconds)
        while self._wire_emitted < self._wire_chunk_count:
            remaining = self._wire_chunk_count - self._wire_emitted
            remaining_steps = self._wire_steps - (
                self._wire_emitted * self._wire_steps // self._wire_chunk_count
            )
            batch = remaining if remaining_steps <= 1 else remaining // remaining_steps
            if batch <= 0:
                batch = 1
            for _ in range(batch):
                if self._wire_emitted >= self._wire_chunk_count:
                    break
                await self.append_chunk(self._wire_fixture.chunk(self._wire_emitted))
                self._wire_emitted += 1
            await asyncio.sleep(self._wire_interval_seconds)
        self.select_final_block()
        await asyncio.sleep(self._wire_interval_seconds)
        self.exit()


def run_wire(options: Options) -> None:
    app = Sb5WireStreamingMarkdownApp(
        rows=options.rows,
        steps=options.wire_steps,
        interval_seconds=options.wire_interval_ms / 1000,
    )
    app.run()


async def run_sample(options: Options) -> Sample:
    app = Sb5StreamingMarkdownApp()
    fixture = MarkdownFixture(seed=1)
    chunk_count = markdown_chunk_count_for(options.rows)
    chunk_parse_us: list[int] = []
    chunk_frame_us: list[int] = []
    chunk_update_us: list[int] = []
    unsafe_frame_count = 0
    metadata_source = ""
    rss_before = current_rss_bytes()
    total_start = now_ns()

    async with app.run_test(size=options.size) as pilot:
        initial_start = now_ns()
        await pilot.pause()
        initial_frame_probe_us = elapsed_us(initial_start)

        for index in range(chunk_count):
            raw_chunk = fixture.chunk(index)
            update_start = now_ns()

            parse_start = now_ns()
            sanitized = sanitize_markdown_chunk(raw_chunk)
            metadata_source += sanitized
            parse_markdown_document(metadata_source)
            parse_us = elapsed_us(parse_start)

            frame_start = now_ns()
            await app.append_chunk(raw_chunk)
            await pilot.pause()
            frame_us = elapsed_us(frame_start)

            update_us = elapsed_us(update_start)
            chunk_parse_us.append(parse_us)
            chunk_frame_us.append(frame_us)
            chunk_update_us.append(update_us)
            if unsafe_count_text(app.source) > 0:
                unsafe_frame_count += 1

        app.select_final_block()
        final_start = now_ns()
        await pilot.pause()
        final_render_us = elapsed_us(final_start)

        copy_start = now_ns()
        await pilot.press("ctrl+c")
        await pilot.pause()
        copy_selected_block_us = elapsed_us(copy_start)

        query_start = now_ns()
        state = app.state_snapshot()
        semantic_or_test_query_us = elapsed_us(query_start)

    total_journey_us = elapsed_us(total_start)
    rss_after = current_rss_bytes()
    copied_safe = unsafe_count_text(app.last_copied_text) == 0
    source_safe = unsafe_count_text(app.source) == 0
    content_coherent = (
        state.chunk_count == chunk_count
        and state.block_count > 0
        and state.heading_count > 0
        and state.list_item_count > 0
        and state.link_count > 0
        and state.unsafe_link_count > 0
        and state.code_block_count > 0
        and state.code_line_count > 0
        and state.selected_block_index == state.block_count - 1
        and state.copied_byte_count > 0
        and state.sanitized_chunk_count > 0
    )
    return Sample(
        total_journey_us=total_journey_us,
        chunk_parse_us=chunk_parse_us,
        chunk_frame_us=chunk_frame_us,
        chunk_update_us=chunk_update_us,
        final_render_us=final_render_us,
        copy_selected_block_us=copy_selected_block_us,
        semantic_or_test_query_us=semantic_or_test_query_us,
        rss_delta_bytes=max(0, rss_after - rss_before),
        initial_frame_probe_us=initial_frame_probe_us,
        chunk_count=state.chunk_count,
        source_byte_count=state.source_byte_count,
        block_count=state.block_count,
        heading_count=state.heading_count,
        list_item_count=state.list_item_count,
        link_count=state.link_count,
        unsafe_link_count=state.unsafe_link_count,
        code_block_count=state.code_block_count,
        code_line_count=state.code_line_count,
        selected_block_index=state.selected_block_index,
        selected_block_kind=state.selected_block_kind,
        unsafe_frame_count=unsafe_frame_count + state.unsafe_artifact_leak_count,
        sanitized_block_count=state.sanitized_block_count,
        sanitized_chunk_count=state.sanitized_chunk_count,
        truncated_block_count=state.truncated_block_count,
        copied_byte_count=state.copied_byte_count,
        incremental_content_coherent=content_coherent,
        unsafe_links_have_visible_fallback=state.unsafe_links_have_visible_fallback,
        unsafe_frame_free=unsafe_frame_count == 0 and copied_safe and source_safe,
    )


def build_artifact(options: Options, samples: list[Sample]) -> dict[str, Any]:
    root = Path(__file__).resolve().parent
    captured_at = datetime.now(timezone.utc)
    run_id = f"textual-sb5-streaming-markdown-{timestamp_for_id(captured_at)}"
    last = samples[-1]
    app_lines = source_line_count(root / "sb5_markdown_app.py")
    test_lines = source_line_count(root / "test_sb5_markdown.py")
    unsafe_frame_count = max(sample.unsafe_frame_count for sample in samples)

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
            "workingDirectory": "peer-fixtures/textual/sb5_streaming_markdown",
            "command": [
                "python",
                "sb5_markdown_benchmark.py",
                f"--warmup={options.warmup_iterations}",
                f"--iterations={options.measured_iterations}",
                f"--rows={options.rows}",
                "--json",
            ],
            "warmupIterations": options.warmup_iterations,
            "measuredIterations": options.measured_iterations,
        },
        "metrics": {
            "journeyUs": stats(sample.total_journey_us for sample in samples),
            "chunkParseUs": stats(
                value for sample in samples for value in sample.chunk_parse_us
            ),
            "chunkFrameUs": stats(
                value for sample in samples for value in sample.chunk_frame_us
            ),
            "chunkUpdateUs": stats(
                value for sample in samples for value in sample.chunk_update_us
            ),
            "finalRenderUs": stats(sample.final_render_us for sample in samples),
            "selectedBlockCopyUs": stats(
                sample.copy_selected_block_us for sample in samples
            ),
            "semanticOrTestQueryUs": stats(
                sample.semantic_or_test_query_us for sample in samples
            ),
            "unsafeFrameCount": unsafe_frame_count,
            "rssDeltaBytes": max(sample.rss_delta_bytes for sample in samples),
            "initialFrameProbeUs": stats(
                sample.initial_frame_probe_us for sample in samples
            ),
            "lineOfCodeCount": app_lines,
            "testLineOfCodeCount": test_lines,
            "chunkCount": last.chunk_count,
            "sourceByteCount": last.source_byte_count,
            "blockCount": last.block_count,
            "headingCount": last.heading_count,
            "listItemCount": last.list_item_count,
            "linkCount": last.link_count,
            "unsafeLinkCount": last.unsafe_link_count,
            "codeBlockCount": last.code_block_count,
            "codeLineCount": last.code_line_count,
            "selectedBlockIndex": last.selected_block_index,
            "selectedBlockKind": last.selected_block_kind,
            "sanitizedBlockCount": last.sanitized_block_count,
            "sanitizedChunkCount": last.sanitized_chunk_count,
            "truncatedBlockCount": last.truncated_block_count,
            "copiedByteCount": last.copied_byte_count,
        },
        "correctness": [
            {
                "gate": "incremental content remains coherent",
                "pass": all(sample.incremental_content_coherent for sample in samples),
                "evidence": (
                    "The streamed document retained headings, lists, links, unsafe-link "
                    "fallback metadata, code fences, selected final block, and non-empty copy text."
                ),
            },
            {
                "gate": "unsafe links have visible fallback",
                "pass": all(
                    sample.unsafe_links_have_visible_fallback for sample in samples
                ),
                "evidence": (
                    "Fixture-owned link policy rewrote unsafe links to a blocked href "
                    "while preserving the original URL in visible text."
                ),
            },
            {
                "gate": "unsafe frame count is zero",
                "pass": unsafe_frame_count == 0
                and all(sample.unsafe_frame_free for sample in samples),
                "evidence": (
                    "Fixture-owned sanitizer removed OSC/CSI/control payloads and "
                    "redacted secret-shaped text before Textual Markdown ingestion."
                ),
            },
        ],
        "ergonomics": {
            "lineOfCodeCount": app_lines,
            "testLineOfCodeCount": test_lines,
            "appFile": "sb5_markdown_app.py",
            "testFile": "test_sb5_markdown.py",
            "peerOwnedMarkdownWidget": True,
            "peerOwnedMarkdownAppend": True,
            "appOwnedSanitization": True,
            "appOwnedLinkPolicy": True,
            "appOwnedSelectedBlockCopy": True,
            "appOwnedMarkdownMetadata": True,
            "semanticGraphAvailable": False,
            "testQueryViaWidgetAndAppState": True,
        },
        "artifacts": [
            {
                "kind": "source",
                "path": "peer-fixtures/textual/sb5_streaming_markdown/sb5_markdown_app.py",
            },
            {
                "kind": "test",
                "path": "peer-fixtures/textual/sb5_streaming_markdown/test_sb5_markdown.py",
            },
        ],
        "notes": [
            "This is a Textual run_test peer fixture, not a real-terminal run.",
            "Textual 8.2.7 supplies the Markdown widget, append API, parser/rendering, focus, scrolling, and test harness.",
            "Sanitization/redaction, visible URL fallback for unsafe links, selected-block copy, and metadata/test query state are fixture-owned app code.",
            "Textual exposes widget/app state for this fixture, not a Fleury-style semantic app graph.",
            "chunkParseUs is fixture metadata parsing around the streamed source; Textual's internal parse/render work is included in chunkFrameUs and chunkUpdateUs.",
            "Timing is local-machine evidence and should not be used as a public superiority claim without repeated peer runs.",
        ],
    }


def parse_args() -> Options:
    parser = argparse.ArgumentParser()
    parser.add_argument("--warmup", type=positive_int_or_zero, default=DEFAULT_WARMUPS)
    parser.add_argument("--iterations", type=positive_int, default=DEFAULT_ITERATIONS)
    parser.add_argument("--rows", type=positive_int, default=DEFAULT_ROWS)
    parser.add_argument("--size", type=parse_size, default=DEFAULT_SIZE)
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
        wire=args.wire,
        wire_steps=args.steps,
        wire_interval_ms=args.interval_ms,
        size=args.size,
        print_json=args.json,
        output_path=args.output,
    )


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return parsed


def positive_int_or_zero(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be zero or positive")
    return parsed


def parse_size(value: str) -> tuple[int, int]:
    parts = value.lower().split("x", 1)
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("size must be COLUMNSxROWS")
    return positive_int(parts[0]), positive_int(parts[1])


def now_ns() -> int:
    return time.perf_counter_ns()


def elapsed_us(start_ns: int) -> int:
    return max(0, (time.perf_counter_ns() - start_ns) // 1_000)


def stats(values: Iterable[int]) -> dict[str, int]:
    ordered = sorted(values)
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


def percentile(values: list[int], fraction: float) -> int:
    if len(values) == 1:
        return values[0]
    index = math.ceil((len(values) - 1) * fraction)
    return values[min(index, len(values) - 1)]


def current_rss_bytes() -> int:
    usage = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    if sys.platform == "darwin":
        return int(usage)
    return int(usage) * 1024


def source_line_count(path: Path) -> int:
    count = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
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
