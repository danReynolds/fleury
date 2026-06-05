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
  const state = {
    step: 0,
    lines: Array.from({ length: 16 }, (_, index) => lineFor(index)),
  }
  const text = new TextRenderable(renderer, {
    id: 'sb9-subprocess-output',
    width: options.terminalColumns,
    height: options.terminalRows,
    content: renderBody(state),
    wrapMode: 'none',
    truncate: true,
  })
  renderer.root.add(text)
  try {
    await render(renderer, text, state)
    await sleep(options.intervalMs)
    for (let index = 0; index < options.steps; index += 1) {
      for (let offset = 0; offset < 4; offset += 1) {
        state.lines.push(lineFor(state.lines.length))
      }
      state.lines = state.lines.slice(-24)
      state.step += 1
      await render(renderer, text, state)
      await sleep(options.intervalMs)
    }
  } finally {
    renderer.destroy?.()
  }
}

async function render(renderer, text, state) {
  text.content = renderBody(state)
  renderer.requestRender()
  await renderer.idle()
}

function renderBody(state) {
  return [`SB.9 subprocess output step=${state.step} total=${state.lines.length}`, '', ...state.lines].join('\n')
}

function lineFor(index) {
  const unsafe = index % 5 === 0 ? ` secret-${index}` : ''
  return `proc[${index}] stdout shard=${index % 17} status=${index % 3} message="streamed output ${index}"${unsafe}`
}

function parseArgs(args) {
  const options = {
    rows: 400,
    steps: 10,
    intervalMs: 35,
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
