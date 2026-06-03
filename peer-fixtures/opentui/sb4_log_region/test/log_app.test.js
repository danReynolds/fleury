import { describe, expect, test } from 'bun:test'

import {
  Sb4OpenTuiLogHarness,
  appendFilterQuery,
  expectedCopiedText,
  logKey,
  unsafeCopyTextCount,
  unsafeVisibleTextCount,
} from '../lib/log_app.js'

describe('OpenTUI SB.4 log region fixture', () => {
  test('exercises tailing, scrollback, filtering, copy, and safety adapters', async () => {
    const rows = 1000
    const append = 128
    const app = await Sb4OpenTuiLogHarness.create({
      rowCount: rows,
      terminalColumns: 96,
      terminalRows: 16,
    })

    try {
      const firstFrame = await app.render()
      expect(firstFrame).toContain(logKey(rows - 1))
      expect(unsafeVisibleTextCount(firstFrame)).toBe(0)

      app.appendBurst(append)
      const appendFrame = await app.render()
      const expectedLastIndex = rows + append - 1
      expect(appendFrame).toContain(logKey(expectedLastIndex))
      expect(app.snapshot().tailAnchored).toBe(true)
      expect(unsafeVisibleTextCount(appendFrame)).toBe(0)

      app.jumpToScrollback(Math.floor(rows / 2))
      const scrollbackFrame = await app.render()
      expect(scrollbackFrame).toContain(logKey(Math.floor(rows / 2)))
      expect(app.snapshot().tailAnchored).toBe(false)

      app.scrollToTail()
      await app.render()
      const copied = app.copySelectedEntry()
      expect(copied).toBe(expectedCopiedText(expectedLastIndex, 'append'))
      expect(unsafeCopyTextCount(copied)).toBe(0)

      app.filterQuery(appendFilterQuery())
      const filteredFrame = await app.render()
      const filtered = app.snapshot()
      expect(filtered.displayedCount).toBe(append)
      expect(filtered.selectedKey).toBe(logKey(expectedLastIndex))
      expect(filtered.frameContainsSelected).toBe(true)
      expect(filteredFrame).toContain(appendFilterQuery())
      expect(filtered.lastFrameUnsafeCount).toBe(0)
    } finally {
      app.destroy()
    }
  })
})
