#!/usr/bin/env bun

import { execFileSync } from 'node:child_process'
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

import {
  Sb4OpenTuiLogHarness,
  appendFilterQuery,
  expectedCopiedText,
  logKey,
  unsafeCopyTextCount,
  unsafeVisibleTextCount,
} from '../lib/log_app.js'

const SCHEMA_VERSION = 1
const PEER_ID = 'opentui'
const PEER_NAME = 'OpenTUI'
const PEER_VERSION = '0.3.1'
const PEER_URL = 'https://www.npmjs.com/package/@opentui/core'
const SCENARIO_ID = 'SB.4'
const DEFAULT_WARMUPS = 2
const DEFAULT_ITERATIONS = 5
const DEFAULT_ROWS = 100_000
const DEFAULT_APPEND = 1_000
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
  console.log('OpenTUI SB.4 LogRegion fixture')
  console.log(`Rows: ${options.rows}`)
  console.log(`Append: ${options.appendCount}`)
  console.log(`Iterations: ${options.measuredIterations}`)
  console.log(`appendBurstUs p95: ${artifact.metrics.appendBurstUs.p95}`)
  console.log(`filterQueryUs p95: ${artifact.metrics.filterQueryUs.p95}`)
  console.log(`unsafeArtifactLeakCount: ${artifact.metrics.unsafeArtifactLeakCount}`)
  if (options.outputPath) console.log(`Saved ${options.outputPath}`)
}

