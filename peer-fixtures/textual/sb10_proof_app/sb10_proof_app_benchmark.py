from __future__ import annotations

import argparse
import asyncio

from textual.app import App, ComposeResult
from textual.widgets import Static


SCREENS = ["home", "search", "task", "logs", "diagnostics"]


def main() -> None:
    options = parse_args()
    if options.wire:
        WireProofApp(options).run()
    else:
        print("Textual SB.10 proof app fixture: use --wire for PTY capture")


class WireProofApp(App[None]):
    def __init__(self, options: argparse.Namespace) -> None:
        super().__init__()
        self.options = options
        self.step = 0
        self.active_screen = "home"
        self.events = ["boot proof app"]

    def compose(self) -> ComposeResult:
        yield Static(self.render_body(), id="body")

    def on_mount(self) -> None:
        self.body = self.query_one("#body", Static)
        asyncio.create_task(self.drive())

    async def drive(self) -> None:
        await asyncio.sleep(self.options.interval_ms / 1000)
        while self.step < self.options.steps:
            self.active_screen = SCREENS[self.step % len(SCREENS)]
            self.events.append(
                f"step={self.step} screen={self.active_screen} rows={self.options.rows}"
            )
            self.events = self.events[-12:]
            self.step += 1
            self.body.update(self.render_body())
            await asyncio.sleep(self.options.interval_ms / 1000)
        self.exit()

    def render_body(self) -> str:
        lines = [
            f"SB.10 proof app screen={self.active_screen} step={self.step}",
            "",
            f"nav: home search task  command: {command_name(self.active_screen):<14} status: {status(self.step)}",
            "",
            f"results visible={(self.step * 17) % self.options.rows} selected={self.step % 9}",
            "",
        ]
        lines.extend(self.events)
        return "\n".join(lines)


def command_name(screen: str) -> str:
    return {
        "home": "open-palette",
        "search": "rank-results",
        "task": "run-process",
        "logs": "copy-log",
    }.get(screen, "diagnose")


def status(step: int) -> str:
    return ["idle", "running", "complete", "warning"][step % 4]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wire", action="store_true")
    parser.add_argument("--rows", type=positive_int, default=1000)
    parser.add_argument("--steps", type=positive_int, default=10)
    parser.add_argument("--interval-ms", type=positive_int, default=50)
    parser.add_argument("--size", default="120x32")
    return parser.parse_args()


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("expected a positive integer")
    return parsed


if __name__ == "__main__":
    main()
