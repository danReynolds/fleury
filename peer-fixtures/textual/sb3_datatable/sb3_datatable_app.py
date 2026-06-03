from __future__ import annotations

from dataclasses import dataclass

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.widgets import DataTable


ColumnSpec = tuple[str, str, int]

COLUMNS: tuple[ColumnSpec, ...] = (
    ("id", "ID", 12),
    ("status", "Status", 8),
    ("title", "Title", 24),
    ("owner", "Owner", 12),
    ("duration", "Duration", 10),
    ("progress", "Progress", 8),
    ("warnings", "Warnings", 8),
    ("updated", "Updated", 14),
)


@dataclass(frozen=True)
class TableState:
    row_count: int
    cursor_row: int
    selected_row_id: str
    scroll_y: int
    max_scroll_y: int
    visible_window_rows: int
    virtual_height: int


def row_id(index: int) -> str:
    return f"RUN-{index:06d}"


def row_key(index: int) -> str:
    return f"run-{index:06d}"


def row_values(index: int) -> tuple[str, str, str, str, str, str, str, str]:
    return (
        row_id(index),
        "failed" if index % 5 == 0 else "ok",
        f"Build pipeline {index}",
        f"user-{index % 17}",
        f"{30 + index % 400}s",
        f"{index % 101}%",
        str(index % 4),
        f"2026-06-{1 + index % 28:02d}",
    )


def sanitize_tsv_cell(value: object) -> str:
    return str(value).replace("\t", " ").replace("\n", " ").replace("\r", " ")


def expected_selected_tsv(index: int) -> str:
    return tsv_for_row(row_values(index))


def tsv_for_row(row: tuple[object, ...] | list[object]) -> str:
    headings = "\t".join(column[1] for column in COLUMNS)
    cells = "\t".join(sanitize_tsv_cell(value) for value in row)
    return f"{headings}\n{cells}"


class Sb3DataTableApp(App[None]):
    """Textual DataTable fixture for Fleury SB.3 peer comparison."""

    CSS = "DataTable { height: 1fr; }"
    BINDINGS = [
        Binding("end", "jump_end", "Jump to final row", priority=True),
        Binding("ctrl+c", "copy_row", "Copy selected row", priority=True),
    ]

    def __init__(self, row_count: int = 100_000) -> None:
        super().__init__()
        self.row_count = row_count
        self.table: DataTable | None = None
        self.last_copied_tsv = ""

    def compose(self) -> ComposeResult:
        self.table = DataTable(
            id="table",
            cursor_type="row",
            fixed_rows=1,
            zebra_stripes=True,
        )
        yield self.table

    def on_mount(self) -> None:
        table = self._table
        for key, title, width in COLUMNS:
            table.add_column(title, key=key, width=width)
        for index in range(self.row_count):
            table.add_row(*row_values(index), key=row_key(index))
        table.focus()

    def action_jump_end(self) -> None:
        self._table.move_cursor(
            row=self.row_count - 1,
            column=0,
            animate=False,
            scroll=True,
        )

    def action_copy_row(self) -> None:
        table = self._table
        row = table.get_row_at(table.cursor_coordinate.row)
        self.last_copied_tsv = tsv_for_row(row)

    @property
    def _table(self) -> DataTable:
        if self.table is None:
            raise RuntimeError("DataTable is not mounted.")
        return self.table

    def state_snapshot(self) -> TableState:
        table = self._table
        cursor_row = table.cursor_coordinate.row
        row = table.get_row_at(cursor_row)
        return TableState(
            row_count=table.row_count,
            cursor_row=cursor_row,
            selected_row_id=str(row[0]),
            scroll_y=int(table.scroll_y),
            max_scroll_y=int(table.max_scroll_y),
            visible_window_rows=int(table.scrollable_size.height),
            virtual_height=int(table.virtual_size.height),
        )
