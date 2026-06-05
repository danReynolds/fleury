#!/usr/bin/env bun

import { createCliRenderer, TextRenderable } from '@opentui/core'

const DEFAULT_ROWS = 2_000
const DEFAULT_STEPS = 8
const DEFAULT_INTERVAL_MS = 60
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
    counter: 0,
    accent: false,
    textVariant: false,
  }
  const text = new TextRenderable(renderer, {
    id: 'sb12-layout-dirtiness',
    width: options.terminalColumns,
    height: options.terminalRows,
    content: renderLayout(options, state),
    wrapMode: 'none',
    truncate: true,
  })
  renderer.root.add(text)
  try {
    await render(renderer, text, options, state)
    await sleep(options.intervalMs)
    for (let index = 0; index < options.steps; index += 1) {
      switch (state.step % 4) {
        case 0:
          state.counter += 1
          break
        case 1:
          state.accent = !state.accent
          break
        case 2:
          state.textVariant = !state.textVariant
          break
      }
      state.step += 1
      await render(renderer, text, options, state)
      await sleep(options.intervalMs)
    }
  } finally {
    renderer.destroy?.()
  }
}

async function render(renderer, text, options, state) {
  text.content = renderLayout(options, state)
  renderer.requestRender()
  await renderer.idle()
}

function renderLayout(options, state) {
  const visible = Math.min(26, Math.max(1, options.rows))
  const start = Math.max(0, options.rows - visible)
  const lines = [
    `SB.12 layout step=${state.step} counter=${state.counter} accent=${state.accent} variant=${state.textVariant}`,
    '',
    `hot region counter=${String(state.counter).padStart(4, '0')}  paint-only text variant=${state.textVariant ? 'B' : 'A'}`,
    '',
  ]
  for (let index = 0; index < visible; index += 1) {
    const row = start + index
    lines.push(
      `row ${String(row).padStart(6, '0')} stable payload owner=layout shard=${row % 31} checksum=${(row * 17) % 997}`,
    )
  }
  return lines.join('\n')
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
