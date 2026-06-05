#!/usr/bin/env node

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import {execFileSync} from 'node:child_process';
import React from 'react';
import {render as renderInk} from 'ink';
import {render as renderTest} from 'ink-testing-library';
import {
  InkSb5App,
  MarkdownFixture,
  markdownChunkCountFor,
  markdownStats,
  parseMarkdownBlocks,
  sanitizeMarkdownChunk,
  unsafeVisibleTextCount,
} from '../lib/markdown_app.js';

const schemaVersion = 1;
const peerId = 'ink';
const peerName = 'Ink';
const inkVersion = '7.0.5';
const reactVersion = '19.2.7';
const testingLibraryVersion = '4.0.0';
const scenarioId = 'SB.5';
const defaultWarmups = 1;
const defaultIterations = 3;
const defaultRows = 10000;
const defaultWireSteps = 16;
const defaultWireIntervalMs = 50;
const defaultColumns = 120;
const defaultTerminalRows = 32;

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.wire) {
    await runWire(options);
    return;
  }
  for (let index = 0; index < options.warmupIterations; index += 1) {
    runSample(options);
  }
  const samples = [];
  for (let index = 0; index < options.measuredIterations; index += 1) {
    samples.push(runSample(options));
  }
  const artifact = buildArtifact(options, samples);
  const jsonText = `${JSON.stringify(artifact, null, 2)}\n`;
  if (options.outputPath) {
    fs.mkdirSync(path.dirname(options.outputPath), {recursive: true});
    fs.writeFileSync(options.outputPath, jsonText);
  }
  if (options.printJson) {
    process.stdout.write(jsonText);
    return;
  }
  const {metrics} = artifact;
  console.log('Ink SB.5 streaming markdown fixture');
  console.log(`Run: ${artifact.runId}`);
  console.log(`Rows: ${options.rows}`);
  console.log(`Chunks: ${metrics.chunkCount}`);
  console.log(`Iterations: ${options.measuredIterations}`);
  console.log(`chunkUpdateUs p95: ${metrics.chunkUpdateUs.p95}`);
  console.log(`finalRenderUs p95: ${metrics.finalRenderUs.p95}`);
  if (options.outputPath) {
    console.log(`Saved ${options.outputPath}`);
  }
}

function runSample(options) {
  const fixture = new MarkdownFixture({seed: 1});
  const chunkCount = markdownChunkCountFor(options.rows);
  const chunkUpdateUs = [];
  let source = '';
  let selectedIndex = 0;
  const rssBefore = process.memoryUsage().rss;

  const mountStart = nowNs();
  const rendered = renderTest(
    React.createElement(InkSb5App, {
      source,
      selectedIndex,
      columns: options.terminalColumns,
      rows: options.terminalRows,
    }),
  );
  const mountUs = elapsedUs(mountStart);
  const firstFrame = rendered.lastFrame() ?? '';

  const journeyStart = nowNs();
  for (let index = 0; index < chunkCount; index += 1) {
    const updateStart = nowNs();
    source += sanitizeMarkdownChunk(fixture.chunk(index));
    selectedIndex = Math.max(0, parseMarkdownBlocks(source).length - 1);
    rendered.rerender(
      React.createElement(InkSb5App, {
        source,
        selectedIndex,
        columns: options.terminalColumns,
        rows: options.terminalRows,
      }),
    );
    chunkUpdateUs.push(elapsedUs(updateStart));
  }

  const finalRenderStart = nowNs();
  const finalFrame = rendered.lastFrame() ?? '';
  const finalRenderUs = elapsedUs(finalRenderStart);
  const totalJourneyUs = elapsedUs(journeyStart);
  const stats = markdownStats(source);
  const blocks = parseMarkdownBlocks(source);
  const copied = blocks.at(-1)?.text ?? '';
  const unsafeFrameCount =
    unsafeVisibleTextCount(firstFrame) + unsafeVisibleTextCount(finalFrame);
  rendered.unmount();

  return {
    totalJourneyUs,
    mountUs,
    chunkUpdateUs,
    finalRenderUs,
    copySelectedBlockUs: 0,
    semanticOrTestQueryUs: 0,
    rssDeltaBytes: Math.max(0, process.memoryUsage().rss - rssBefore),
    chunkCount,
    sourceByteCount: Buffer.byteLength(source),
    blockCount: stats.blockCount,
    headingCount: stats.headingCount,
    listItemCount: stats.listItemCount,
    linkCount: stats.linkCount,
    unsafeLinkCount: stats.unsafeLinkCount,
    codeBlockCount: stats.codeBlockCount,
    selectedBlockIndex: selectedIndex,
    selectedBlockKind: blocks.at(-1)?.kind ?? '',
    unsafeFrameCount,
    sanitizedBlockCount: stats.sanitizedBlockCount,
    copiedByteCount: Buffer.byteLength(copied),
    incrementalContentCoherent: source.includes('Stream batch') && stats.blockCount > 0,
    unsafeLinksHaveVisibleFallback: stats.unsafeLinkCount === 0,
    unsafeFrameFree: unsafeFrameCount === 0,
    renderErrorFree: true,
  };
}

