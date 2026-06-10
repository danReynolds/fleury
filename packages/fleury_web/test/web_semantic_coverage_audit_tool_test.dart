@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'fleury_web_semantic_coverage_audit_test_',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'web semantic coverage audit summarizes capture fallback reliance',
    () async {
      _writeCapture(
        '${tempDir.path}/normal-a.json',
        scenarioId: 'normal-80x24',
        capturedAt: '2026-06-08T01:00:00.000000Z',
        frames: [
          _webFrame(totalFrameMicros: 10000, domApplyMicros: 3000),
          _webFrame(
            totalFrameMicros: 12000,
            domApplyMicros: 3500,
            semanticFallbackNodeCount: 2,
            semanticUncoveredCellCount: 6,
          ),
        ],
      );
      _writeCapture(
        '${tempDir.path}/normal-b.json',
        scenarioId: 'normal-80x24',
        capturedAt: '2026-06-08T01:05:00.000000Z',
        frames: [_webFrame(totalFrameMicros: 11000, domApplyMicros: 3000)],
      );
      File('${tempDir.path}/not-a-capture.json').writeAsStringSync('{}');

      final jsonOutputPath = '${tempDir.path}/semantic-coverage.json';
      final jsonResult = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_semantic_coverage_audit.dart',
        '--input=${tempDir.path}',
        '--max-fallback-cells=6',
        '--max-fallback-frame-percent=34',
        '--json-output=$jsonOutputPath',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(jsonResult.exitCode, 0, reason: jsonResult.stderr.toString());
      final audit = jsonDecode(jsonResult.stdout.toString());
      expect(audit, isA<Map<String, Object?>>());
      expect(
        (audit as Map<String, Object?>)['kind'],
        'fleuryWebSemanticCoverageAudit',
      );
      expect(audit['captureCount'], 2);
      expect(audit['frameCount'], 3);
      expect(audit['fallbackFrameCount'], 1);
      expect(audit['fallbackCellCount'], 6);
      expect(audit['maxFallbackCellsInFrame'], 6);
      final persisted =
          jsonDecode(File(jsonOutputPath).readAsStringSync())
              as Map<String, Object?>;
      expect(persisted['kind'], 'fleuryWebSemanticCoverageAudit');
      expect(persisted['strictPass'], isTrue);
      expect(persisted['fallbackCellCount'], 6);
      final topFallbackCaptures = audit['topFallbackCaptures'] as List<Object?>;
      expect(topFallbackCaptures, hasLength(1));
      expect(
        topFallbackCaptures.single,
        isA<Map<String, Object?>>()
            .having((capture) => capture['file'], 'file', 'normal-a.json')
            .having(
              (capture) => capture['scenarioId'],
              'scenarioId',
              'normal-80x24',
            )
            .having(
              (capture) => capture['fallbackCellCount'],
              'fallbackCellCount',
              6,
            ),
      );
      expect(audit['strictPass'], isTrue);
      final scenarios = audit['scenarios'] as List<Object?>;
      final scenario = scenarios.single as Map<String, Object?>;
      expect(scenario['id'], 'normal-80x24');
      expect(scenario['captureCount'], 2);
      expect(scenario['frameCount'], 3);
      expect(scenario['fallbackNodeCount'], 2);
      expect(scenario['latestCapture'], 'normal-b.json');
      expect(scenario['topFallbackCaptures'], hasLength(1));
      expect(
        scenario['gates'] as List<Object?>,
        contains(
          isA<Map<String, Object?>>()
              .having((gate) => gate['id'], 'id', 'maxFallbackCellsInFrame')
              .having((gate) => gate['passed'], 'passed', isTrue),
        ),
      );

      final markdownPath = '${tempDir.path}/coverage.md';
      final markdownResult = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_semantic_coverage_audit.dart',
        '--input=${tempDir.path}',
        '--output=$markdownPath',
        '--max-fallback-cells=6',
      ], workingDirectory: Directory.current.path);

      expect(
        markdownResult.exitCode,
        0,
        reason: markdownResult.stderr.toString(),
      );
      final markdown = File(markdownPath).readAsStringSync();
      expect(markdown, contains('Fleury Web Semantic Coverage Audit'));
      expect(markdown, contains('normal-80x24'));
      expect(markdown, contains('Top Fallback Captures'));
      expect(markdown, contains('normal-a.json'));
      expect(markdown, contains('Fallback Cells'));
      expect(markdown, contains('pass'));
    },
  );

  test(
    'web semantic coverage audit strict mode fails supplied gates',
    () async {
      _writeCapture(
        '${tempDir.path}/normal-a.json',
        scenarioId: 'normal-80x24',
        capturedAt: '2026-06-08T01:00:00.000000Z',
        frames: [
          _webFrame(
            totalFrameMicros: 12000,
            domApplyMicros: 3500,
            semanticFallbackNodeCount: 1,
            semanticUncoveredCellCount: 3,
          ),
        ],
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/web_semantic_coverage_audit.dart',
        '--input=${tempDir.path}',
        '--max-fallback-cells=0',
        '--strict',
        '--json',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 1);
      final audit =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(audit['strictPass'], isFalse);
      final scenarios = audit['scenarios'] as List<Object?>;
      final scenario = scenarios.single as Map<String, Object?>;
      expect(scenario['strictPass'], isFalse);
      expect(
        scenario['gates'] as List<Object?>,
        contains(
          isA<Map<String, Object?>>()
              .having((gate) => gate['id'], 'id', 'maxFallbackCellsInFrame')
              .having((gate) => gate['passed'], 'passed', isFalse),
        ),
      );
    },
  );

  test('web semantic coverage audit rejects empty json output path', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/web_semantic_coverage_audit.dart',
      '--input=${tempDir.path}',
      '--json-output=',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains('--json-output requires a non-empty path.'),
    );
  });
}

void _writeCapture(
  String path, {
  required String scenarioId,
  required String capturedAt,
  required List<Map<String, Object?>> frames,
}) {
  File(path).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'kind': 'fleuryWebFrameCapture',
      'capturedAt': capturedAt,
      'scenario': {'id': scenarioId},
      'frameBudgetMs': 16.67,
      'frames': frames,
    })}\n',
  );
}

Map<String, Object?> _webFrame({
  required int totalFrameMicros,
  required int domApplyMicros,
  int semanticFallbackNodeCount = 0,
  int semanticUncoveredCellCount = 0,
}) {
  return <String, Object?>{
    'reason': 'benchmark',
    'coalescedReasons': ['benchmark'],
    'viewport': {'cols': 80, 'rows': 24},
    'damageSource': 'paintDamage',
    'fullRepaint': false,
    'metricsChanged': false,
    'dirtyRowCount': 1,
    'dirtyCellEstimate': 80,
    'spanCount': 4,
    'domNodesCreated': 4,
    'rowsReplaced': 1,
    'styleCacheHits': 4,
    'styleCacheMisses': 0,
    'widthCacheHits': 0,
    'widthCacheMisses': 0,
    'metricsReadCount': 1,
    'semanticNodeCount': 2,
    'semanticAddedNodeCount': 0,
    'semanticRemovedNodeCount': 0,
    'semanticUpdatedNodeCount': 1,
    'semanticFallbackNodeCount': semanticFallbackNodeCount,
    'semanticUncoveredCellCount': semanticUncoveredCellCount,
    'runtimeRenderMicros': 3000,
    'spanBuildMicros': 1000,
    'domApplyMicros': domApplyMicros,
    'semanticApplyMicros': 1000,
    'totalFrameMicros': totalFrameMicros,
  };
}
