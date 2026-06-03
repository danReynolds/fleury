import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import {execFileSync} from 'node:child_process';
import React from 'react';
import {render} from 'ink-testing-library';
import {InkSb2App, InkSb2Fixture} from '../lib/text_editing_app.js';

const schemaVersion = 1;
const peerId = 'ink';
const peerName = 'Ink + Ink ecosystem inputs';
const inkVersion = '7.0.5';
const reactVersion = '19.2.7';
const inkTextInputVersion = '6.0.0';
const reactInkTextareaVersion = '0.1.3';
const testingLibraryVersion = '4.0.0';
const scenarioId = 'SB.2';
const defaultWarmups = 1;
const defaultIterations = 5;
const defaultTextChars = 10000;
const defaultColumns = 120;
const defaultRows = 32;

function main() {
  const options = parseArgs(process.argv.slice(2));
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
  console.log('Ink SB.2 text editing fixture');
  console.log(`Run: ${artifact.runId}`);
  console.log(`Text chars: ${options.textChars}`);
  console.log(`Iterations: ${options.measuredIterations}`);
  console.log(`cursorMoveUs p95: ${metrics.cursorMoveUs.p95}`);
  console.log(`pasteCompleteUs p95: ${metrics.pasteCompleteUs.p95}`);
  if (options.outputPath) {
    console.log(`Saved ${options.outputPath}`);
  }
}

function runSample(options) {
  const rssBefore = process.memoryUsage().rss;
  const mountStart = nowNs();
  const fixture = new InkSb2Fixture({
    textChars: options.textChars,
    columns: options.terminalColumns,
    rows: options.terminalRows
  });
  const mountUs = elapsedUs(mountStart);

  const firstRenderStart = nowNs();
  const rendered = render(React.createElement(InkSb2App, {fixture}));
  const firstFrame = rendered.lastFrame() ?? '';
  const firstRenderUs = elapsedUs(firstRenderStart);

  const cursorStart = nowNs();
  fixture.cursorMove();
  const cursorMoveUs = elapsedUs(cursorStart);

  const insertionStart = nowNs();
  fixture.insertionDeletion();
  const insertionDeletionUs = elapsedUs(insertionStart);

  const selectionStart = nowNs();
  fixture.replaceSelection();
  const selectionUs = elapsedUs(selectionStart);

  const undoStart = nowNs();
  fixture.undo();
  fixture.redo();
  const undoRedoUs = elapsedUs(undoStart);

  const historyStart = nowNs();
  fixture.historyPrevious();
  fixture.historyPrevious();
  const historyNavigationUs = elapsedUs(historyStart);

  const completionStart = nowNs();
  fixture.acceptCompletion();
  const completionAcceptUs = elapsedUs(completionStart);

  const pasteStart = nowNs();
  fixture.pasteLargeText();
  const pasteCompleteUs = elapsedUs(pasteStart);

  const queryStart = nowNs();
  rendered.rerender(React.createElement(InkSb2App, {fixture}));
  const frame = `${firstFrame}\n${rendered.lastFrame() ?? ''}`;
  const state = fixture.stateSnapshot({frame});
  const semanticOrTestQueryUs = elapsedUs(queryStart);
  rendered.unmount();

  return {
    mountUs,
    firstRenderUs,
    cursorMoveUs,
    insertionDeletionUs,
    selectionUs,
    undoRedoUs,
    historyNavigationUs,
    completionAcceptUs,
    pasteCompleteUs,
    semanticOrTestQueryUs,
    rssDeltaBytes: Math.max(0, process.memoryUsage().rss - rssBefore),
    mixedWidthValid: state.mixedWidthValid,
    selectionUndoCorrect: state.selectionReplacementValid && state.undoRedoCorrect,
    redactedValueStaysSafe: !state.secretRawVisible,
    historyCorrect: state.historyNavigationCorrect,
    completionCorrect: state.completionAccepted,
    pasteCorrect: state.pasteInserted,
    editorLength: state.editorLength,
    editorLineCount: state.editorLineCount,
    composerValue: state.composerValue
  };
}

