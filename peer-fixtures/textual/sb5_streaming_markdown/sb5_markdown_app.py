from __future__ import annotations

import re
from dataclasses import dataclass

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.widgets import Markdown

OSC_RE = re.compile(r"\x1b\].*?(?:\x07|\x1b\\)")
CSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
SECRET_RE = re.compile(r"secret-[A-Za-z0-9_-]+")
LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")
ORDERED_RE = re.compile(r"^\s*\d+\.\s+")

SAFE_SCHEMES = {"http", "https", "mailto"}


@dataclass(frozen=True)
class MarkdownState:
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
    scroll_y: int
    max_scroll_y: int
    visible_window_rows: int
    unsafe_artifact_leak_count: int
    sanitized_block_count: int
    sanitized_chunk_count: int
    truncated_block_count: int
    copied_byte_count: int
    unsafe_links_have_visible_fallback: bool


@dataclass(frozen=True)
class MarkdownBlockRecord:
    index: int
    kind: str
    source_text: str
    sanitized: bool
    truncated: bool


@dataclass(frozen=True)
class MarkdownDocumentRecord:
    source: str
    blocks: list[MarkdownBlockRecord]
    heading_count: int
    list_item_count: int
    link_count: int
    unsafe_link_count: int
    code_block_count: int
    code_line_count: int
    unsafe_links_have_visible_fallback: bool


class MarkdownFixture:
    def __init__(self, seed: int = 1) -> None:
        self.seed = seed

    def chunk(self, index: int) -> str:
        chunk_id = index + self.seed
        section = index // 12
        match index % 12:
            case 0:
                return f"## Stream batch {section}\n"
            case 1:
                return f"Paragraph {chunk_id} starts with **bold** text, "
            case 2:
                return (
                    f"[docs-{chunk_id}](https://fleury.dev/docs/{chunk_id}), "
                    "`inline-code`, and mixed width text.\n"
                )
            case 3:
                return f"- checklist item {chunk_id} keeps semantic list state\n"
            case 4:
                return (
                    "| field | value |\n"
                    "| --- | --- |\n"
                    f"| chunk | {chunk_id} |\n"
                )
            case 5:
                return (
                    "```dart\n"
                    f'final chunk{chunk_id} = "safe";\n'
                    f'final hidden{chunk_id} = "\x1b]52;c;secret-{chunk_id}\x07";\n'
                )
            case 6:
                return f"print(chunk{chunk_id});\n```\n"
            case 7:
                return (
                    f"> quoted output {chunk_id} "
                    f"\x1b]52;c;secret-{chunk_id}\x07 stays inert\n"
                )
            case 8:
                return (
                    f"1. ordered item {chunk_id} with "
                    f"[mail](mailto:ops{chunk_id}@example.com)\n"
                )
            case 9:
                return "\n"
            case 10:
                return f"{long_markdown_paragraph(chunk_id)}\n"
            case _:
                return (
                    f"[unsafe-{chunk_id}](javascript:alert({chunk_id})) "
                    "visible fallback only\n"
                )


def long_markdown_paragraph(chunk_id: int) -> str:
    words = [f"word{(chunk_id + offset) % 17}" for offset in range(24)]
    return (
        f"Long paragraph {chunk_id} "
        + " ".join(words)
        + " with ~~strike~~ and _emphasis_."
    )


def markdown_chunk_count_for(row_count: int) -> int:
    scaled = row_count // 100
    if scaled < 64:
        return 64
    if scaled > 1024:
        return 1024
    return scaled


def unsafe_count_text(value: str) -> int:
    count = value.count("\x1b")
    count += len(SECRET_RE.findall(value))
    count += value.count("\x07")
    count += value.count("\r")
    return count


def sanitize_markdown_chunk(raw: str) -> str:
    value = OSC_RE.sub("", raw)
    value = CSI_RE.sub("", value)
    value = SECRET_RE.sub("[redacted]", value)
    cleaned = []
    for character in value:
        code = ord(character)
        if character in ("\r", "\t") or (code < 0x20 and character != "\n"):
            cleaned.append(" ")
        else:
            cleaned.append(character)
    return _rewrite_links_with_visible_fallback("".join(cleaned))


def _rewrite_links_with_visible_fallback(value: str) -> str:
    lines = value.splitlines(keepends=True)
    in_code = False
    output = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("```"):
            in_code = not in_code
            output.append(line)
            continue
        if in_code:
            output.append(line)
            continue

        def replace(match: re.Match[str]) -> str:
            label = match.group(1)
            url = match.group(2)
            scheme = url_scheme(url)
            if scheme in SAFE_SCHEMES:
                return f"[{label}]({url}) ({url})"
            return f"[{label}](#blocked) (unsafe link: {url})"

        output.append(LINK_RE.sub(replace, line))
    return "".join(output)


def url_scheme(url: str) -> str:
    index = url.find(":")
    if index <= 0:
        return ""
    return url[:index].lower()