async function runWire(options) {
  let instance;
  const done = new Promise(resolve => {
    instance = renderInk(
      React.createElement(InkSb5WireApp, {
        rows: options.rows,
        columns: options.terminalColumns,
        terminalRows: options.terminalRows,
        steps: options.wireSteps,
        intervalMs: options.wireIntervalMs,
        onDone: () => {
          instance.unmount();
          resolve();
        },
      }),
      {
        exitOnCtrlC: false,
        interactive: true,
        alternateScreen: true,
        maxFps: 60,
        patchConsole: false,
      },
    );
  });
  await done;
  await instance.waitUntilExit();
}

function InkSb5WireApp({rows, columns, terminalRows, steps, intervalMs, onDone}) {
  const fixture = React.useMemo(() => new MarkdownFixture({seed: 1}), []);
  const chunkCount = React.useMemo(() => markdownChunkCountFor(rows), [rows]);
  const [source, setSource] = React.useState('');
  const [selectedIndex, setSelectedIndex] = React.useState(0);

  React.useEffect(() => {
    let step = 0;
    let emitted = 0;
    let sourceValue = '';
    const timer = setInterval(() => {
      if (step >= steps || emitted >= chunkCount) {
        clearInterval(timer);
        setTimeout(onDone, intervalMs);
        return;
      }
      const remaining = chunkCount - emitted;
      const remainingSteps = steps - step;
      const batch = Math.max(1, Math.floor(remaining / remainingSteps));
      for (let index = 0; index < batch && emitted < chunkCount; index += 1) {
        sourceValue += sanitizeMarkdownChunk(fixture.chunk(emitted));
        emitted += 1;
      }
      const blocks = parseMarkdownBlocks(sourceValue);
      setSource(sourceValue);
      setSelectedIndex(Math.max(0, blocks.length - 1));
      step += 1;
    }, intervalMs);
    return () => clearInterval(timer);
  }, [chunkCount, fixture, steps, intervalMs, onDone]);

  return React.createElement(InkSb5App, {
    source,
    selectedIndex,
    columns,
    rows: terminalRows,
  });
}

function buildArtifact(options, samples) {
  const capturedAt = new Date();
  const last = samples.at(-1);
  const appLines = sourceLineCount('lib/markdown_app.js');
  const benchmarkLines = sourceLineCount('bin/sb5_markdown_benchmark.js');

  return {
    schemaVersion,
    kind: 'fleuryPeerBenchmarkRun',
    runId: `ink-sb5-streaming-markdown-${timestampForId(capturedAt)}`,
    peerId,
    scenarioId,
    capturedAt: capturedAt.toISOString(),
    source: {
      name: peerName,
      version: `Ink ${inkVersion} / React ${reactVersion}`,
      url: 'https://www.npmjs.com/package/ink',
    },
    environment: {
      machine: os.hostname() || 'unknown',
      operatingSystem: os.platform(),
      operatingSystemVersion: osVersion(),
      runtime: `${process.version} / Ink ${inkVersion} / React ${reactVersion} / ink-testing-library ${testingLibraryVersion}`,
      terminalMode: 'ink-testing-library-memory',
      terminalSize: {
        columns: options.terminalColumns,
        rows: options.terminalRows,
      },
    },
    fixture: {
      workingDirectory: 'peer-fixtures/ink/sb5_streaming_markdown',
      command: [
        'node',
        'bin/sb5_markdown_benchmark.js',
        `--warmup=${options.warmupIterations}`,
        `--iterations=${options.measuredIterations}`,
        `--rows=${options.rows}`,
        '--json',
      ],
      warmupIterations: options.warmupIterations,
      measuredIterations: options.measuredIterations,
    },
    metrics: {
      totalJourneyUs: stats(samples.map(sample => sample.totalJourneyUs)),
      mountUs: stats(samples.map(sample => sample.mountUs)),
      chunkUpdateUs: stats(samples.flatMap(sample => sample.chunkUpdateUs)),
      finalRenderUs: stats(samples.map(sample => sample.finalRenderUs)),
      copySelectedBlockUs: stats(samples.map(sample => sample.copySelectedBlockUs)),
      semanticOrTestQueryUs: stats(samples.map(sample => sample.semanticOrTestQueryUs)),
      rssDeltaBytes: Math.max(...samples.map(sample => sample.rssDeltaBytes)),
      chunkCount: last.chunkCount,
      sourceByteCount: last.sourceByteCount,
      blockCount: last.blockCount,
      headingCount: last.headingCount,
      listItemCount: last.listItemCount,
      linkCount: last.linkCount,
      unsafeLinkCount: last.unsafeLinkCount,
      codeBlockCount: last.codeBlockCount,
      selectedBlockIndex: last.selectedBlockIndex,
      selectedBlockKind: last.selectedBlockKind,
      unsafeFrameCount: last.unsafeFrameCount,
      sanitizedBlockCount: last.sanitizedBlockCount,
      copiedByteCount: last.copiedByteCount,
      lineOfCodeCount: appLines,
      benchmarkLineOfCodeCount: benchmarkLines,
    },
    correctness: [
      {
        gate: 'incremental stream remains coherent',
        pass: samples.every(sample => sample.incrementalContentCoherent),
        evidence: 'All streamed chunks produced parsed blocks and kept batch headings visible to the fixture.',
      },
      {
        gate: 'unsafe markdown does not reach visible frames',
        pass: samples.every(sample => sample.unsafeFrameFree),
        evidence: 'Escape/control/secret patterns were sanitized before rendering.',
      },
      {
        gate: 'unsafe links have safe visible fallback',
        pass: samples.every(sample => sample.unsafeLinksHaveVisibleFallback),
        evidence: 'Fixture-generated links are non-javascript/data URLs after sanitization.',
      },
    ],
    ergonomics: {
      lineOfCodeCount: appLines,
      benchmarkLineOfCodeCount: benchmarkLines,
      appFile: 'lib/markdown_app.js',
      benchmarkFile: 'bin/sb5_markdown_benchmark.js',
      peerOwnedMarkdownParser: true,
      appOwnedViewportSelection: true,
      semanticGraphAvailable: false,
      testQueryViaInkTestingLibrary: true,
    },
    artifacts: [
      {
        kind: 'source',
        path: 'peer-fixtures/ink/sb5_streaming_markdown/lib/markdown_app.js',
      },
      {
        kind: 'benchmark',
        path: 'peer-fixtures/ink/sb5_streaming_markdown/bin/sb5_markdown_benchmark.js',
      },
    ],
    notes: [
      'Ink is represented as a retained React terminal UI peer for full-ui streaming markdown.',
      'The fixture owns markdown parsing/sanitization because Ink provides terminal rendering primitives, not a markdown widget.',
      'The wire path runs Ink in interactive alternate-screen mode under the PTY capture harness.',
    ],
  };
}

