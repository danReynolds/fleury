#!/usr/bin/env bun

import { execFileSync } from 'node:child_process'
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

import {
  Sb3OpenTuiTableHarness,
  expectedCopiedRow,
  rowId,
  unsafeCopyTextCount,
  unsafeVisibleTextCount,
  visibleDataCapacity,
} from '../lib/table_app.js'

const SCHEMA_VERSION = 1
const PEER_ID = 'opentui'
const PEER_NAME = 'OpenTUI'
const PEER_VERSION = '0.3.1'
const PEER_URL = 'https://www.npmjs.com/package/@opentui/core'
const SCENARIO_ID = 'SB.3'
const DEFAULT_WARMUPS = 2
const DEFAULT_ITERATIONS = 5
const DEFAULT_ROWS = 100_000
const DEFAULT_COLUMNS = 120
const DEFAULT_TERMINAL_ROWS = 32

const options = parseArgs(process.argv.slice(2))

for (let index = 0; index < options.warmupIterations; index += 1) {
  await runSample(options)
}

const rssBefore = process.memoryUsage().rss
const samples = []
for (let index = 0; index < options.measuredIterations; index += 1) {
  samples.push(await runSample(options))
}
const runRssDeltaBytes = Math.max(0, process.memoryUsage().rss - rssBefore)
const artifact = buildArtifact(options, samples, runRssDeltaBytes)
const jsonText = `${JSON.stringify(artifact, null, 2)}\n`

if (options.outputPath) {
  mkdirSync(dirname(options.outputPath), { recursive: true })
  writeFileSync(options.outputPath, jsonText)
}

if (options.printJson) {
  process.stdout.write(jsonText)
} else {
  console.log('OpenTUI SB.3 DataTable fixture')
  console.log(`Rows: ${options.rows}`)
  console.log(`Iterations: ${options.measuredIterations}`)
  console.log(`pageMoveUs p95: ${artifact.metrics.pageMoveUs.p95}`)
  console.log(`copySelectedRowUs p95: ${artifact.metrics.copySelectedRowUs.p95}`)
  if (options.outputPath) console.log(`Saved ${options.outputPath}`)
}

async function runSample(options) {
  let app
  const rssBefore = process.memoryUsage().rss
  const mountStart = process.hrtime.bigint()
  app = await Sb3OpenTuiTableHarness.create({
    rowCount: options.rows,
    terminalColumns: options.terminalColumns,
    terminalRows: options.terminalRows,
  })
  const mountUs = elapsedUs(mountStart)
  const rssAfterMount = process.memoryUsage().rss

  try {
    const firstRenderStart = process.hrtime.bigint()
    const firstFrame = await app.render()
    const firstRenderUs = elapsedUs(firstRenderStart)

    const arrowStart = process.hrtime.bigint()
    app.arrowDown()
    await app.render()
    const arrowMoveUs = elapsedUs(arrowStart)

    const pageStart = process.hrtime.bigint()
    app.pageDown()
    await app.render()
    const pageMoveUs = elapsedUs(pageStart)

    const jumpStart = process.hrtime.bigint()
    app.jumpToEnd()
    const finalFrame = await app.render()
    const jumpToEndUs = elapsedUs(jumpStart)

    const copyStart = process.hrtime.bigint()
    const copied = app.copySelectedRow()
    const copySelectedRowUs = elapsedUs(copyStart)

    const expectedId = rowId(options.rows - 1)
    const expectedCopy = expectedCopiedRow(options.rows - 1)
    const queryStart = process.hrtime.bigint()
    const snapshot = app.snapshot()
    const frameContainsSelectedRow =
      finalFrame.includes(expectedId) && snapshot.frameContainsSelectedRow
    const semanticOrTestQueryUs = elapsedUs(queryStart)
    const unsafeLeakCount =
      snapshot.lastFrameUnsafeCount +
      unsafeCopyTextCount(copied) +
      unsafeVisibleTextCount(firstFrame) +
      0

    return {
      mountUs,
      firstRenderUs,
      arrowMoveUs,
      pageMoveUs,
      jumpToEndUs,
      copySelectedRowUs,
      semanticOrTestQueryUs,
      rssDeltaBytes: Math.max(0, rssAfterMount - rssBefore),
      rowCount: snapshot.rowCount,
      visibleWindowRows: snapshot.visibleWindowRows,
      visibleStart: snapshot.visibleStart,
      visibleEnd: snapshot.visibleEnd,
      selectedRow: snapshot.selectedRow,
      selectedRowId: snapshot.selectedRowId,
      visibleWindowBounded:
        snapshot.visibleWindowRows <=
        visibleDataCapacity(options.terminalRows),
      selectionCorrect:
        snapshot.selectedRow === options.rows - 1 &&
        snapshot.selectedRowId === expectedId &&
        frameContainsSelectedRow,
      copyExact: copied === expectedCopy && unsafeCopyTextCount(copied) === 0,
      unsafeLeakCount,
      firstFrameUnsafeCount: unsafeVisibleTextCount(firstFrame),
    }
  } finally {
    app?.destroy()
  }
}

