import { TextTableRenderable, stringToStyledText } from '@opentui/core'
import { createTestRenderer } from '@opentui/core/testing'

export const COLUMNS = [
  ['id', 'ID'],
  ['status', 'Status'],
  ['title', 'Title'],
  ['owner', 'Owner'],
  ['duration', 'Duration'],
  ['progress', 'Progress'],
  ['warnings', 'Warnings'],
  ['updated', 'Updated'],
]

const ESCAPE_PATTERN =
  /\x1b(?:\][^\x07]*(?:\x07|\x1b\\)|\[[0-?]*[ -/]*[@-~]|[PX^_][\s\S]*?(?:\x1b\\|\x07)|[@-Z\\-_])/g
const CONTROL_PATTERN = /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g
const SECRET_PATTERN = /secret-[A-Za-z0-9_-]+/g

export function rowId(index) {
  return `RUN-${String(index).padStart(6, '0')}`
}

export function visibleDataCapacity(terminalRows) {
  return Math.max(1, Math.floor((terminalRows - 2) / 2))
}

export function makeRow(index) {
  const rawTitle =
    index % 97 === 0
      ? `Build pipeline ${index} \x1b[31munsafe\x1b[0m secret-${index}`
      : `Build pipeline ${index}`
  return {
    id: rowId(index),
    status: index % 5 === 0 ? 'failed' : 'ok',
    title: sanitizeDisplayText(rawTitle),
    owner: `user-${index % 17}`,
    duration: `${30 + (index % 400)}s`,
    progress: `${index % 101}%`,
    warnings: String(index % 4),
    updated: `2026-06-${String(1 + (index % 28)).padStart(2, '0')}`,
  }
}

export function rowCells(row) {
  return [
    row.id,
    row.status,
    row.title,
    row.owner,
    row.duration,
    row.progress,
    row.warnings,
    row.updated,
  ]
}

export function expectedCopiedRow(index) {
  return tsvForRow(makeRow(index))
}

export function tsvForRow(row) {
  const headings = COLUMNS.map((column) => column[1]).join('\t')
  const cells = rowCells(row).map(sanitizeTsvCell).join('\t')
  return `${headings}\n${cells}`
}

