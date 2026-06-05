from __future__ import annotations

import argparse
import asyncio

from textual.app import App, ComposeResult
from textual.widgets import Static


def main() -> None:
    options = parse_args()
    if options.wire:
        WireSubprocessApp(options).run()
    else:
        print("Textual SB.9 subprocess output fixture: use --wire for PTY capture")


class WireSubprocessApp(App[None]):
    def __init__(self, options: argparse.Namespace) -> None:
        super().__init__()
        self.options = options
        self.step = 0
        self.lines = [line_for(index) for index in range(16)]

    def compose(self) -> ComposeResult:
        yield Static(self.render_body(), id="body")

    def on_mount(self) -> None:
        self.body = self.query_one("#body", Static)
        asyncio.create_task(self.drive())

    async def drive(self) -> None:
        await asyncio.sleep(self.options.interval_ms / 1000)
        while self.step < self.options.steps:
            for _ in range(4):
                self.lines.append(line_for(len(self.lines)))
            self.lines = self.lines[-24:]
            self.step += 1
            self.body.update(self.render_body())
            await asyncio.sleep(self.options.interval_ms / 1000)
        self.exit()

    def render_body(self) -> str:
        return "\n".join(
            [f"SB.9 subprocess output step={self.step} total={len(self.lines)}", ""]
            + self.lines
        )


def line_for(index: int) -> str:
    unsafe = f" secret-{index}" if index % 5 == 0 else ""
    return (
        f"proc[{index}] stdout shard={index % 17} status={index % 3} "
        f'message="streamed output {index}"{unsafe}'
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wire", action="store_true")
    parser.add_argument("--rows", type=positive_int, default=400)
    parser.add_argument("--steps", type=positive_int, default=10)
    parser.add_argument("--interval-ms", type=positive_int, default=35)
    parser.add_argument("--size", default="120x32")
    return parser.parse_args()


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("expected a positive integer")
    return parsed


if __name__ == "__main__":
    main()
