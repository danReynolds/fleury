import 'package:fleury_peer_nocterm_sb4_log_region/log_region_app.dart';
import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart' hide isEmpty;

void main() {
  test('Nocterm SB.4 fixture exercises log viewport adapters', () async {
    await testNocterm('SB.4 Nocterm log region fixture', (tester) async {
      await tester.pumpComponent(
        const Sb4NoctermLogRegion(rowCount: 1000, width: 120, height: 24),
      );
      final state = tester.findState<Sb4NoctermLogRegionState>();

      expect(state.snapshot().tailAnchored, isTrue);
      expect(tester.terminalState.containsText(logKey(999)), isTrue);

      state.appendBurst(128);
      await tester.pump();
      state.scrollToTail();
      await tester.pump();

      final lastIndex = 1127;
      expect(state.snapshot().tailAnchored, isTrue);
      expect(state.snapshot().selectedKey, logKey(lastIndex));
      expect(tester.terminalState.containsText(logKey(lastIndex)), isTrue);

      state.jumpToScrollback(500);
      await tester.pump();
      expect(state.snapshot().selectedKey, logKey(500));
      expect(tester.terminalState.containsText(logKey(500)), isTrue);

      state.scrollToTail();
      await tester.pump();
      state.copySelectedEntry();
      expect(state.lastCopiedText, expectedCopiedText(lastIndex));
      expect(unsafeCopyTextCount(state.lastCopiedText), 0);

      final matches = state.filterQuery(appendFilterQuery());
      await tester.pump();
      state.scrollDisplayedToEnd();
      await tester.pump();
      expect(matches, 128);
      expect(state.snapshot().displayedCount, 128);
      expect(state.snapshot().selectedKey, logKey(lastIndex));
      expect(tester.terminalState.containsText(logKey(lastIndex)), isTrue);

      final visible = tester.terminalState.getText();
      expect(unsafeVisibleTextCount(visible), 0);
    }, size: const Size(120, 32));
  });
}
