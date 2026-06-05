#!/usr/bin/env node

import React from 'react'
import { Box, Text, render as renderInk } from 'ink'

const screens = ['home', 'search', 'task', 'logs', 'diagnostics']
const options = parseArgs(process.argv.slice(2))
if (options.wire) await runWire(options)
else console.log('Ink SB.10 proof app fixture: use --wire for PTY capture')

async function runWire(options) {
  let instance
  const done = new Promise((resolve) => {
    instance = renderInk(
      React.createElement(WireProofApp, {
        options,
        onDone: () => {
          instance.unmount()
          resolve()
        },
      }),
      {
        exitOnCtrlC: false,
        interactive: true,
        alternateScreen: true,
        maxFps: 60,
        patchConsole: false,
      },
    )
  })
  await done
  await instance.waitUntilExit()
}

function WireProofApp({ options, onDone }) {
  const [step, setStep] = React.useState(0)
  const [events, setEvents] = React.useState(['boot proof app'])
  const screen = screens[step % screens.length]

  React.useEffect(() => {
    const timer = setInterval(() => {
      setStep((current) => {
        const next = Math.min(current + 1, options.steps)
        const nextScreen = screens[current % screens.length]
        setEvents((items) => [...items, `step=${current} screen=${nextScreen} rows=${options.rows}`].slice(-12))
        if (next >= options.steps) {
          clearInterval(timer)
          setTimeout(onDone, options.intervalMs)
        }
        return next
      })
    }, options.intervalMs)
    return () => clearInterval(timer)
  }, [options.steps, options.intervalMs, options.rows, onDone])

  return React.createElement(
    Box,
    { flexDirection: 'column' },
    React.createElement(Text, null, `SB.10 proof app screen=${screen} step=${step}`),
    React.createElement(Text, null, ''),
    React.createElement(
      Text,
      null,
      `nav: home search task  command: ${commandName(screen).padEnd(14)} status: ${status(step)}`,
    ),
    React.createElement(Text, null, ''),
    React.createElement(Text, null, `results visible=${(step * 17) % options.rows} selected=${step % 9}`),
    React.createElement(Text, null, ''),
    ...events.map((event, index) => React.createElement(Text, { key: index }, event)),
  )
}

function commandName(screen) {
  return {
    home: 'open-palette',
    search: 'rank-results',
    task: 'run-process',
    logs: 'copy-log',
  }[screen] ?? 'diagnose'
}

function status(step) {
  return ['idle', 'running', 'complete', 'warning'][step % 4]
}

function parseArgs(args) {
  const options = { wire: false, rows: 1000, steps: 10, intervalMs: 50 }
  for (const arg of args) {
    if (arg === '--wire') options.wire = true
    else if (arg.startsWith('--rows=')) options.rows = positive(arg, '--rows=')
    else if (arg.startsWith('--steps=')) options.steps = positive(arg, '--steps=')
    else if (arg.startsWith('--interval-ms=')) options.intervalMs = positive(arg, '--interval-ms=')
    else if (arg.startsWith('--size=')) continue
    else throw new Error(`unknown argument: ${arg}`)
  }
  return options
}

function positive(arg, prefix) {
  const value = Number(arg.slice(prefix.length))
  if (!Number.isInteger(value) || value <= 0) throw new Error(`${prefix} expects a positive integer`)
  return value
}
