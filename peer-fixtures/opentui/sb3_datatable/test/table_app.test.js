import { expect, test } from 'bun:test'

import {
  Sb3OpenTuiTableHarness,
  expectedCopiedRow,
  rowId,
  unsafeCopyTextCount,
  unsafeVisibleTextCount,
  visibleDataCapacity,
} from '../lib/table_app.js'

test('OpenTUI SB.3 table fixture navigates, renders, and copies safely', async () => {
  const rowCount = 1_000
  const terminalRows = 32
  const app = await Sb3OpenTuiTableHarness.create({
    rowCount,
    terminalColumns: 120,
    terminalRows,
  })

  try {
    await app.render()
    let snapshot = app.snapshot()
    expect(snapshot.rowCount).toBe(rowCount)
    expect(snapshot.selectedRow).toBe(0)
    expect(snapshot.selectedRowId).toBe(rowId(0))
    expect(snapshot.visibleWindowRows).toBeLessThanOrEqual(
      visibleDataCapacity(terminalRows),
    )
    expect(snapshot.frameContainsSelectedRow).toBe(true)
    expect(unsafeVisibleTextCount(app.lastFrame)).toBe(0)

    app.arrowDown()
    await app.render()
    snapshot = app.snapshot()
    expect(snapshot.selectedRow).toBe(1)
    expect(snapshot.selectedRowId).toBe(rowId(1))
    expect(snapshot.frameContainsSelectedRow).toBe(true)

    app.pageDown()
    await app.render()
    snapshot = app.snapshot()
    expect(snapshot.selectedRow).toBe(1 + app.visibleCapacity)
    expect(snapshot.frameContainsSelectedRow).toBe(true)

    app.jumpToEnd()
    await app.render()
    snapshot = app.snapshot()
    expect(snapshot.selectedRow).toBe(rowCount - 1)
    expect(snapshot.selectedRowId).toBe(rowId(rowCount - 1))
    expect(snapshot.visibleWindowRows).toBeLessThanOrEqual(app.visibleCapacity)
    expect(snapshot.frameContainsSelectedRow).toBe(true)
    expect(snapshot.lastFrameUnsafeCount).toBe(0)

    const copied = app.copySelectedRow()
    expect(copied).toBe(expectedCopiedRow(rowCount - 1))
    expect(unsafeCopyTextCount(copied)).toBe(0)
  } finally {
    app.destroy()
  }
})
