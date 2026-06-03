from __future__ import annotations

import asyncio

from sb3_datatable_app import Sb3DataTableApp, expected_selected_tsv, row_id


async def main() -> None:
    row_count = 1_000
    app = Sb3DataTableApp(row_count=row_count)
    async with app.run_test(size=(80, 24)) as pilot:
        await pilot.pause()

        state = app.state_snapshot()
        assert state.row_count == row_count
        assert state.cursor_row == 0
        assert state.visible_window_rows <= 28

        await pilot.press("down")
        await pilot.pause()
        assert app.state_snapshot().cursor_row == 1

        await pilot.press("pagedown")
        await pilot.pause()
        assert app.state_snapshot().cursor_row > 1

        await pilot.press("end")
        await pilot.pause()
        state = app.state_snapshot()
        assert state.cursor_row == row_count - 1
        assert state.selected_row_id == row_id(row_count - 1)
        assert state.scroll_y <= state.max_scroll_y

        await pilot.press("ctrl+c")
        await pilot.pause()
        assert app.last_copied_tsv == expected_selected_tsv(row_count - 1)
        assert "\x1b" not in app.last_copied_tsv


if __name__ == "__main__":
    asyncio.run(main())