function buildArtifact(options, samples, runRssDeltaBytes) {
  const capturedAt = new Date()
  const runId = `opentui-sb3-datatable-${capturedAt
    .toISOString()
    .replace(/\.\d{3}Z$/, 'Z')
    .replaceAll(':', '-')}`
  const last = samples[samples.length - 1]
  const allVisibleBounded = samples.every((sample) => sample.visibleWindowBounded)
  const allSelectionCorrect = samples.every((sample) => sample.selectionCorrect)
  const allCopyExact = samples.every((sample) => sample.copyExact)
  const appLines = sourceLineCount(new URL('../lib/table_app.js', import.meta.url))
  const benchmarkLines = sourceLineCount(import.meta.url)
  const testLines = sourceLineCount(
    new URL('../test/table_app.test.js', import.meta.url),
  )

  return {
    schemaVersion: SCHEMA_VERSION,
    kind: 'fleuryPeerBenchmarkRun',
    runId,
    peerId: PEER_ID,
    scenarioId: SCENARIO_ID,
    capturedAt: capturedAt.toISOString(),
    source: {
      name: PEER_NAME,
      version: PEER_VERSION,
      url: PEER_URL,
    },
    environment: {
      machine: commandOutput('hostname') ?? 'unknown',
      operatingSystem: process.platform,
      operatingSystemVersion:
        commandOutput('uname', ['-a']) ?? process.platform,
      runtime: `${runtimeVersion()} / OpenTUI ${PEER_VERSION}`,
      terminalMode: 'opentui-test-renderer-memory',
      terminalSize: {
        columns: options.terminalColumns,
        rows: options.terminalRows,
      },
    },
    fixture: {
      workingDirectory: 'peer-fixtures/opentui/sb3_datatable',
      command: [
        'npm',
        'run',
        'benchmark',
        '--',
        `--warmup=${options.warmupIterations}`,
        `--iterations=${options.measuredIterations}`,
        `--rows=${options.rows}`,
        '--json',
      ],
      warmupIterations: options.warmupIterations,
      measuredIterations: options.measuredIterations,
    },
    metrics: {
      mountUs: stats(samples.map((sample) => sample.mountUs)),
      firstRenderUs: stats(samples.map((sample) => sample.firstRenderUs)),
      arrowMoveUs: stats(samples.map((sample) => sample.arrowMoveUs)),
      pageMoveUs: stats(samples.map((sample) => sample.pageMoveUs)),
      jumpToEndUs: stats(samples.map((sample) => sample.jumpToEndUs)),
      copySelectedRowUs: stats(samples.map((sample) => sample.copySelectedRowUs)),
      semanticOrTestQueryUs: stats(
        samples.map((sample) => sample.semanticOrTestQueryUs),
      ),
      rssDeltaBytes: Math.max(
        runRssDeltaBytes,
        ...samples.map((sample) => sample.rssDeltaBytes),
      ),
      lineOfCodeCount: appLines,
      benchmarkLineOfCodeCount: benchmarkLines,
      testLineOfCodeCount: testLines,
      rowCount: options.rows,
      observedRowCount: last.rowCount,
      visibleWindowRowEstimate: last.visibleWindowRows,
      visibleRangeStart: last.visibleStart,
      visibleRangeEnd: last.visibleEnd,
      finalSelectedRow: last.selectedRow,
      finalSelectedRowId: last.selectedRowId,
      unsafeLeakCount: Math.max(...samples.map((sample) => sample.unsafeLeakCount)),
    },
    correctness: [
      {
        gate: 'visible window stays bounded',
        pass: allVisibleBounded,
        evidence:
          'Fixture-owned visible-row slice stayed within the OpenTUI test-renderer height.',
      },
      {
        gate: 'selection is correct after jump',
        pass: allSelectionCorrect,
        evidence: `Jump-to-end selected ${rowId(
          options.rows - 1,
        )} and rendered it in the OpenTUI character frame.`,
      },
      {
        gate: 'copy/export is sanitized and exact',
        pass: allCopyExact,
        evidence:
          'Selected row TSV matched generated source row and contained no escape/control/secret leakage.',
      },
    ],
    ergonomics: {
      lineOfCodeCount: appLines,
      benchmarkLineOfCodeCount: benchmarkLines,
      testLineOfCodeCount: testLines,
      appFile: 'lib/table_app.js',
      benchmarkFile: 'bin/sb3_datatable_benchmark.js',
      testFile: 'test/table_app.test.js',
      peerOwnedTextTableRenderable: true,
      appOwnedRetainedRows: true,
      appOwnedVisibleRowSlicing: true,
      appOwnedSelectionState: true,
      appOwnedCopyExport: true,
      semanticGraphAvailable: false,
      testQueryViaFrameAndAppState: true,
    },
    artifacts: [
      {
        kind: 'source',
        path: 'peer-fixtures/opentui/sb3_datatable/lib/table_app.js',
      },
      {
        kind: 'benchmark',
        path: 'peer-fixtures/opentui/sb3_datatable/bin/sb3_datatable_benchmark.js',
      },
      {
        kind: 'test',
        path: 'peer-fixtures/opentui/sb3_datatable/test/table_app.test.js',
      },
    ],
    notes: [
      'This is an OpenTUI test-renderer memory fixture, not a real-terminal run.',
      'OpenTUI 0.3.1 supplies TextTableRenderable, styled text chunks, and the native-backed test renderer.',
      'The fixture owns retained row generation, visible-row slicing, navigation policy, selected-row copy/export, and state query because this scenario needs app behavior around the OpenTUI table renderer.',
      'Timing is local-machine evidence and should not be used as a public superiority claim without repeated peer runs.',
    ],
  }
}

