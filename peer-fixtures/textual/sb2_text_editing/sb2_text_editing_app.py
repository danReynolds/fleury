from __future__ import annotations

from dataclasses import dataclass

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.suggester import SuggestFromList
from textual.widgets import Input, Label, TextArea


PASTE_MARKER = "SB2_PASTE_MARKER"
SELECTION_REPLACEMENT = "[edited]"


@dataclass(frozen=True)
class TextFixture:
    composer_text: str
    editor_text: str
    secret_text: str
    paste_text: str
    paste_marker: str
    selection_replacement: str
    history_entries: tuple[str, ...]
    history_draft: str


@dataclass(frozen=True)
class EditingState:
    editor_text_length: int
    composer_text: str
    secret_visible_value: str
    cursor_location: tuple[int, int]
    selected_text: str
    completion_accepted: bool
    history_index: int | None
    contains_paste_marker: bool
    contains_cjk: bool
    contains_emoji: bool
    contains_combining: bool
    raw_secret_in_display: bool
    password_input_mode: bool


def generate_fixture(text_chars: int = 10_000) -> TextFixture:
    return TextFixture(
        composer_text="deploy service --target staging",
        editor_text=mixed_text(
            target_chars=text_chars,
            seed=42,
            line_prefix="editor",
            include_newlines=True,
        ),
        secret_text="textual-secret-do-not-leak",
        paste_text=(
            f"{PASTE_MARKER} "
            f"{mixed_text(target_chars=4096, seed=77, line_prefix='paste', include_newlines=False)}"
        ),
        paste_marker=PASTE_MARKER,
        selection_replacement=SELECTION_REPLACEMENT,
        history_entries=(
            "status --json",
            "logs --tail",
            "deploy --dry-run",
        ),
        history_draft="draft command",
    )


def mixed_text(
    *,
    target_chars: int,
    seed: int,
    line_prefix: str,
    include_newlines: bool,
) -> str:
    emoji = "\U0001f642"
    cjk = "\u6f22\u5b57"
    combining = "e\u0301"
    long_token = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    parts: list[str] = []
    index = 0
    while sum(len(part) for part in parts) < target_chars:
        lane = (index + seed) % 5
        parts.append(f"{line_prefix}-{index} ")
        if lane == 0:
            parts.append(f"ascii-{long_token} ")
        elif lane == 1:
            parts.append(f"emoji-{emoji} ")
        elif lane == 2:
            parts.append(f"cjk-{cjk} ")
        elif lane == 3:
            parts.append(f"combining-{combining} ")
        else:
            parts.append(f"wide-{cjk}-{emoji}-{combining} ")
        if include_newlines and index % 8 == 7:
            parts.append("\n")
        index += 1
    return "".join(parts)[:target_chars]