async function runSample(options) {
  let app
  const rssBefore = process.memoryUsage().rss
  const mountStart = process.hrtime.bigint()
  app = await Sb4OpenTuiLogHarness.create({
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

    const appendStart = process.hrtime.bigint()
    app.appendBurst(options.appendCount)
    const appendFrame = await app.render()
    const appendBurstUs = elapsedUs(appendStart)
    const appendState = app.snapshot()

    const scrollbackIndex = Math.floor(options.rows / 2)
    const scrollbackStart = process.hrtime.bigint()
    app.jumpToScrollback(scrollbackIndex)
    const scrollbackFrame = await app.render()
    const scrollbackJumpUs = elapsedUs(scrollbackStart)
    const scrollbackState = app.snapshot()

    const tailStart = process.hrtime.bigint()
    app.scrollToTail()
    const tailFrame = await app.render()
    const scrollToTailUs = elapsedUs(tailStart)
    const tailState = app.snapshot()

    const copyStart = process.hrtime.bigint()
    const copied = app.copySelectedEntry()
    const copySelectedEntryUs = elapsedUs(copyStart)

    const filterStart = process.hrtime.bigint()
    app.filterQuery(appendFilterQuery())
    const filterFrame = await app.render()
    const filterQueryUs = elapsedUs(filterStart)
    const filterState = app.snapshot()

    const queryStart = process.hrtime.bigint()
    const selectedKeyVisible = filterState.frameContainsSelected
    const unsafeLeakCount =
      filterState.lastFrameUnsafeCount +
      unsafeCopyTextCount(copied) +
      unsafeVisibleTextCount(firstFrame) +
      unsafeVisibleTextCount(appendFrame) +
      unsafeVisibleTextCount(scrollbackFrame) +
      unsafeVisibleTextCount(tailFrame) +
      unsafeVisibleTextCount(filterFrame)
    const semanticOrTestQueryUs = elapsedUs(queryStart)

    const expectedLastIndex = options.rows + options.appendCount - 1
    const expectedLastKey = logKey(expectedLastIndex)

    return {
      mountUs,
      firstRenderUs,
      appendBurstUs,
      scrollbackJumpUs,
      scrollToTailUs,
      copySelectedEntryUs,
      filterQueryUs,
      semanticOrTestQueryUs,
      rssDeltaBytes: Math.max(0, rssAfterMount - rssBefore),
      unsafeArtifactLeakCount: unsafeLeakCount,
      entryCountAfterAppend: appendState.entryCount,
      lineCountAfterFilter: filterState.displayedCount,
      filterMatchCount: filterState.displayedCount,
      selectedKey: filterState.selectedKey,
      visibleStart: filterState.visibleStart,
      visibleEnd: filterState.visibleEnd,
      visibleWindowRows: filterState.visibleWindowRows,
      tailAnchoringCorrect:
        appendState.tailAnchored &&
        tailState.tailAnchored &&
        tailState.selectedKey === expectedLastKey &&
        tailState.entryCount === options.rows + options.appendCount,
      copyTextSanitized:
        copied === expectedCopiedText(expectedLastIndex, 'append') &&
        unsafeCopyTextCount(copied) === 0,
      filterResultCorrect:
        filterState.displayedCount === options.appendCount &&
        filterState.selectedKey === expectedLastKey &&
        selectedKeyVisible,
      scrollbackSelectedCorrect:
        scrollbackState.selectedKey === logKey(scrollbackIndex) &&
        scrollbackFrame.includes(logKey(scrollbackIndex)),
    }
  } finally {
    app?.destroy()
  }
}

function buildArtifact(options, samples, runRssDeltaBytes) {
  const capturedAt = new Date()
  const runId = `opentui-sb4-log-region-${capturedAt
    .toISOString()
    .replace(/\.\d{3}Z$/, 'Z')
    .replaceAll(':', '-')}`
  const last = samples[samples.length - 1]
  const unsafeLeakCount = Math.max(
    ...samples.map((sample) => sample.unsafeArtifactLeakCount),
  )
  const appLines = sourceLineCount(new URL('../lib/log_app.js', import.meta.url))
  const benchmarkLines = sourceLineCount(import.meta.url)
  const testLines = sourceLineCount(new URL('../test/log_app.test.js', import.meta.url))

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
      workingDirectory: 'peer-fixtures/opentui/sb4_log_region',
      command: [
        'npm',
        'run',
        'benchmark',
        '--',
        `--warmup=${options.warmupIterations}`,
        `--iterations=${options.measuredIterations}`,
        `--rows=${options.rows}`,
        `--append=${options.appendCount}`,
        '--json',
      ],
      warmupIterations: options.warmupIterations,
      measuredIterations: options.measuredIterations,
    },
    metrics: {
      mountUs: stats(samples.map((sample) => sample.mountUs)),
      firstRenderUs: stats(samples.map((sample) => sample.firstRenderUs)),
      appendBurstUs: stats(samples.map((sample) => sample.appendBurstUs)),
      scrollbackJumpUs: stats(samples.map((sample) => sample.scrollbackJumpUs)),
      scrollToTailUs: stats(samples.map((sample) => sample.scrollToTailUs)),
      copySelectedEntryUs: stats(
        samples.map((sample) => sample.copySelectedEntryUs),
      ),
      filterQueryUs: stats(samples.map((sample) => sample.filterQueryUs)),
      semanticOrTestQueryUs: stats(
        samples.map((sample) => sample.semanticOrTestQueryUs),
      ),
      unsafeArtifactLeakCount: unsafeLeakCount,
      rssDeltaBytes: Math.max(
        runRssDeltaBytes,
        ...samples.map((sample) => sample.rssDeltaBytes),
      ),
      lineOfCodeCount: appLines,
      benchmarkLineOfCodeCount: benchmarkLines,
      testLineOfCodeCount: testLines,
      entryCountAfterAppend: last.entryCountAfterAppend,
      appendCount: options.appendCount,
      lineCountAfterFilter: last.lineCountAfterFilter,
      filterMatchCount: last.filterMatchCount,
      selectedKey: last.selectedKey,
      finalVisibleStart: last.visibleStart,
      finalVisibleEnd: last.visibleEnd,
      visibleWindowRowEstimate: last.visibleWindowRows,
    },
    correctness: [
      {
        gate: 'tail anchoring is correct',
        pass: samples.every((sample) => sample.tailAnchoringCorrect),
        evidence: `After append and explicit tail scroll, the OpenTUI text frame stayed anchored at ${logKey(
          options.rows + options.appendCount - 1,
        )}.`,
      },
      {
        gate: 'copy text is sanitized',
        pass: samples.every((sample) => sample.copyTextSanitized),
        evidence:
          'Selected-entry copy matched the generated sanitized log line and contained no escape, secret, or newline artifacts.',
      },
      {
        gate: 'unsafe output leak count is zero',
        pass: unsafeLeakCount === 0,
        evidence:
          'Fixture-owned sanitizer removed ANSI/OSC/control payloads before OpenTUI TextRenderable rendering.',
      },
    ],
    ergonomics: {
      lineOfCodeCount: appLines,
      benchmarkLineOfCodeCount: benchmarkLines,
      testLineOfCodeCount: testLines,
      appFile: 'lib/log_app.js',
      benchmarkFile: 'bin/sb4_log_region_benchmark.js',
      testFile: 'test/log_app.test.js',
      peerOwnedTextRenderable: true,
      peerOwnedTestRenderer: true,
      appOwnedRetainedLogs: true,
      appOwnedTailPolicy: true,
      appOwnedSanitization: true,
      appOwnedFiltering: true,
      appOwnedSelectedEntryCopy: true,
      semanticGraphAvailable: false,
      testQueryViaFrameAndAppState: true,
    },
    artifacts: [
      {
        kind: 'source',
        path: 'peer-fixtures/opentui/sb4_log_region/lib/log_app.js',
      },
      {
        kind: 'benchmark',
        path:
          'peer-fixtures/opentui/sb4_log_region/bin/sb4_log_region_benchmark.js',
      },
      {
        kind: 'test',
        path: 'peer-fixtures/opentui/sb4_log_region/test/log_app.test.js',
      },
    ],
    notes: [
      'This is an OpenTUI test-renderer peer fixture, not a real-terminal run.',
      'OpenTUI 0.3.1 supplies TextRenderable and the native-backed test renderer.',
      'Retained logs, tail policy, scrollback selection, sanitization/redaction, filtering, selected-entry state, and copy/export are app-owned fixture code because OpenTUI 0.3.1 does not expose Fleury-equivalent built-in LogRegion semantics.',
      'OpenTUI exposes frame/app state for this fixture, not a Fleury-style semantic app graph.',
      'Timing is local-machine evidence and should not be used as a public superiority claim without repeated peer runs.',
    ],
  }
}

