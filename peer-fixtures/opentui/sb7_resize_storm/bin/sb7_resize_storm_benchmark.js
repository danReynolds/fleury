#!/usr/bin/env bun

import { createCliRenderer, TextRenderable } from '@opentui/core'

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
  const state = { step: 0 }
  const text = new TextRenderable(renderer, {
    id: 'sb7-resize-storm',
    width: options.terminalColumns,
    height: options.terminalRows,
    content: renderBody(options, state),
    wrapMode: 'none',
    truncate: true,
  })
  renderer.root.add(text)
  try {
    for (let step = 0; step <= options.steps; step += 1) {
      state.step = step
      text.content = renderBody(options, state)
      renderer.requestRender()
      await renderer.idle()
      await sleep(options.intervalMs)
    }
  } finally {
    renderer.destroy?.()
  }
}

function renderBody(options, state) {
  const width = process.stdout.columns || options.terminalColumns
  const height = process.stdout.rows || options.terminalRows
  const visibleLogs = Math.max(2, Math.min(10, Math.floor(height / 3)))
  const visibleRows = Math.max(3, Math.min(14, height - visibleLogs - 4))
  const lines = [
    `SB.7 resize step=${state.step} rows=${options.rows} size=${width}x${height}`,
    'filter status:failed',
    '',
  ]
  for (let row = 0; row < visibleRows; row += 1) {
    const index = (state.step * 7 + row) % options.rows
    lines.push(
      `RUN-${100000 + index} ${status(index).padEnd(8)} owner=${owner(index).padEnd(5)} duration=${String(index % 3).padStart(2, '0')}:${String(index % 60).padStart(2, '0')} Resize shard ${index % 2048}`,
    )
  }
  lines.push('')
  for (let row = 0; row < visibleLogs; row += 1) {
    const index = state.step * visibleLogs + row
    const unsafe = index % 17 === 0 ? ` secret-${index} payload` : ''
    lines.push(`resize log ${index} shard=${index % 31} status=${status(index)}${unsafe}`)
  }
  return lines.join('\n')
}

function status(row) {
  return ['queued', 'running', 'passed', 'failed', 'blocked'][row % 5]
}

function owner(row) {
  return ['agent', 'ops', 'qa', 'infra', 'cli'][row % 5]
}

function parseArgs(args) {
  const options = {
    rows: 100000,
    steps: 8,
    intervalMs: 80,
    terminalColumns: 120,
    terminalRows: 32,
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
