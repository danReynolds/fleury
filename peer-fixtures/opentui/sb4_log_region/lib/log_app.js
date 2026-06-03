import { TextRenderable } from '@opentui/core'
import { createTestRenderer } from '@opentui/core/testing'

const LEVELS = ['info', 'warn', 'error', 'debug']
const ESCAPE_PATTERN =
  /\x1b(?:\][^\x07]*(?:\x07|\x1b\\)|\[[0-?]*[ -/]*[@-~]|[PX^_][\s\S]*?(?:\x1b\\|\x07)|[@-Z\\-_])/g
const CONTROL_PATTERN = /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g
const SECRET_PATTERN = /secret-[A-Za-z0-9_-]+/g

export function logKey(index) {
  return `LOG-${String(index).padStart(6, '0')}`
}

export function appendFilterQuery() {
  return 'append-burst'
}

export function visibleLineCapacity(terminalRows) {
  return Math.max(1, terminalRows)
}

export function makeLogEntry(index, phase = 'initial') {
  const unsafe =
    index % 89 === 0
      ? ` \x1b[31munsafe\x1b[0m \x1b]8;;https://unsafe.example\x07link\x1b]8;;\x07 secret-${index}`
      : ''
  const phaseText = phase === 'append' ? `${appendFilterQuery()} ` : ''
  return {
    index,
    id: logKey(index),
    source: `worker-${index % 9}`,
    level: LEVELS[index % LEVELS.length],
    message: sanitizeDisplayText(
      `${phaseText}event ${index} completed batch ${index % 257}${unsafe}`,
    ),
  }
}

export function lineForEntry(entry) {
  if (!entry) return ''
  return `${entry.id} ${entry.level.padEnd(5)} ${entry.source.padEnd(8)} ${entry.message}`
}

export function expectedCopiedText(index, phase = 'append') {
  return lineForEntry(makeLogEntry(index, phase))
}

