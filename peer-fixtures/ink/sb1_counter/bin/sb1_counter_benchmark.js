#!/usr/bin/env node

import React from 'react'
import { Text, render as renderInk } from 'ink'

const options = parseArgs(process.argv.slice(2))
if (options.wire) await runWire(options)
else console.log('Ink SB.1 counter fixture: use --wire for PTY capture')

async function runWire(options) {
  let instance
  const done = new Promise((resolve) => {
    instance = renderInk(
      React.createElement(WireCounterApp, {
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

function WireCounterApp({ options, onDone }) {
  const [count, setCount] = React.useState(0)

  React.useEffect(() => {
    const timer = setInterval(() => {
      setCount((current) => {
        if (current + 1 >= options.steps) {
          clearInterval(timer)
          setTimeout(onDone, options.intervalMs)
        }
        return Math.min(current + 1, options.steps)
      })
    }, options.intervalMs)
    return () => clearInterval(timer)
  }, [options.steps, options.intervalMs, onDone])

  return React.createElement(Text, null, `Count: ${count}`)
}

function parseArgs(args) {
  const options = { wire: false, steps: 1, intervalMs: 60 }
  for (const arg of args) {
    if (arg === '--wire') options.wire = true
    else if (arg.startsWith('--rows=')) continue
    else if (arg.startsWith('--size=')) continue
    else if (arg.startsWith('--steps=')) options.steps = positive(arg, '--steps=')
    else if (arg.startsWith('--interval-ms=')) options.intervalMs = positive(arg, '--interval-ms=')
    else throw new Error(`unknown argument: ${arg}`)
  }
  return options
}

function positive(arg, prefix) {
  const value = Number(arg.slice(prefix.length))
  if (!Number.isInteger(value) || value <= 0) throw new Error(`${prefix} expects a positive integer`)
  return value
}