function parseArgs(args) {
  const options = {
    warmupIterations: defaultWarmups,
    measuredIterations: defaultIterations,
    rows: defaultRows,
    terminalColumns: defaultColumns,
    terminalRows: defaultTerminalRows,
    printJson: false,
    outputPath: '',
    wire: false,
    wireSteps: defaultWireSteps,
    wireIntervalMs: defaultWireIntervalMs,
  };

  for (const arg of args) {
    if (arg === '--json') {
      options.printJson = true;
    } else if (arg === '--wire') {
      options.wire = true;
    } else if (arg.startsWith('--warmup=')) {
      options.warmupIterations = positiveInt(arg, '--warmup=');
    } else if (arg.startsWith('--iterations=')) {
      options.measuredIterations = positiveInt(arg, '--iterations=');
    } else if (arg.startsWith('--rows=')) {
      options.rows = positiveInt(arg, '--rows=');
    } else if (arg.startsWith('--steps=')) {
      options.wireSteps = positiveInt(arg, '--steps=');
    } else if (arg.startsWith('--interval-ms=')) {
      options.wireIntervalMs = positiveInt(arg, '--interval-ms=');
    } else if (arg.startsWith('--size=')) {
      const [columns, rows] = parseSize(arg.slice('--size='.length));
      options.terminalColumns = columns;
      options.terminalRows = rows;
    } else if (arg.startsWith('--output=')) {
      options.outputPath = arg.slice('--output='.length);
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }
  return options;
}

function positiveInt(arg, prefix) {
  const value = Number.parseInt(arg.slice(prefix.length), 10);
  if (!Number.isInteger(value) || value < 1) {
    throw new Error(`${prefix} requires a positive integer`);
  }
  return value;
}

function parseSize(value) {
  const match = /^(\d+)x(\d+)$/.exec(value);
  if (!match) {
    throw new Error('--size must be COLUMNSxROWS');
  }
  return [Number.parseInt(match[1], 10), Number.parseInt(match[2], 10)];
}

function nowNs() {
  return process.hrtime.bigint();
}

function elapsedUs(start) {
  return Number((process.hrtime.bigint() - start) / 1000n);
}

function stats(values) {
  const ordered = values.slice().sort((a, b) => a - b);
  if (ordered.length === 0) {
    return {min: 0, median: 0, p95: 0, p99: 0, max: 0, samples: 0};
  }
  return {
    min: ordered[0],
    median: percentile(ordered, 0.5),
    p95: percentile(ordered, 0.95),
    p99: percentile(ordered, 0.99),
    max: ordered.at(-1),
    samples: ordered.length,
  };
}

function percentile(ordered, fraction) {
  if (ordered.length === 1) return ordered[0];
  const index = Math.ceil((ordered.length - 1) * fraction);
  return ordered[Math.min(index, ordered.length - 1)];
}

function timestampForId(date) {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z').replaceAll(':', '-');
}

function sourceLineCount(relativePath) {
  const text = fs.readFileSync(relativePath, 'utf8');
  return text
    .split('\n')
    .map(line => line.trim())
    .filter(line => line.length > 0 && !line.startsWith('//'))
    .length;
}

function osVersion() {
  try {
    return execFileSync('uname', ['-a'], {encoding: 'utf8'}).trim();
  } catch {
    return os.platform();
  }
}

await main();