export function sanitizeDisplayText(value) {
  return String(value)
    .replace(ESCAPE_PATTERN, '')
    .replace(SECRET_PATTERN, '[redacted]')
    .replace(CONTROL_PATTERN, ' ')
    .replace(/\s+/g, ' ')
    .trim()
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

export class Sb4OpenTuiLogHarness {
  static async create(options = {}) {
    const rowCount = options.rowCount ?? 100_000
    const terminalColumns = options.terminalColumns ?? 120
    const terminalRows = options.terminalRows ?? 32
    const setup = await createTestRenderer({
      width: terminalColumns,
      height: terminalRows,
      consoleMode: 'disabled',
    })
    const app = new Sb4OpenTuiLogHarness({
      rowCount,
      terminalColumns,
      terminalRows,
      setup,
    })
    app.mount()
    return app
  }

  constructor({ rowCount, terminalColumns, terminalRows, setup }) {
    this.terminalColumns = terminalColumns
    this.terminalRows = terminalRows
    this.entries = Array.from({ length: rowCount }, (_, index) =>
      makeLogEntry(index),
    )
    this.visibleCapacity = visibleLineCapacity(terminalRows)
    this.filteredIndexes = null
    this.selectedDisplayIndex = Math.max(0, this.displayedLength() - 1)
    this.visibleStart = this.maxVisibleStart()
    this.lastCopiedText = ''
    this.lastFrame = ''
    this.setup = setup
    this.renderer = setup.renderer
    this.renderOnce = setup.renderOnce
    this.captureCharFrame = setup.captureCharFrame
    this.getNativeStats = setup.getNativeStats
    this.logText = null
  }

  mount() {
    this.logText = new TextRenderable(this.renderer, {
      id: 'sb4-log',
      width: this.terminalColumns,
      height: this.terminalRows,
      content: this.visibleText(),
      wrapMode: 'none',
      truncate: true,
      selectable: false,
    })
    this.renderer.root.add(this.logText)
  }

  async render() {
    this.updateText()
    this.renderer.requestRender?.()
    await this.renderOnce()
    this.lastFrame = frameToText(this.captureCharFrame())
    return this.lastFrame
  }

  appendBurst(count) {
    const startIndex = this.entries.length
    for (let offset = 0; offset < count; offset += 1) {
      this.entries.push(makeLogEntry(startIndex + offset, 'append'))
    }
    if (this.filteredIndexes) {
      this.applyFilter(appendFilterQuery())
    }
    this.selectedDisplayIndex = Math.max(0, this.displayedLength() - 1)
    this.visibleStart = this.maxVisibleStart()
    this.updateText()
  }

  jumpToScrollback(sourceIndex) {
    this.filteredIndexes = null
    this.selectedDisplayIndex = Math.max(
      0,
      Math.min(sourceIndex, this.displayedLength() - 1),
    )
    this.visibleStart = Math.min(this.selectedDisplayIndex, this.maxVisibleStart())
    this.keepSelectedVisible()
    this.updateText()
  }

  scrollToTail() {
    this.selectedDisplayIndex = Math.max(0, this.displayedLength() - 1)
    this.visibleStart = this.maxVisibleStart()
    this.updateText()
  }

  copySelectedEntry() {
    const entry = this.selectedEntry()
    this.lastCopiedText = lineForEntry(entry)
    return this.lastCopiedText
  }

  filterQuery(query) {
    this.applyFilter(query)
    this.selectedDisplayIndex = Math.max(0, this.displayedLength() - 1)
    this.visibleStart = this.maxVisibleStart()
    this.updateText()
  }

  snapshot() {
    const selected = this.selectedEntry()
    const visibleEnd = this.visibleEnd()
    const frame = this.lastFrame
    return {
      entryCount: this.entries.length,
      displayedCount: this.displayedLength(),
      selectedKey: selected?.id ?? '',
      selectedSourceIndex: selected?.index ?? -1,
      selectedDisplayIndex: this.selectedDisplayIndex,
      visibleStart: this.visibleStart,
      visibleEnd,
      visibleWindowRows: Math.max(0, visibleEnd - this.visibleStart),
      tailAnchored:
        this.selectedDisplayIndex === Math.max(0, this.displayedLength() - 1) &&
        this.visibleStart === this.maxVisibleStart(),
      frameContainsSelected: selected ? frame.includes(selected.id) : false,
      lastFrameUnsafeCount: unsafeVisibleTextCount(frame),
      lastCopiedText: this.lastCopiedText,
      lastCopiedUnsafeCount: unsafeCopyTextCount(this.lastCopiedText),
      nativeStats: this.getNativeStats?.(),
    }
  }

  destroy() {
    return this.renderer.destroy?.()
  }

  updateText() {
    if (!this.logText) return
    this.logText.content = this.visibleText()
  }

  visibleText() {
    const indexes = this.displayedIndexes()
    return indexes
      .slice(this.visibleStart, this.visibleEnd())
      .map((sourceIndex, visibleOffset) => {
        const displayIndex = this.visibleStart + visibleOffset
        const marker = displayIndex === this.selectedDisplayIndex ? '>' : ' '
        return `${marker} ${lineForEntry(this.entries[sourceIndex])}`
      })
      .join('\n')
  }

  selectedEntry() {
    const sourceIndex = this.sourceIndexAtDisplay(this.selectedDisplayIndex)
    return sourceIndex == null ? null : this.entries[sourceIndex]
  }

  displayedLength() {
    return this.filteredIndexes?.length ?? this.entries.length
  }

  displayedIndexes() {
    if (this.filteredIndexes) return this.filteredIndexes
    return this.entries.map((_, index) => index)
  }

  sourceIndexAtDisplay(displayIndex) {
    if (displayIndex < 0 || displayIndex >= this.displayedLength()) return null
    return this.filteredIndexes?.[displayIndex] ?? displayIndex
  }

  visibleEnd() {
    return Math.min(this.visibleStart + this.visibleCapacity, this.displayedLength())
  }

  maxVisibleStart() {
    return Math.max(0, this.displayedLength() - Math.max(1, this.visibleCapacity))
  }

  keepSelectedVisible() {
    const capacity = Math.max(1, this.visibleCapacity)
    if (this.selectedDisplayIndex < this.visibleStart) {
      this.visibleStart = this.selectedDisplayIndex
    } else if (this.selectedDisplayIndex >= this.visibleStart + capacity) {
      this.visibleStart = this.selectedDisplayIndex + 1 - capacity
    }
    this.visibleStart = Math.min(this.visibleStart, this.maxVisibleStart())
  }

  applyFilter(query) {
    const normalized = sanitizeDisplayText(query).toLowerCase()
    if (!normalized) {
      this.filteredIndexes = null
      return
    }
    this.filteredIndexes = []
    for (let index = 0; index < this.entries.length; index += 1) {
      const entry = this.entries[index]
      const haystack = `${entry.id} ${entry.source} ${entry.level} ${entry.message}`
        .toLowerCase()
      if (haystack.includes(normalized)) this.filteredIndexes.push(index)
    }
  }
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
  const matches = text.match(pattern)
  return matches ? matches.length : 0
}
