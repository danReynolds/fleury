// Performance regression gate for the M1/M2 hardening. Runs in `dart test`, so a
// future change that erodes a measured win fails CI. Reuses the benchmark
// functions (one source of truth) — byte metrics are asserted with absolute
// thresholds (deterministic), timing metrics with RELATIVE ones (robust to CI
// load). See benchmark/BASELINE.md for the recorded "where we started" numbers.

import '../benchmark/mcp_benchmarks.dart';
import 'package:test/test.dart';

void main() {
  group('MCP perf gate — protects the M1/M2 wins against regression', () {
    final dashboard = buildDashboard(rows: 80);

    test('the dashboard fixture is representative (hundreds of nodes)', () {
      expect(dashboard.nodeCount, greaterThan(300));
    });

    test('WS-1: a delta is a tiny fraction of a full re-read', () {
      final d = deltaVsFull(dashboard);
      // Baseline ~0.3%. A regression that fattened the notification (or shrank
      // the gap) past 2% would mean delta push stopped paying for itself.
      expect(
        d['deltaPctOfFull'] as num,
        lessThan(2.0),
        reason: 'delta notify (${d['deltaNotifyBytes']}B) vs full '
            '(${d['fullReadBytes']}B) must stay far below a full re-read',
      );
      // Even acting on the change (delta + reading the one node) stays <5%.
      expect(d['actPctOfFull'] as num, lessThan(5.0));
    });

    test('WS-9/WS-4: typed-affordance + untrusted marker overhead stays small',
        () {
      final a = affordanceOverhead(dashboard);
      // Baseline ~2.4%. Gate at 10% so a future schema bloat is caught before it
      // meaningfully grows every get_ui.
      expect(
        a['overheadPct'] as num,
        lessThan(10.0),
        reason: 'valueSchema + untrustedContent added '
            '${a['overheadBytes']}B (+${a['overheadPct']}%)',
      );
    });

    test('WS-2: capped settle beats the uncapped (old) latency on a ticking app',
        () async {
      final st = await settleLatency();
      // Relative assertions — robust to absolute CI timing. Baseline ~3.7x.
      expect(
        st['cappedMs'] as num,
        lessThan((st['uncappedMs'] as num) * 0.7),
        reason: 'capped ${st['cappedMs']}ms must beat uncapped '
            '${st['uncappedMs']}ms (the never-close case)',
      );
      expect(st['speedup'] as num, greaterThan(1.5));
    });
  });
}
