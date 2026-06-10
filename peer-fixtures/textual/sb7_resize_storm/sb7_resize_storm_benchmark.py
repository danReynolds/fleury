from __future__ import annotations

import argparse
import asyncio

from textual.app import App, ComposeResult
from textual.widgets import Static


def main() -> None:
    options = parse_args()
    if options.wire:
        WireResizeStormApp(options).run()
    else:
        print("Textual SB.7 resize storm fixture: use --wire for PTY capture")


class WireResizeStormApp(App[None]):
    def __init__(self, options: argparse.Namespace) -> None:
        super().__init__()
        self.options = options
        self.step = 0

    def compose(self) -> ComposeResult:
        yield Static(self.render_body(), id="body")

    def on_mount(self) -> None:
        self.body = self.query_one("#body", Static)
        asyncio.create_task(self.drive())

    async def drive(self) -> None:
        await asyncio.sleep(self.options.interval_ms / 1000)
        while self.step < self.options.steps:
            self.step += 1
            self.body.update(self.render_body())
            await asyncio.sleep(self.options.interval_ms / 1000)
        self.exit()

    def render_body(self) -> str:
        width, height = self.size
        visible_logs = max(2, min(10, height // 3))
        visible_rows = max(3, min(14, height - visible_logs - 4))
        lines = [
            f"SB.7 resize step={self.step} rows={self.options.rows} size={width}x{height}",
            "filter status:failed",
            "",
        ]
        for row in range(visible_rows):
            index = (self.step * 7 + row) % self.options.rows
            lines.append(
                f"RUN-{100000 + index} {status(index):8} owner={owner(index):5} "
                f"duration={index % 3:02d}:{index % 60:02d} Resize shard {index % 2048}"
            )
        lines.append("")
        for row in range(visible_logs):
            index = self.step * visible_logs + row
            unsafe = f" secret-{index} payload" if index % 17 == 0 else ""
            lines.append(
                f"resize log {index} shard={index % 31} status={status(index)}{unsafe}"
            )
        return "\n".join(lines)


def status(row: int) -> str:
    return ["queued", "running", "passed", "failed", "blocked"][row % 5]


def owner(row: int) -> str:
    return ["agent", "ops", "qa", "infra", "cli"][row % 5]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wire", action="store_true")
    parser.add_argument("--rows", type=positive_int, default=100_000)
    parser.add_argument("--steps", type=positive_int, default=8)
    parser.add_argument("--interval-ms", type=positive_int, default=80)
    parser.add_argument("--size", default="120x32")
    return parser.parse_args()


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("expected a positive integer")
    return parsed


if __name__ == "__main__":
    main()