function parseArgs(args) {
  const options = {
    warmupIterations: DEFAULT_WARMUPS,
    measuredIterations: DEFAULT_ITERATIONS,
    rows: DEFAULT_ROWS,
    terminalColumns: DEFAULT_COLUMNS,
    terminalRows: DEFAULT_TERMINAL_ROWS,
    printJson: false,
    outputPath: null,
  }

  for (const arg of args) {
    if (arg === '--json') {
      options.printJson = true
    } else if (arg.startsWith('--warmup=')) {
      options.warmupIterations = parseNonNegativeInteger(arg, 'warmup')
    } else if (arg.startsWith('--iterations=')) {
      options.measuredIterations = parsePositiveInteger(arg, 'iterations')
    } else if (arg.startsWith('--rows=')) {
      options.rows = parsePositiveInteger(arg, 'rows')
    } else if (arg.startsWith('--size=')) {
      const value = arg.slice('--size='.length)
      const [columns, rows] = value.split('x')
      options.terminalColumns = parsePositiveInteger(
        `--columns=${columns}`,
        'columns',
      )
      options.terminalRows = parsePositiveInteger(`--rows=${rows}`, 'rows')
    } else if (arg.startsWith('--output=')) {
      options.outputPath = arg.slice('--output='.length)
    } else {
      throw new Error(`unknown argument: ${arg}`)
    }
  }

  if (options.measuredIterations <= 0) {
    throw new Error('--iterations must be positive')
  }
  if (options.rows <= 0) {
    throw new Error('--rows must be positive')
  }
  return options
}

function parsePositiveInteger(arg, label) {
  const value = Number.parseInt(arg.slice(arg.indexOf('=') + 1), 10)
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`--${label} must be a positive integer`)
  }
  return value
}

function parseNonNegativeInteger(arg, label) {
  const value = Number.parseInt(arg.slice(arg.indexOf('=') + 1), 10)
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`--${label} must be a non-negative integer`)
  }
  return value
}

function elapsedUs(start) {
  return Number((process.hrtime.bigint() - start) / 1000n)
}

function stats(values) {
  const ordered = [...values].sort((a, b) => a - b)
  if (ordered.length === 0) {
    return { min: 0, median: 0, p95: 0, p99: 0, max: 0, samples: 0 }
  }
  return {
    min: ordered[0],
    median: percentile(ordered, 0.5),
    p95: percentile(ordered, 0.95),
    p99: percentile(ordered, 0.99),
    max: ordered[ordered.length - 1],
    samples: ordered.length,
  }
}

function percentile(ordered, fraction) {
  if (ordered.length === 1) return ordered[0]
  const index = Math.ceil((ordered.length - 1) * fraction)
  return ordered[Math.min(index, ordered.length - 1)]
}

function sourceLineCount(url) {
  const path = fileURLToPath(url)
  const text = readFileSync(path, 'utf8')
  return text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith('//')).length
}

function commandOutput(command, args = []) {
  try {
    return execFileSync(command, args, { encoding: 'utf8' }).trim()
  } catch {
    return null
  }
}

function runtimeVersion() {
  const bunVersion = globalThis.Bun?.version
  if (bunVersion) return `Bun ${bunVersion}`
  return `Node ${process.version}`
}
