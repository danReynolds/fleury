from __future__ import annotations

import asyncio

from sb4_log_app import (
    Sb4LogRegionApp,
    append_filter_query,
    expected_copied_text,
    log_key,
)


async def main() -> None:
    row_count = 1_000
    append_count = 128
    app = Sb4LogRegionApp(row_count=row_count)
    async with app.run_test(size=(120, 32)) as pilot:
        await pilot.pause()

        state = app.state_snapshot()
        assert state.entry_count == row_count
        assert state.line_count == row_count
        assert state.selected_key == log_key(row_count - 1)
        assert state.unsafe_artifact_leak_count == 0

        app.append_burst(append_count)
        await pilot.pause()
        last_source_index = row_count + append_count - 1
        state = app.state_snapshot()
        assert state.entry_count == row_count + append_count
        assert state.line_count == row_count + append_count
        assert state.selected_key == log_key(last_source_index)
        assert state.tail_anchored
        assert state.unsafe_artifact_leak_count == 0

        app.jump_to_scrollback(row_count // 2)
        await pilot.pause()
        state = app.state_snapshot()
        assert state.selected_key == log_key(row_count // 2)
        assert state.scroll_y <= state.max_scroll_y

        app.scroll_to_tail()
        await pilot.pause()
        state = app.state_snapshot()
        assert state.selected_key == log_key(last_source_index)
        assert state.tail_anchored

        await pilot.press("ctrl+c")
        await pilot.pause()
        assert app.last_copied_text == expected_copied_text(last_source_index)
        assert "\x1b" not in app.last_copied_text
        assert "secret-" not in app.last_copied_text
        assert "\n" not in app.last_copied_text

        query = append_filter_query(row_count)
        matches = app.filter_query(query)
        await pilot.pause()
        state = app.state_snapshot()
        assert matches == append_count
        assert state.line_count == append_count
        assert state.filtered_count == append_count
        assert state.selected_key == log_key(last_source_index)
        assert state.unsafe_artifact_leak_count == 0


if __name__ == "__main__":
    asyncio.run(main())
