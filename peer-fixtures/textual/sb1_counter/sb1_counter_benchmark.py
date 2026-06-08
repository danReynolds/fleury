from __future__ import annotations

import argparse
import asyncio

from textual.app import App, ComposeResult
from textual.widgets import Static


def main() -> None:
    options = parse_args()
    if options.wire:
        WireCounterApp(options).run()
    else:
        print("Textual SB.1 counter fixture: use --wire for PTY capture")


class WireCounterApp(App[None]):
    def __init__(self, options: argparse.Namespace) -> None:
        super().__init__()
        self.options = options
        self.count = 0

    def compose(self) -> ComposeResult:
        yield Static(self.render_body(), id="counter")

    def on_mount(self) -> None:
        self.counter = self.query_one("#counter", Static)
        asyncio.create_task(self.drive())

    async def drive(self) -> None:
        await asyncio.sleep(self.options.interval_ms / 1000)
        while self.count < self.options.steps:
            self.count += 1
            self.counter.update(self.render_body())
            if self.count >= self.options.steps:
                break
            await asyncio.sleep(self.options.interval_ms / 1000)
        self.exit()

    def render_body(self) -> str:
        return f"Count: {self.count}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wire", action="store_true")
    parser.add_argument("--rows", type=positive_int, default=1)
    parser.add_argument("--steps", type=positive_int, default=1)
    parser.add_argument("--interval-ms", type=positive_int, default=60)
    parser.add_argument("--size", default="120x32")
    return parser.parse_args()


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("expected a positive integer")
    return parsed


if __name__ == "__main__":
    main()