function buildArtifact(options, samples) {
  const capturedAt = new Date();
  const last = samples.at(-1);
  const appLines = sourceLineCount('lib/text_editing_app.js');
  const benchmarkLines = sourceLineCount('bin/sb2_text_editing_benchmark.js');
  const testLines = sourceLineCount('test/text_editing_app.test.js');

  return {
    schemaVersion,
    kind: 'fleuryPeerBenchmarkRun',
    runId: `ink-sb2-text-editing-${timestampForId(capturedAt)}`,
    peerId,
    scenarioId,
    capturedAt: capturedAt.toISOString(),
    source: {
      name: peerName,
      version: `Ink ${inkVersion} / React ${reactVersion} / ink-text-input ${inkTextInputVersion} / react-ink-textarea ${reactInkTextareaVersion}`,
      url: 'https://www.npmjs.com/package/ink'
    },
    environment: {
      machine: os.hostname() || 'unknown',
      operatingSystem: os.platform(),
      operatingSystemVersion: osVersion(),
      runtime: `${process.version} / Ink ${inkVersion} / React ${reactVersion} / ink-text-input ${inkTextInputVersion} / react-ink-textarea ${reactInkTextareaVersion}`,
      terminalMode: 'ink-testing-library-memory',
      terminalSize: {
        columns: options.terminalColumns,
        rows: options.terminalRows
      }
    },
    fixture: {
      workingDirectory: 'peer-fixtures/ink/sb2_text_editing',
      command: [
        'node',
        'bin/sb2_text_editing_benchmark.js',
        `--warmup=${options.warmupIterations}`,
        `--iterations=${options.measuredIterations}`,
        `--text-chars=${options.textChars}`,
        '--json'
      ],
      warmupIterations: options.warmupIterations,
      measuredIterations: options.measuredIterations
    },
    metrics: {
      mountUs: stats(samples.map(sample => sample.mountUs)),
      firstRenderUs: stats(samples.map(sample => sample.firstRenderUs)),
      cursorMoveUs: stats(samples.map(sample => sample.cursorMoveUs)),
      insertionDeletionUs: stats(samples.map(sample => sample.insertionDeletionUs)),
      selectionUs: stats(samples.map(sample => sample.selectionUs)),
      undoRedoUs: stats(samples.map(sample => sample.undoRedoUs)),
      historyNavigationUs: stats(samples.map(sample => sample.historyNavigationUs)),
      completionAcceptUs: stats(samples.map(sample => sample.completionAcceptUs)),
      pasteCompleteUs: stats(samples.map(sample => sample.pasteCompleteUs)),
      semanticOrTestQueryUs: stats(samples.map(sample => sample.semanticOrTestQueryUs)),
      rssDeltaBytes: Math.max(...samples.map(sample => sample.rssDeltaBytes)),
      lineOfCodeCount: appLines,
      benchmarkLineOfCodeCount: benchmarkLines,
      testLineOfCodeCount: testLines,
      textCharsRequested: options.textChars,
      editorLength: last.editorLength,
      editorLineCount: last.editorLineCount,
      composerValue: last.composerValue,
      adapterOwnedFeatureCount: 4
    },
    correctness: [
      {
        gate: 'mixed-width text remains valid',
        pass: samples.every(sample => sample.mixedWidthValid && sample.pasteCorrect),
        evidence: `react-ink-textarea rendered a ${options.textChars} character mixed-width editor value while fixture state retained emoji, CJK, combining text, and the paste marker.`
      },
      {
        gate: 'selection and undo state are correct',
        pass: samples.every(sample => sample.selectionUndoCorrect),
        evidence: 'Selection replacement and redo were fixture-owned adapters; undo state was verified around the react-ink-textarea-controlled value.'
      },
      {
        gate: 'redacted value stays redacted',
        pass: samples.every(sample => sample.redactedValueStaysSafe),
        evidence: 'ink-text-input mask rendering did not expose the raw secret in Ink frames.'
      }
    ],
    ergonomics: {
      lineOfCodeCount: appLines,
      benchmarkLineOfCodeCount: benchmarkLines,
      testLineOfCodeCount: testLines,
      appFile: 'lib/text_editing_app.js',
      benchmarkFile: 'bin/sb2_text_editing_benchmark.js',
      testFile: 'test/text_editing_app.test.js',
      peerOwnedReactRenderer: true,
      peerOwnedTextareaComponent: true,
      peerOwnedTextInputComponent: true,
      peerOwnedMaskedInputDisplay: true,
      appOwnedSelection: true,
      appOwnedRedo: true,
      appOwnedHistory: true,
      appOwnedCompletion: true,
      semanticGraphAvailable: false,
      testQueryViaInkFrameAndAppState: true
    },
    artifacts: [
      {
        kind: 'source',
        path: 'peer-fixtures/ink/sb2_text_editing/lib/text_editing_app.js'
      },
      {
        kind: 'benchmark',
        path: 'peer-fixtures/ink/sb2_text_editing/bin/sb2_text_editing_benchmark.js'
      },
      {
        kind: 'test',
        path: 'peer-fixtures/ink/sb2_text_editing/test/text_editing_app.test.js'
      }
    ],
    notes: [
      'This is an Ink testing-library memory fixture, not a real-terminal run.',
      'Ink 7.0.5 supplies the React renderer; react-ink-textarea 0.1.3 supplies the multiline textarea component; ink-text-input 6.0.0 supplies the single-line and masked input components.',
      'react-ink-textarea documents no selection and no redo, so selection replacement and redo are fixture-owned adapters. Submission history and completion acceptance are also fixture-owned app code.',
      'Ink exposes rendered frames and app state for this fixture, not a Fleury-style semantic app graph.',
      'Timing is local-machine evidence and should not be used as a public superiority claim without repeated peer runs.'
    ]
  };
}

