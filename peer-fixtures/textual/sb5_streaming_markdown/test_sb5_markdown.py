from __future__ import annotations

import asyncio

from sb5_markdown_app import (
    MarkdownFixture,
    Sb5StreamingMarkdownApp,
    markdown_chunk_count_for,
    unsafe_count_text,
)


async def run_case() -> None:
    app = Sb5StreamingMarkdownApp()
    fixture = MarkdownFixture(seed=1)
    chunk_count = markdown_chunk_count_for(1_000)
    async with app.run_test(size=(120, 32)) as pilot:
        await pilot.pause()
        for index in range(chunk_count):
            await app.append_chunk(fixture.chunk(index))
            await pilot.pause()
        app.select_final_block()
        await pilot.pause()
        await pilot.press("ctrl+c")
        await pilot.pause()
        state = app.state_snapshot()

    assert state.chunk_count == chunk_count
    assert state.block_count > 0
    assert state.heading_count > 0
    assert state.list_item_count > 0
    assert state.link_count > 0
    assert state.unsafe_link_count > 0
    assert state.code_block_count > 0
    assert state.code_line_count > 0
    assert state.selected_block_index == state.block_count - 1
    assert state.copied_byte_count > 0
    assert state.sanitized_chunk_count > 0
    assert state.unsafe_links_have_visible_fallback
    assert state.unsafe_artifact_leak_count == 0
    assert unsafe_count_text(app.last_copied_text) == 0


def test_streaming_markdown_copy_link_policy_and_safety() -> None:
    asyncio.run(run_case())