function stats(values) {
  const sorted = [...values].sort((a, b) => a - b)
  if (sorted.length === 0) throw new Error('Cannot summarize empty metric samples.')
  return {
    min: sorted[0],
    median: percentile(sorted, 0.5),
    p95: percentile(sorted, 0.95),
    p99: percentile(sorted, 0.99),
    max: sorted[sorted.length - 1],
    samples: sorted.length,
  }
}

function percentile(sorted, percent) {
  const index = Math.min(
    sorted.length - 1,
    Math.max(0, Math.ceil(sorted.length * percent) - 1),
  )
  return sorted[index]
}

function elapsedUs(start) {
  return Number((process.hrtime.bigint() - start) / 1000n)
}

function sourceLineCount(urlOrPath) {
  const path =
    urlOrPath instanceof URL || String(urlOrPath).startsWith('file:')
      ? fileURLToPath(urlOrPath)
      : urlOrPath
  return readFileSync(path, 'utf8')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith('//')).length
}

function commandOutput(command, args = []) {
  try {
    return execFileSync(command, args, { encoding: 'utf8' }).trim()
  } catch (_) {
    return null
  }
}

function runtimeVersion() {
  return commandOutput('bun', ['--version']) ?? process.version
}

function parseArgs(args) {
  const options = {
    warmupIterations: DEFAULT_WARMUPS,
    measuredIterations: DEFAULT_ITERATIONS,
    rows: DEFAULT_ROWS,
    appendCount: DEFAULT_APPEND,
    terminalColumns: DEFAULT_COLUMNS,
    terminalRows: DEFAULT_TERMINAL_ROWS,
    printJson: false,
    outputPath: '',
  }

  for (const arg of args) {
    if (arg === '--json') {
      options.printJson = true
      continue
    }
    const [name, value] = arg.split('=', 2)
    switch (name) {
      case '--warmup':
        options.warmupIterations = parseNonNegativeInt(name, value)
        break
      case '--iterations':
        options.measuredIterations = parsePositiveInt(name, value)
        break
      case '--rows':
        options.rows = parsePositiveInt(name, value)
        break
      case '--append':
        options.appendCount = parsePositiveInt(name, value)
        break
      case '--columns':
        options.terminalColumns = parsePositiveInt(name, value)
        break
      case '--terminal-rows':
        options.terminalRows = parsePositiveInt(name, value)
        break
      case '--output':
        if (!value) throw new Error('--output requires a path')
        options.outputPath = value
        break
      default:
        throw new Error(`Unknown argument: ${arg}`)
    }
  }

  return options
}

function parsePositiveInt(name, value) {
  const parsed = Number.parseInt(value, 10)
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive integer.`)
  }
  return parsed
}

function parseNonNegativeInt(name, value) {
  const parsed = Number.parseInt(value, 10)
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new Error(`${name} must be a non-negative integer.`)
  }
  return parsed
}