function parseArgs(args) {
  const options = {
    warmupIterations: defaultWarmups,
    measuredIterations: defaultIterations,
    textChars: defaultTextChars,
    terminalColumns: defaultColumns,
    terminalRows: defaultRows,
    printJson: false,
    outputPath: ''
  };
  for (const arg of args) {
    if (arg === '--json') {
      options.printJson = true;
    } else if (arg.startsWith('--warmup=')) {
      options.warmupIterations = positiveOrZeroInt(arg.slice('--warmup='.length), 'warmup');
    } else if (arg.startsWith('--iterations=')) {
      options.measuredIterations = positiveInt(arg.slice('--iterations='.length), 'iterations');
    } else if (arg.startsWith('--text-chars=')) {
      options.textChars = positiveInt(arg.slice('--text-chars='.length), 'text-chars');
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

function positiveInt(value, label) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`--${label} must be positive`);
  }
  return parsed;
}

function positiveOrZeroInt(value, label) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new Error(`--${label} must be zero or positive`);
  }
  return parsed;
}

function parseSize(value) {
  const parts = value.split('x');
  if (parts.length !== 2) {
    throw new Error('--size must be COLUMNSxROWS');
  }
  return [positiveInt(parts[0], 'size columns'), positiveInt(parts[1], 'size rows')];
}

function nowNs() {
  return process.hrtime.bigint();
}

function elapsedUs(start) {
  return Number((process.hrtime.bigint() - start) / 1000n);
}

function stats(values) {
  const sorted = [...values].sort((a, b) => a - b);
  if (sorted.length === 0) {
    return {min: 0, median: 0, p95: 0, p99: 0, max: 0, samples: 0};
  }
  return {
    min: sorted[0],
    median: percentile(sorted, 0.50),
    p95: percentile(sorted, 0.95),
    p99: percentile(sorted, 0.99),
    max: sorted.at(-1),
    samples: sorted.length
  };
}

function percentile(values, fraction) {
  if (values.length === 1) {
    return values[0];
  }
  let index = Math.ceil((values.length - 1) * fraction);
  if (index >= values.length) {
    index = values.length - 1;
  }
  return values[index];
}

function sourceLineCount(relativePath) {
  const text = fs.readFileSync(relativePath, 'utf8');
  return text
    .split('\n')
    .map(line => line.trim())
    .filter(line => line !== '' && !line.startsWith('//'))
    .length;
}

function osVersion() {
  try {
    return execFileSync('uname', ['-a'], {encoding: 'utf8'}).trim();
  } catch {
    return os.platform();
  }
}

function timestampForId(value) {
  return value.toISOString().replace(/\.\d{3}Z$/, 'Z').replaceAll(':', '-');
}

main();
