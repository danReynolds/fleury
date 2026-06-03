from __future__ import annotations

import asyncio

from sb2_text_editing_app import (
    Sb2TextEditingApp,
    generate_fixture,
)


async def test_textual_sb2_text_editing_fixture() -> None:
    fixture = generate_fixture(text_chars=2_000)
    app = Sb2TextEditingApp(fixture)

    async with app.run_test(size=(90, 28)) as pilot:
        await pilot.pause()
        app.focus_editor_end()
        await pilot.pause()

        await pilot.press("left")
        await pilot.press("ctrl+left")
        await pilot.press("end")
        await pilot.press("x")
        await pilot.press("backspace")
        await pilot.press("shift+left")
        app.replace_selection()
        await pilot.pause()
        assert fixture.selection_replacement in app._editor.text

        await pilot.press("ctrl+z")
        await pilot.pause()
        assert fixture.selection_replacement not in app._editor.text

        await pilot.press("ctrl+y")
        await pilot.pause()
        assert fixture.selection_replacement in app._editor.text

        app.paste_large_text()
        await pilot.pause()
        assert fixture.paste_marker in app._editor.text
        assert "\u6f22\u5b57" in app._editor.text
        assert "\U0001f642" in app._editor.text
        assert "e\u0301" in app._editor.text

        app.focus_composer()
        app.set_composer_text("git che")
        await pilot.press("tab")
        await pilot.pause()
        assert app._composer.value == "git checkout"
        assert app.completion_accepted

        app.set_composer_text(fixture.history_draft)
        await pilot.press("up")
        await pilot.pause()
        assert app._composer.value == fixture.history_entries[-1]
        await pilot.press("down")
        await pilot.pause()
        assert app._composer.value == fixture.history_draft

        app.focus_secret()
        await pilot.pause()
        state = app.state_snapshot()
        assert state.password_input_mode
        assert not state.raw_secret_in_display


if __name__ == "__main__":
    asyncio.run(test_textual_sb2_text_editing_fixture())
