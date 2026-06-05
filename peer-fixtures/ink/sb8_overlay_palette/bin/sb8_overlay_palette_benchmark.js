#!/usr/bin/env node

import React from 'react'
import { Box, Text, render as renderInk } from 'ink'

const options = parseArgs(process.argv.slice(2))
if (options.wire) await runWire(options)
else console.log('Ink SB.8 overlay/palette fixture: use --wire for PTY capture')

async function runWire(options) {
  let instance
  const done = new Promise((resolve) => {
    instance = renderInk(
      React.createElement(WireOverlayApp, {
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

function WireOverlayApp({ options, onDone }) {
  const [step, setStep] = React.useState(0)
  const paletteOpen = step % 3 !== 2
  const query = ['open', 'run', 'diag', 'copy'][step % 4]

  React.useEffect(() => {
    const timer = setInterval(() => {
      setStep((current) => {
        if (current + 1 >= options.steps) {
          clearInterval(timer)
          setTimeout(onDone, options.intervalMs)
        }
        return Math.min(current + 1, options.steps)
      })
    }, options.intervalMs)
    return () => clearInterval(timer)
  }, [options.steps, options.intervalMs, onDone])

  return React.createElement(
    Box,
    { flexDirection: 'column' },
    React.createElement(Text, null, `SB.8 overlay churn step=${step} open=${paletteOpen} query=${query}`),
    React.createElement(Text, null, ''),
    ...Array.from({ length: 9 }, (_, index) =>
      React.createElement(
        Text,
        { key: `row-${index}` },
        `screen row ${index} focus=${index === step % 9} command=cmd-${(step + index) % options.rows}`,
      ),
    ),
    paletteOpen
      ? React.createElement(
          React.Fragment,
          null,
          React.createElement(Text, null, ''),
          React.createElement(Text, null, `+${'-'.repeat(54)}+`),
          React.createElement(Text, null, `| Command Palette query=${query.padEnd(26)} |`),
          ...Array.from({ length: 6 }, (_, index) => {
            const commandIndex = (step * 7 + index) % options.rows
            return React.createElement(
              Text,
              { key: `command-${index}` },
              `| cmd-${String(commandIndex).padStart(4, '0')} ${query} action-${String(index).padEnd(31)} |`,
            )
          }),
          React.createElement(Text, null, `+${'-'.repeat(54)}+`),
        )
      : null,
  )
}

function parseArgs(args) {
  const options = { wire: false, rows: 500, steps: 12, intervalMs: 40 }
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
