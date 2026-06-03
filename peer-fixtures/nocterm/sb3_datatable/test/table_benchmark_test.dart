import 'package:fleury_peer_nocterm_sb3_datatable/table_app.dart';
import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart' hide isEmpty;

void main() {
  test('Nocterm SB.3 fixture exercises lazy table-list adapters', () async {
    await testNocterm('SB.3 Nocterm data table fixture', (tester) async {
      await tester.pumpComponent(
        const Sb3NoctermDataTable(rowCount: 1000, width: 120, height: 24),
      );
      final state = tester.findState<Sb3NoctermDataTableState>();

      var snapshot = state.snapshot();
      expect(snapshot.rowCount, 1000);
      expect(snapshot.selectedRow, 0);
      expect(snapshot.selectedRowId, rowId(0));
      expect(
        snapshot.visibleWindowRows,
        lessThanOrEqualTo(state.visibleCapacity()),
      );
      expect(tester.terminalState.containsText(rowId(0)), isTrue);

      state.arrowDown();
      await tester.pump();
      snapshot = state.snapshot();
      expect(snapshot.selectedRow, 1);
      expect(snapshot.selectedRowId, rowId(1));
      expect(tester.terminalState.containsText(rowId(1)), isTrue);

      state.pageDown();
      await tester.pump();
      snapshot = state.snapshot();
      expect(snapshot.selectedRow, 1 + state.visibleCapacity());
      expect(tester.terminalState.containsText(snapshot.selectedRowId), isTrue);

      state.jumpToEnd();
      await tester.pump();
      snapshot = state.snapshot();
      expect(snapshot.selectedRow, 999);
      expect(snapshot.selectedRowId, rowId(999));
      expect(
        snapshot.visibleWindowRows,
        lessThanOrEqualTo(state.visibleCapacity()),
      );
      expect(tester.terminalState.containsText(rowId(999)), isTrue);

      state.copySelectedRow();
      expect(state.lastCopiedText, expectedSelectedTsv(999));
      expect(unsafeCopyTextCount(state.lastCopiedText), 0);

      final visible = tester.terminalState.getText();
      expect(unsafeVisibleTextCount(visible), 0);
    }, size: const Size(120, 32));
  });
}
