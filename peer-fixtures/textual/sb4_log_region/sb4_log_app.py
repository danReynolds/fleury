from __future__ import annotations

import re
from dataclasses import dataclass

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.widgets import Log

OSC_RE = re.compile(r"\x1b\].*?(?:\x07|\x1b\\)")
CSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
SECRET_RE = re.compile(r"secret-[A-Za-z0-9_-]+")


@dataclass(frozen=True)
class LogEntryRecord:
    source_index: int
    key: str
    text: str
    sanitized: bool


@dataclass(frozen=True)
class LogState:
    entry_count: int
    displayed_count: int
    line_count: int
    scroll_y: int
    max_scroll_y: int
    visible_window_rows: int
    selected_key: str
    tail_anchored: bool
    filtered_count: int
    filter_query: str
    unsafe_artifact_leak_count: int


def log_key(source_index: int) -> str:
    return f"LOG-{100_000 + source_index:06d}"


def append_filter_query(row_count: int) -> str:
    bucket = (100_000 + row_count) // 1_000
    return f"LOG-{bucket:03d}"


def unsafe_count_text(value: str) -> int:
    count = 0
    count += value.count("\x1b")
    count += len(SECRET_RE.findall(value))
    count += value.count("\x07")
    count += value.count("\n")
    count += value.count("\r")
    return count


def sanitize_log_text(raw: str) -> str:
    value = OSC_RE.sub("", raw)
    value = CSI_RE.sub("", value)
    value = SECRET_RE.sub("[redacted]", value)
    cleaned = []
    for character in value:
        code = ord(character)
        if character in ("\n", "\r", "\t") or code < 0x20:
            cleaned.append(" ")
        else:
            cleaned.append(character)
    return " ".join("".join(cleaned).split())


def expected_copied_text(source_index: int) -> str:
    return make_log_entry(source_index).text


def make_log_entry(source_index: int) -> LogEntryRecord:
    key = log_key(source_index)
    severity = "ERROR" if source_index % 17 == 0 else "WARN" if source_index % 7 == 0 else "INFO"
    payload = f"{key} {severity} worker-{source_index % 23} request={source_index} duration={20 + source_index % 900}ms"
    if source_index % 97 == 0:
        payload += f" \x1b[31mred\x1b[0m secret-{source_index} \x1b]52;c;clipboard-{source_index}\x07"
    if source_index % 211 == 0:
        payload += " multiline\ncontinued\rpayload"
    text = sanitize_log_text(payload)
    return LogEntryRecord(
        source_index=source_index,
        key=key,
        text=text,
        sanitized=text != payload,
    )


class Sb4LogRegionApp(App[None]):
    """Textual Log fixture for Fleury SB.4 peer comparison."""

    CSS = "Log { height: 1fr; }"
    BINDINGS = [
        Binding("end", "tail", "Scroll to tail", priority=True),
        Binding("ctrl+c", "copy_entry", "Copy selected entry", priority=True),
    ]

    def __init__(self, row_count: int = 100_000) -> None:
        super().__init__()
        self.row_count = row_count
        self.log_widget: Log | None = None
        self.entries: list[LogEntryRecord] = []
        self.displayed_entries: list[LogEntryRecord] = []
        self.filter_text = ""
        self.selected_source_index = 0
        self.last_copied_text = ""
        self.sanitized_fixture_rows = 0
        self._unsafe_artifact_leak_count = 0

    def compose(self) -> ComposeResult:
        self.log_widget = Log(id="log", auto_scroll=True, highlight=False)
        yield self.log_widget

    def on_mount(self) -> None:
        initial = [make_log_entry(index) for index in range(self.row_count)]
        self.entries = initial
        self.displayed_entries = initial
        self.sanitized_fixture_rows = sum(1 for entry in initial if entry.sanitized)
        self.selected_source_index = max(0, self.row_count - 1)
        self._append_to_log(initial)
        self._log_widget.scroll_end(animate=False, immediate=True)
        self._log_widget.focus()

    def append_burst(self, count: int) -> None:
        start = len(self.entries)
        appended = [make_log_entry(start + offset) for offset in range(count)]
        self.entries.extend(appended)
        self.displayed_entries = self.entries
        self.filter_text = ""
        self.sanitized_fixture_rows += sum(1 for entry in appended if entry.sanitized)
        self.selected_source_index = len(self.entries) - 1
        self._append_to_log(appended)
        self._log_widget.scroll_end(animate=False, immediate=True)

    def jump_to_scrollback(self, source_index: int) -> None:
        if not self.entries:
            return
        index = max(0, min(source_index, len(self.entries) - 1))
        self.filter_text = ""
        self.displayed_entries = self.entries
        self.selected_source_index = index
        self._log_widget.scroll_to(y=index, animate=False, immediate=True, force=True)

    def action_tail(self) -> None:
        self.scroll_to_tail()

    def scroll_to_tail(self) -> None:
        if not self.entries:
            return
        self.filter_text = ""
        self.displayed_entries = self.entries
        self.selected_source_index = len(self.entries) - 1
        self._log_widget.scroll_end(animate=False, immediate=True, force=True)

    def action_copy_entry(self) -> None:
        if not self.entries:
            self.last_copied_text = ""
            return
        self.last_copied_text = self.entries[self.selected_source_index].text
        self._unsafe_artifact_leak_count += unsafe_count_text(self.last_copied_text)

    def filter_query(self, query: str) -> int:
        self.filter_text = query
        matches = [entry for entry in self.entries if query in entry.text]
        self.displayed_entries = matches
        self._log_widget.clear()
        self._append_to_log(matches)
        if matches:
            self.selected_source_index = matches[-1].source_index
            self._log_widget.scroll_end(animate=False, immediate=True, force=True)
        return len(matches)

    @property
    def _log_widget(self) -> Log:
        if self.log_widget is None:
            raise RuntimeError("Log is not mounted.")
        return self.log_widget

    def state_snapshot(self) -> LogState:
        log = self._log_widget
        selected_key = ""
        if self.entries:
            selected_key = self.entries[self.selected_source_index].key
        return LogState(
            entry_count=len(self.entries),
            displayed_count=len(self.displayed_entries),
            line_count=log.line_count,
            scroll_y=int(log.scroll_y),
            max_scroll_y=int(log.max_scroll_y),
            visible_window_rows=int(log.scrollable_size.height),
            selected_key=selected_key,
            tail_anchored=self._tail_anchored(log),
            filtered_count=len(self.displayed_entries) if self.filter_text else 0,
            filter_query=self.filter_text,
            unsafe_artifact_leak_count=self._unsafe_artifact_leak_count,
        )

    def _append_to_log(self, entries: list[LogEntryRecord]) -> None:
        lines = [entry.text for entry in entries]
        self._unsafe_artifact_leak_count += sum(unsafe_count_text(line) for line in lines)
        self._log_widget.write_lines(lines, scroll_end=True)

    def _tail_anchored(self, log: Log) -> bool:
        if not self.entries:
            return True
        selected_tail = self.selected_source_index == len(self.entries) - 1
        scrolled_tail = abs(int(log.max_scroll_y) - int(log.scroll_y)) <= 1
        full_log_visible = not self.filter_text and log.line_count == len(self.entries)
        return selected_tail and scrolled_tail and full_log_visible