export function sanitizeDisplayText(value) {
  return String(value)
    .replace(ESCAPE_PATTERN, '')
    .replace(SECRET_PATTERN, '[redacted]')
    .replace(CONTROL_PATTERN, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

export function sanitizeTsvCell(value) {
  return sanitizeDisplayText(value).replace(/[\t\r\n]/g, ' ')
}

export function unsafeVisibleTextCount(value) {
  const text = String(value)
  return (
    countMatches(text, ESCAPE_PATTERN) +
    countMatches(text, CONTROL_PATTERN) +
    countMatches(text, SECRET_PATTERN)
  )
}

export function unsafeCopyTextCount(value) {
  const text = String(value)
  return (
    countMatches(text, ESCAPE_PATTERN) +
    countMatches(text, /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g) +
    countMatches(text, SECRET_PATTERN)
  )
}

export class Sb3OpenTuiTableHarness {
  static async create(options = {}) {
    const rowCount = options.rowCount ?? 100_000
    const terminalColumns = options.terminalColumns ?? 120
    const terminalRows = options.terminalRows ?? 32
    const setup = await createTestRenderer({
      width: terminalColumns,
      height: terminalRows,
      consoleMode: 'disabled',
    })
    const app = new Sb3OpenTuiTableHarness({
      rowCount,
      terminalColumns,
      terminalRows,
      setup,
    })
    app.mount()
    return app
  }

  constructor({ rowCount, terminalColumns, terminalRows, setup }) {
    this.rowCount = rowCount
    this.terminalColumns = terminalColumns
    this.terminalRows = terminalRows
    this.rows = Array.from({ length: rowCount }, (_, index) => makeRow(index))
    this.visibleCapacity = visibleDataCapacity(terminalRows)
    this.selectedIndex = 0
    this.visibleStart = 0
    this.lastCopiedText = ''
    this.lastFrame = ''
    this.setup = setup
    this.renderer = setup.renderer
    this.renderOnce = setup.renderOnce
    this.captureCharFrame = setup.captureCharFrame
    this.getNativeStats = setup.getNativeStats
    this.table = null
  }

  mount() {
    this.table = new TextTableRenderable(this.renderer, {
      id: 'sb3-table',
      width: this.terminalColumns,
      height: this.terminalRows,
      content: this.tableContent(),
      showBorders: false,
      selectable: true,
      columnWidthMode: 'full',
      cellPaddingX: 1,
      cellPaddingY: 0,
      columnGap: 1,
    })
    this.renderer.root.add(this.table)
  }

  async render() {
    this.updateTable()
    this.renderer.requestRender?.()
    await this.renderOnce()
    this.lastFrame = frameToText(this.captureCharFrame())
    return this.lastFrame
  }

  arrowDown() {
    if (this.rowCount === 0) return
    this.selectedIndex = Math.min(this.selectedIndex + 1, this.rowCount - 1)
    this.keepSelectedVisible()
    this.updateTable()
  }

  pageDown() {
    if (this.rowCount === 0) return
    this.selectedIndex = Math.min(
      this.selectedIndex + this.visibleCapacity,
      this.rowCount - 1,
    )
    this.visibleStart = Math.min(this.selectedIndex, this.maxVisibleStart())
    this.keepSelectedVisible()
    this.updateTable()
  }

  jumpToEnd() {
    if (this.rowCount === 0) return
    this.selectedIndex = this.rowCount - 1
    this.visibleStart = this.maxVisibleStart()
    this.updateTable()
  }

  copySelectedRow() {
    const row = this.rows[this.selectedIndex]
    this.lastCopiedText = row ? tsvForRow(row) : ''
    return this.lastCopiedText
  }

  snapshot() {
    const selectedRowId = this.rows[this.selectedIndex]?.id ?? ''
    const visibleEnd = this.visibleEnd()
    const frame = this.lastFrame
    return {
      rowCount: this.rowCount,
      selectedRow: this.selectedIndex,
      selectedRowId,
      visibleStart: this.visibleStart,
      visibleEnd,
      visibleWindowRows: Math.max(0, visibleEnd - this.visibleStart),
      visibleCapacity: this.visibleCapacity,
      frameContainsSelectedRow: frame.includes(selectedRowId),
      lastFrameUnsafeCount: unsafeVisibleTextCount(frame),
      lastCopiedText: this.lastCopiedText,
      lastCopiedUnsafeCount: unsafeCopyTextCount(this.lastCopiedText),
      nativeStats: this.getNativeStats?.(),
    }
  }

  destroy() {
    return this.renderer.destroy?.()
  }

  updateTable() {
    if (!this.table) return
    this.table.content = this.tableContent()
  }

  tableContent() {
    return [
      COLUMNS.map((column) => tableCell(column[1])),
      ...this.visibleRows().map((row) => rowCells(row).map(tableCell)),
    ]
  }

  visibleRows() {
    return this.rows.slice(this.visibleStart, this.visibleEnd())
  }

  visibleEnd() {
    return Math.min(this.visibleStart + this.visibleCapacity, this.rowCount)
  }

  maxVisibleStart() {
    return Math.max(0, this.rowCount - Math.max(1, this.visibleCapacity))
  }

  keepSelectedVisible() {
    const capacity = Math.max(1, this.visibleCapacity)
    if (this.selectedIndex < this.visibleStart) {
      this.visibleStart = this.selectedIndex
    } else if (this.selectedIndex >= this.visibleStart + capacity) {
      this.visibleStart = this.selectedIndex + 1 - capacity
    }
    this.visibleStart = Math.min(this.visibleStart, this.maxVisibleStart())
  }
}

function tableCell(value) {
  return stringToStyledText(sanitizeDisplayText(value)).chunks
}

function frameToText(frame) {
  if (typeof frame === 'string') return frame
  if (Array.isArray(frame)) {
    return frame
      .map((row) => (Array.isArray(row) ? row.join('') : String(row)))
      .join('\n')
  }
  return String(frame ?? '')
}

function countMatches(text, pattern) {
  pattern.lastIndex = 0
  let count = 0
  while (pattern.exec(text) !== null) {
    count += 1
  }
  pattern.lastIndex = 0
  return count
}
