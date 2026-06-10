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
    selected: 1,
    filtering: false,
    copiedBytes: 0,
    groupSize: Math.max(1, Math.min(1000, options.rows)),
  }
  state.groupCount = Math.ceil(options.rows / state.groupSize)
  const text = new TextRenderable(renderer, {
    id: 'sb11-treetable-filter-copy',
    width: options.terminalColumns,
    height: options.terminalRows,
    content: renderTree(options, state),
    wrapMode: 'none',
    truncate: true,
  })
  renderer.root.add(text)
  try {
    await render(renderer, text, options, state)
    await sleep(options.intervalMs)
    for (let index = 0; index < options.steps; index += 1) {
      switch (state.step % 6) {
        case 0:
          state.selected = state.groupSize + 1
          break
        case 1:
          state.selected = Math.min(visibleRowCount(options, state) - 1, state.selected + 20)
          break
        case 2:
          state.selected = visibleRowCount(options, state) - 1
          break
        case 3:
          state.filtering = true
          state.selected = 1
          break
        case 4:
          state.copiedBytes = Buffer.byteLength(copySelectedRow(options, state), 'utf8')
          break
        case 5:
          state.filtering = false
          state.selected = 1
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
  text.content = renderTree(options, state)
  renderer.requestRender()
  await renderer.idle()
}

function renderTree(options, state) {
  const query = state.filtering ? targetQuery(options.rows) : 'none'
  const lines = [
    `SB.11 tree step=${state.step} rows=${options.rows} filter=${query} copied=${state.copiedBytes}`,
    '',
  ]

  if (state.filtering) {
    lines.push(groupLine(state.groupCount - 1))
    lines.push(rowLine(options.rows - 1, true, options.rows))
    return lines.join('\n')
  }

  lines.push(groupLine(0))
  for (let row = 0; row < Math.min(12, options.rows); row += 1) {
    lines.push(rowLine(row, state.selected === row + 1, options.rows))
  }
  if (state.groupCount > 1) {
    lines.push(groupLine(1))
    const start = state.groupSize
    for (let row = start; row < Math.min(start + 10, options.rows); row += 1) {
      lines.push(rowLine(row, state.selected === row + 2, options.rows))
    }
  }
  if (state.selected >= visibleRowCount(options, state) - 2) {
    lines.push(groupLine(state.groupCount - 1))
    for (let row = Math.max(0, options.rows - 8); row < options.rows; row += 1) {
      lines.push(rowLine(row, row === options.rows - 1, options.rows))
    }
  }
  return lines.join('\n')
}

function visibleRowCount(options, state) {
  const expandedLeafCount = Math.min(options.rows, state.groupSize * Math.min(2, state.groupCount))
  return Math.min(state.groupCount + expandedLeafCount, options.rows + state.groupCount)
}

function copySelectedRow(options, state) {
  const row = state.filtering ? options.rows - 1 : Math.min(options.rows - 1, state.selected)
  return [
    'Component\tStatus\tOwner\tDuration\tNotes',
    `${leafKey(row)}\t${status(row)}\t${owner(row)}\t${duration(row)}\t${notes(row)}`,
  ].join('\n')
}

function groupLine(group) {
  return `GROUP-${String(group).padStart(3, '0')} ready owner=${owner(group)} duration=${String(group % 7).padStart(2, '0')}:00 1000 tasks`
}

function rowLine(row, selected, rows) {
  const marker = selected ? '>' : ' '
  const unsafe = row % 97 === 0 ? ` unsafe secret-${row} payload` : ''
  const target = row === rows - 1 ? ` ${targetQuery(rows)}` : ''
  return `${marker} ${leafKey(row)} ${status(row).padEnd(8)} ${owner(row).padEnd(5)} ${duration(row).padStart(5)} ${notes(row)}${target}${unsafe}`
}

function leafKey(row) {
  return `TASK-${100000 + row}`
}

function targetQuery(rows) {
  return `zz-target-${100000 + rows - 1}`
}

function status(row) {
  return ['queued', 'running', 'passed', 'failed', 'blocked'][row % 5]
}

function owner(row) {
  return ['agent', 'ops', 'qa', 'infra', 'cli'][row % 5]
}

function duration(row) {
  return `${String(row % 4).padStart(2, '0')}:${String(row % 60).padStart(2, '0')}`
}

function notes(row) {
  return `shard ${row % 4096} ${['core', 'widgets', 'unicode', 'deploy'][row % 4]}`
}

function parseArgs(args) {
  const options = {
    rows: 100000,
    steps: 6,
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
