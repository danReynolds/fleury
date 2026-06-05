#!/usr/bin/env bun

import { createCliRenderer, TextRenderable } from '@opentui/core'

const DEFAULT_ROWS = 100_000
const DEFAULT_STEPS = 120
const DEFAULT_INTERVAL_MS = 16
const DEFAULT_COLUMNS = 120
const DEFAULT_TERMINAL_ROWS = 32

const options = parseArgs(process.argv.slice(2))
await runWire(options)

async function runWire(options) {
  const renderer = await createCliRenderer({
    width: options.terminalColumns,
    height: options.terminalRows,
    consoleMode: 'disabled',
    screenMode: 'alternate-screen',
    clearOnShutdown: true,
    targetFps: 60,
    maxFps: 60,
    exitOnCtrlC: false,
  })
  const state = {
    step: 0,
    history: Array.from({ length: 48 }, (_, index) => 40 + (index % 17)),
  }
  const text = new TextRenderable(renderer, {
    id: 'sb6-dashboard',
    width: options.terminalColumns,
    height: options.terminalRows,
    content: renderDashboard(options, state),
    wrapMode: 'none',
    truncate: true,
  })
  renderer.root.add(text)
  try {
    await render(renderer, text, options, state)
    await sleep(options.intervalMs)
    for (let index = 0; index < options.steps; index += 1) {
      state.step += 1
      state.history = [...state.history.slice(1), 20 + ((state.step * 13) % 80)]
      await render(renderer, text, options, state)
      await sleep(options.intervalMs)
    }
  } finally {
    renderer.destroy?.()
  }
}

async function render(renderer, text, options, state) {
  text.content = renderDashboard(options, state)
  renderer.requestRender()
  await renderer.idle()
}

function renderDashboard(options, state) {
  const cpu = (state.step * 17) % 100
  const mem = (state.step * 29 + 15) % 100
  const disk = (state.step * 7 + 30) % 100
  const completed = Math.min(options.rows, state.step * Math.max(1, Math.floor(options.rows / 80)))
  const lines = [
    `SB.6 dashboard tick=${state.step} rows=${options.rows} active=${20 + ((state.step * 7) % 900)}`,
    '',
    `CPU ${bar(cpu, 32).padEnd(36)} ${String(cpu).padStart(3)}%`,
    `MEM ${bar(mem, 32).padEnd(36)} ${String(mem).padStart(3)}%`,
    `IO  ${bar(disk, 32).padEnd(36)} ${String(disk).padStart(3)}%`,
    '',
    `build queue ${String(completed).padStart(6)} / ${options.rows}`,
    bar(percent(completed, options.rows), 76),
    '',
    `spark ${spark(state.history, 76)}`,
    '',
  ]
  for (let index = 0; index < 14; index += 1) {
    const id = (state.step * 10 + index) % Math.max(1, options.rows)
    const statuses = ['queued', 'running', 'passed', 'failed', 'blocked']
    lines.push(
      `RUN-${String(id).padStart(6, '0')} ${statuses[(id + state.step) % statuses.length].padEnd(7)} ` +
        `shard=${String(id % 31).padStart(2, '0')} owner=worker-${String(id % 17).padStart(2, '0')} latency=${20 + (id % 900)}ms`,
    )
  }
  return lines.join('\n')
}

function bar(value, width) {
  const filled = Math.floor(Math.max(0, Math.min(100, value)) * width / 100)
  return '#'.repeat(filled) + '.'.repeat(width - filled)
}

function spark(values, width) {
  const levels = '._-~=+*#'
  return values
    .slice(Math.max(0, values.length - width))
    .map((value) => levels[Math.min(levels.length - 1, Math.floor(value * (levels.length - 1) / 100))])
    .join('')
}

function percent(value, total) {
  return total <= 0 ? 0 : Math.floor(value * 100 / total)
}

function parseArgs(args) {
  const options = {
    rows: DEFAULT_ROWS,
    steps: DEFAULT_STEPS,
    intervalMs: DEFAULT_INTERVAL_MS,
    terminalColumns: DEFAULT_COLUMNS,
    terminalRows: DEFAULT_TERMINAL_ROWS,
  }
  for (const arg of args) {
    if (arg === '--wire') continue
    if (arg.startsWith('--rows=')) options.rows = positive(arg, '--rows=')
    else if (arg.startsWith('--steps=')) options.steps = positive(arg, '--steps=')
    else if (arg.startsWith('--interval-ms=')) options.intervalMs = positive(arg, '--interval-ms=')
    else if (arg.startsWith('--size=')) {
      const [columns, rows] = arg.slice('--size='.length).split('x').map(Number)
      if (!Number.isInteger(columns) || columns <= 0 || !Number.isInteger(rows) || rows <= 0) {
        throw new Error('--size must be COLSxROWS')
      }
      options.terminalColumns = columns
      options.terminalRows = rows
    } else {
      throw new Error(`unknown argument: ${arg}`)
    }
  }
  return options
}

function positive(arg, prefix) {
  const value = Number(arg.slice(prefix.length))
  if (!Number.isInteger(value) || value <= 0) throw new Error(`${prefix} expects a positive integer`)
  return value
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
