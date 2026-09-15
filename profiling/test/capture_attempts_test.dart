import 'package:fleury_profiling/capture_attempts.dart';
import 'package:test/test.dart';

void main() {
  test('partial and all-failed captures retain failures and never pass', () {
    final capture = CaptureAttempts(2);
    capture.runs.add({
      'status': 'failed',
      'error': 'timeout',
      'rawLatencyMs': [1.0]
    });
    expect(capture.complete, isFalse);
    capture.runs.add({'status': 'complete'});
    expect(capture.complete, isFalse);
    expect(capture.toJson()['failedRuns'], 1);
    expect(capture.runs.first['rawLatencyMs'], [1.0]);
    final allFailed = CaptureAttempts(1)..runs.add({'status': 'failed'});
    expect(allFailed.toJson()['status'], 'incomplete');
  });
}