def parse_markdown_document(source: str, max_line_length: int = 1000) -> MarkdownDocumentRecord:
    blocks: list[MarkdownBlockRecord] = []
    heading_count = 0
    list_item_count = 0
    link_count = 0
    unsafe_link_count = 0
    code_block_count = 0
    code_line_count = 0
    unsafe_links_have_visible_fallback = True
    in_code = False
    current_code: list[str] = []

    def add_block(kind: str, text: str, sanitized: bool = False) -> None:
        nonlocal heading_count, list_item_count
        if kind == "blank":
            return
        truncated = len(text) > max_line_length
        blocks.append(
            MarkdownBlockRecord(
                index=len(blocks),
                kind=kind,
                source_text=text[:max_line_length],
                sanitized=sanitized,
                truncated=truncated,
            )
        )
        if kind == "heading":
            heading_count += 1
        if kind in {"bullet", "ordered"}:
            list_item_count += 1

    for line in source.splitlines():
        stripped = line.strip()
        if stripped.startswith("```"):
            if in_code:
                add_block("codeFence", "\n".join(current_code), sanitized=False)
                current_code = []
            else:
                code_block_count += 1
            in_code = not in_code
            continue
        if in_code:
            code_line_count += 1
            current_code.append(line)
            continue

        for match in LINK_RE.finditer(line):
            link_count += 1
            url = match.group(2)
            scheme = url_scheme(url)
            if scheme not in SAFE_SCHEMES and url != "#blocked":
                unsafe_link_count += 1
                unsafe_links_have_visible_fallback = False
        if "(unsafe link:" in line:
            unsafe_link_count += line.count("(unsafe link:")

        if not stripped:
            add_block("blank", "")
        elif stripped.startswith("#"):
            add_block("heading", line)
        elif stripped.startswith(("- ", "* ")):
            add_block("bullet", line)
        elif ORDERED_RE.match(line):
            add_block("ordered", line)
        elif stripped.startswith(">"):
            add_block("blockquote", line)
        elif stripped.startswith("|"):
            add_block("tableRow", line)
        else:
            add_block("paragraph", line)

    if in_code and current_code:
        add_block("codeFence", "\n".join(current_code), sanitized=False)

    return MarkdownDocumentRecord(
        source=source,
        blocks=blocks,
        heading_count=heading_count,
        list_item_count=list_item_count,
        link_count=link_count,
        unsafe_link_count=unsafe_link_count,
        code_block_count=code_block_count,
        code_line_count=code_line_count,
        unsafe_links_have_visible_fallback=unsafe_links_have_visible_fallback,
    )


class Sb5StreamingMarkdownApp(App[None]):
    """Textual Markdown fixture for Fleury SB.5 peer comparison."""

    CSS = "Markdown { height: 1fr; }"
    BINDINGS = [Binding("ctrl+c", "copy_block", "Copy selected block", priority=True)]

    def __init__(self) -> None:
        super().__init__()
        self.markdown_widget: Markdown | None = None
        self.source = ""
        self.document = parse_markdown_document("")
        self.chunk_count = 0
        self.selected_block_index = 0
        self.last_copied_text = ""
        self.sanitized_chunk_count = 0
        self._unsafe_artifact_leak_count = 0

    def compose(self) -> ComposeResult:
        self.markdown_widget = Markdown("", id="markdown", open_links=False)
        yield self.markdown_widget

    def on_mount(self) -> None:
        self._markdown.focus()

    async def append_chunk(self, raw_chunk: str) -> None:
        chunk = sanitize_markdown_chunk(raw_chunk)
        if chunk != raw_chunk:
            self.sanitized_chunk_count += 1
        self._unsafe_artifact_leak_count += unsafe_count_text(chunk)
        self.source += chunk
        self.chunk_count += 1
        self.document = parse_markdown_document(self.source)
        await self._markdown.append(chunk)

    def select_final_block(self) -> None:
        self.selected_block_index = max(0, len(self.document.blocks) - 1)
        self._markdown.scroll_end(animate=False, immediate=True, force=True)

    def action_copy_block(self) -> None:
        self.copy_selected_block()

    def copy_selected_block(self) -> str:
        if not self.document.blocks:
            self.last_copied_text = ""
            return self.last_copied_text
        index = max(0, min(self.selected_block_index, len(self.document.blocks) - 1))
        self.last_copied_text = self.document.blocks[index].source_text
        self._unsafe_artifact_leak_count += unsafe_count_text(self.last_copied_text)
        return self.last_copied_text

    @property
    def _markdown(self) -> Markdown:
        if self.markdown_widget is None:
            raise RuntimeError("Markdown is not mounted.")
        return self.markdown_widget

    def state_snapshot(self) -> MarkdownState:
        markdown = self._markdown
        selected = None
        if self.document.blocks:
            selected = self.document.blocks[
                max(0, min(self.selected_block_index, len(self.document.blocks) - 1))
            ]
        return MarkdownState(
            chunk_count=self.chunk_count,
            source_byte_count=len(self.document.source.encode("utf-8")),
            block_count=len(self.document.blocks),
            heading_count=self.document.heading_count,
            list_item_count=self.document.list_item_count,
            link_count=self.document.link_count,
            unsafe_link_count=self.document.unsafe_link_count,
            code_block_count=self.document.code_block_count,
            code_line_count=self.document.code_line_count,
            selected_block_index=self.selected_block_index,
            selected_block_kind=selected.kind if selected is not None else "",
            scroll_y=int(markdown.scroll_y),
            max_scroll_y=int(markdown.max_scroll_y),
            visible_window_rows=int(markdown.scrollable_size.height),
            unsafe_artifact_leak_count=self._unsafe_artifact_leak_count,
            sanitized_block_count=sum(1 for block in self.document.blocks if block.sanitized),
            sanitized_chunk_count=self.sanitized_chunk_count,
            truncated_block_count=sum(1 for block in self.document.blocks if block.truncated),
            copied_byte_count=len(self.last_copied_text.encode("utf-8")),
            unsafe_links_have_visible_fallback=self.document.unsafe_links_have_visible_fallback,
        )
