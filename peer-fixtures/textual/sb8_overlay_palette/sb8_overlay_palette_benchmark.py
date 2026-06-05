from __future__ import annotations

import argparse
import asyncio

from textual.app import App, ComposeResult
from textual.widgets import Static


def main() -> None:
    options = parse_args()
    if options.wire:
        WireOverlayApp(options).run()
    else:
        print("Textual SB.8 overlay/palette fixture: use --wire for PTY capture")


class WireOverlayApp(App[None]):
    def __init__(self, options: argparse.Namespace) -> None:
        super().__init__()
        self.options = options
        self.step = 0
        self.query = "open"
        self.palette_open = True

    def compose(self) -> ComposeResult:
        yield Static(self.render_body(), id="body")

    def on_mount(self) -> None:
        self.body = self.query_one("#body", Static)
        asyncio.create_task(self.drive())

    async def drive(self) -> None:
        await asyncio.sleep(self.options.interval_ms / 1000)
        while self.step < self.options.steps:
            self.palette_open = self.step % 3 != 2
            self.query = ["open", "run", "diag", "copy"][self.step % 4]
            self.step += 1
            self.body.update(self.render_body())
            await asyncio.sleep(self.options.interval_ms / 1000)
        self.exit()

    def render_body(self) -> str:
        lines = [
            f"SB.8 overlay churn step={self.step} open={self.palette_open} query={self.query}",
            "",
        ]
        for index in range(9):
            command_index = (self.step + index) % self.options.rows
            lines.append(
                f"screen row {index} focus={index == self.step % 9} command=cmd-{command_index}"
            )
        if self.palette_open:
            lines.extend(["", "+" + "-" * 54 + "+"])
            lines.append(f"| Command Palette query={self.query:<26} |")
            for index in range(6):
                command_index = (self.step * 7 + index) % self.options.rows
                lines.append(f"| cmd-{command_index:04d} {self.query} action-{index:<31} |")
            lines.append("+" + "-" * 54 + "+")
        return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wire", action="store_true")
    parser.add_argument("--rows", type=positive_int, default=500)
    parser.add_argument("--steps", type=positive_int, default=12)
    parser.add_argument("--interval-ms", type=positive_int, default=40)
    parser.add_argument("--size", default="120x32")
    return parser.parse_args()


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("expected a positive integer")
    return parsed


if __name__ == "__main__":
    main()