class Sb2TextEditingApp(App[None]):
    """Textual text editing fixture for Fleury SB.2 peer comparison."""

    CSS = """
    Screen { layout: vertical; }
    TextArea { height: 1fr; }
    Input { width: 1fr; }
    """

    BINDINGS = [
        Binding("up", "history_previous", "Previous history", priority=True),
        Binding("down", "history_next", "Next history", priority=True),
        Binding("tab", "accept_completion", "Accept completion", priority=True),
    ]

    def __init__(self, fixture: TextFixture | None = None) -> None:
        super().__init__()
        self.fixture = fixture or generate_fixture()
        self.editor: TextArea | None = None
        self.composer: Input | None = None
        self.secret: Input | None = None
        self.completion_accepted = False
        self.history_index: int | None = None
        self._history_draft: str | None = None

    def compose(self) -> ComposeResult:
        yield Label("Textual SB.2 Text Editing")
        self.composer = Input(
            value=self.fixture.composer_text,
            placeholder="Command composer",
            suggester=SuggestFromList(["git checkout", "deploy service", "logs --tail"]),
            id="composer",
        )
        yield self.composer
        self.editor = TextArea(
            self.fixture.editor_text,
            id="editor",
            show_line_numbers=False,
            max_checkpoints=200,
        )
        yield self.editor
        self.secret = Input(
            value=self.fixture.secret_text,
            password=True,
            id="secret",
            placeholder="Secret token",
        )
        yield self.secret

    def on_mount(self) -> None:
        self._editor.focus()
        self._editor.move_cursor(self._editor.document.end)

    def action_history_previous(self) -> None:
        if not self.composer or self.focused is not self.composer:
            return
        if not self.fixture.history_entries:
            return
        self._history_draft = self._history_draft or self.composer.value
        if self.history_index is None:
            self.history_index = len(self.fixture.history_entries) - 1
        else:
            self.history_index = max(0, self.history_index - 1)
        self.composer.value = self.fixture.history_entries[self.history_index]
        self.composer.cursor_position = len(self.composer.value)

    def action_history_next(self) -> None:
        if not self.composer or self.focused is not self.composer:
            return
        if self.history_index is None:
            return
        if self.history_index >= len(self.fixture.history_entries) - 1:
            self.composer.value = self._history_draft or ""
            self.composer.cursor_position = len(self.composer.value)
            self.history_index = None
            self._history_draft = None
            return
        self.history_index += 1
        self.composer.value = self.fixture.history_entries[self.history_index]
        self.composer.cursor_position = len(self.composer.value)

    def action_accept_completion(self) -> None:
        if not self.composer or self.focused is not self.composer:
            return
        if self.composer.value.endswith("che"):
            self.composer.value = f"{self.composer.value[:-3]}checkout"
            self.composer.cursor_position = len(self.composer.value)
            self.completion_accepted = True

    def focus_editor_end(self) -> None:
        self._editor.focus()
        self._editor.move_cursor(self._editor.document.end)

    def focus_composer(self) -> None:
        self._composer.focus()

    def focus_secret(self) -> None:
        self._secret.focus()

    def set_composer_text(self, value: str) -> None:
        self._composer.value = value
        self._composer.cursor_position = len(value)
        self.completion_accepted = False

    def replace_selection(self) -> None:
        selection = self._editor.selection
        start, end = selection.start, selection.end
        if start == end:
            end = self._editor.document.end
            start = self._editor.get_cursor_left_location()
        self._editor.replace(
            self.fixture.selection_replacement,
            start,
            end,
            maintain_selection_offset=False,
        )

    def paste_large_text(self) -> None:
        self._editor.insert(self.fixture.paste_text)

    def state_snapshot(self) -> EditingState:
        editor = self._editor
        composer = self._composer
        secret = self._secret
        selected = ""
        selection = editor.selection
        if selection.start != selection.end:
            selected = editor.get_text_range(selection.start, selection.end)
        display = self.screen.render()
        display_text = str(display)
        text = editor.text
        return EditingState(
            editor_text_length=len(text),
            composer_text=composer.value,
            secret_visible_value=secret.value,
            cursor_location=tuple(editor.cursor_location),
            selected_text=selected,
            completion_accepted=self.completion_accepted,
            history_index=self.history_index,
            contains_paste_marker=self.fixture.paste_marker in text,
            contains_cjk="\u6f22\u5b57" in text,
            contains_emoji="\U0001f642" in text,
            contains_combining="e\u0301" in text,
            raw_secret_in_display=self.fixture.secret_text in display_text,
            password_input_mode=secret.password,
        )

    @property
    def _editor(self) -> TextArea:
        if self.editor is None:
            raise RuntimeError("TextArea is not mounted.")
        return self.editor

    @property
    def _composer(self) -> Input:
        if self.composer is None:
            raise RuntimeError("Composer Input is not mounted.")
        return self.composer

    @property
    def _secret(self) -> Input:
        if self.secret is None:
            raise RuntimeError("Secret Input is not mounted.")
        return self.secret
