from __future__ import annotations

import argparse
import asyncio
import math

from textual.app import App, ComposeResult
from textual.widgets import Static, Tree


def main() -> None:
    options = parse_args()
    if options.wire:
        WireTreeTableApp(options).run()
    else:
        print("Textual SB.11 TreeTable/filter/copy fixture: use --wire for PTY capture")


class WireTreeTableApp(App[None]):
    def __init__(self, options: argparse.Namespace) -> None:
        super().__init__()
        self.options = options
        self.step = 0
        self.selected = 1
        self.filtering = False
        self.copied_bytes = 0
        self.group_size = max(1, min(1000, options.rows))
        self.group_count = math.ceil(options.rows / self.group_size)

    def compose(self) -> ComposeResult:
        yield Static(self.header_text(), id="header")
        yield Tree("components", id="tree")

    def on_mount(self) -> None:
        self.header = self.query_one("#header", Static)
        self.tree = self.query_one("#tree", Tree)
        self.tree.show_root = False
        self.refresh_tree()
        asyncio.create_task(self.drive())

    async def drive(self) -> None:
        await asyncio.sleep(self.options.interval_ms / 1000)
        while self.step < self.options.steps:
            mode = self.step % 6
            if mode == 0:
                self.selected = self.group_size + 1
            elif mode == 1:
                self.selected = min(self.visible_row_count() - 1, self.selected + 20)
            elif mode == 2:
                self.selected = self.visible_row_count() - 1
            elif mode == 3:
                self.filtering = True
                self.selected = 1
            elif mode == 4:
                self.copied_bytes = len(self.copy_selected_row().encode("utf-8"))
            elif mode == 5:
                self.filtering = False
                self.selected = 1
            self.step += 1
            self.header.update(self.header_text())
            self.refresh_tree()
            await asyncio.sleep(self.options.interval_ms / 1000)
        self.exit()

    def header_text(self) -> str:
        query = target_query(self.options.rows) if self.filtering else "none"
        return (
            f"SB.11 tree step={self.step} rows={self.options.rows} "
            f"filter={query} copied={self.copied_bytes}"
        )

    def refresh_tree(self) -> None:
        self.tree.clear()
        if self.filtering:
            group = self.tree.root.add(group_line(self.group_count - 1), expand=True)
            group.add_leaf(row_line(self.options.rows - 1, target_rows=self.options.rows))
            return

        first_group = self.tree.root.add(group_line(0), expand=True)
        for row in range(0, min(12, self.options.rows)):
            first_group.add_leaf(
                row_line(
                    row,
                    selected=self.selected == row + 1,
                    target_rows=self.options.rows,
                )
            )

        if self.group_count > 1:
            second_group = self.tree.root.add(group_line(1), expand=True)
            start = self.group_size
            for row in range(start, min(start + 10, self.options.rows)):
                second_group.add_leaf(
                    row_line(
                        row,
                        selected=self.selected == row + 2,
                        target_rows=self.options.rows,
                    )
                )

        if self.selected >= self.visible_row_count() - 2:
            last_group_index = self.group_count - 1
            last_group = self.tree.root.add(group_line(last_group_index), expand=True)
            start = max(0, self.options.rows - 8)
            for row in range(start, self.options.rows):
                last_group.add_leaf(
                    row_line(
                        row,
                        selected=row == self.options.rows - 1,
                        target_rows=self.options.rows,
                    )
                )

    def visible_row_count(self) -> int:
        expanded_leaf_count = min(self.options.rows, self.group_size * min(2, self.group_count))
        return min(self.group_count + expanded_leaf_count, self.options.rows + self.group_count)

    def copy_selected_row(self) -> str:
        row = self.options.rows - 1 if self.filtering else min(self.options.rows - 1, self.selected)
        return (
            "Component\tStatus\tOwner\tDuration\tNotes\n"
            f"{leaf_key(row)}\t{status(row)}\t{owner(row)}\t{duration(row)}\t{notes(row)}"
        )


def group_line(group: int) -> str:
    count = "1000" if group >= 0 else "0"
    return f"GROUP-{group:03d} ready owner={owner(group)} duration={group % 7:02d}:00 {count} tasks"


def row_line(row: int, *, selected: bool = False, target_rows: int) -> str:
    marker = ">" if selected else " "
    unsafe = f" unsafe secret-{row} payload" if row % 97 == 0 else ""
    target = f" {target_query(target_rows)}" if row == target_rows - 1 else ""
    return (
        f"{marker} {leaf_key(row)} {status(row):8} {owner(row):5} "
        f"{duration(row):>5} {notes(row)}{target}{unsafe}"
    )


def leaf_key(row: int) -> str:
    return f"TASK-{100000 + row}"


def target_query(rows: int) -> str:
    return f"zz-target-{100000 + rows - 1}"


def status(row: int) -> str:
    return ["queued", "running", "passed", "failed", "blocked"][row % 5]


def owner(row: int) -> str:
    return ["agent", "ops", "qa", "infra", "cli"][row % 5]


def duration(row: int) -> str:
    return f"{row % 4:02d}:{row % 60:02d}"


def notes(row: int) -> str:
    return f"shard {row % 4096} {['core', 'widgets', 'unicode', 'deploy'][row % 4]}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wire", action="store_true")
    parser.add_argument("--rows", type=positive_int, default=100_000)
    parser.add_argument("--steps", type=positive_int, default=6)
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
