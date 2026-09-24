import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/runtime/inline_terminal_lease.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late String path;
  const terminal = CellSize(80, 24);
  const mode = TerminalMode.inline(
    rows: 4,
    keyboardProtocol: KeyboardProtocolMode.legacy,
  );

  setUp(() {
    directory = Directory.systemTemp.createTempSync('fleury_inline_lease_');
    path = '${directory.path}/lease.json';
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'no lease keeps fullscreen recovery; clean release needs no second pop',
    () {
      expect(inlineTerminalRecovery(path, terminal), isNull);
      writeInlineTerminalLease(path, mode: mode, active: false);
      expect(inlineTerminalRecovery(path, terminal), isEmpty);
      expect(File('$path.pending').existsSync(), isFalse);
    },
  );

  test(
    'crash clears only the committed region and restores actual mode tier',
    () {
      writeInlineTerminalLease(
        path,
        mode: mode,
        active: true,
        terminal: terminal,
        top: 8,
        rows: 4,
      );
      final recovery = inlineTerminalRecovery(path, terminal)!;
      expect(
        recovery,
        startsWith(
          '\x1B[0m\x1B[9;1H\x1B[2K\x1B[10;1H\x1B[2K'
          '\x1B[11;1H\x1B[2K\x1B[12;1H\x1B[2K\x1B[9;1H',
        ),
      );
      expect(recovery, contains('\x1B[?7h'));
      expect(recovery, contains('\x1B[?25h'));
      expect(recovery, isNot(contains('1049')));
      expect(recovery, isNot(contains('\x1B[<1u')));

      writeInlineTerminalLease(
        path,
        mode: const TerminalMode.inline(rows: 4),
        active: true,
      );
      expect(inlineTerminalRecovery(path, terminal), contains('\x1B[<1u'));
    },
  );

  test('resize after allocation never clears using a stale origin', () {
    writeInlineTerminalLease(
      path,
      mode: mode,
      active: true,
      terminal: terminal,
      top: 8,
      rows: 4,
    );
    final recovery = inlineTerminalRecovery(path, const CellSize(40, 12))!;
    expect(recovery, startsWith('\r\n'));
    expect(recovery, isNot(contains('\x1B[2K')));
    expect(recovery, isNot(contains('\x1B[2J')));
    expect(recovery, isNot(contains('1049')));
  });

  test(
    'crash pops an owned pointer shape and leaves an unowned stack alone',
    () {
      writeInlineTerminalLease(
        path,
        mode: mode,
        active: true,
        pointerStackOwned: true,
      );
      expect(
        inlineTerminalRecovery(path, terminal),
        contains('\x1B]22;<\x1B\\'),
      );
      writeInlineTerminalLease(path, mode: mode, active: true);
      expect(
        inlineTerminalRecovery(path, terminal),
        isNot(contains('\x1B]22;')),
      );
    },
  );

  test('uncommitted geometry restores modes without guessing rows', () {
    writeInlineTerminalLease(path, mode: mode, active: true);
    expect(inlineTerminalRecovery(path, terminal), isNot(contains('\x1B[2K')));
  });

  test('invalid geometry and corrupt metadata cannot clear unrelated rows', () {
    for (final region in [
      {'cols': 80, 'terminalRows': 24, 'top': -1, 'rows': 4},
      {'cols': 80, 'terminalRows': 24, 'top': 23, 'rows': 4},
      {'cols': 80, 'terminalRows': 24, 'top': 2.5, 'rows': 4},
      {'cols': 80, 'terminalRows': 24, 'top': '\x1B[2J', 'rows': 4},
    ]) {
      writeInlineTerminalLease(path, mode: mode, active: true);
      final data = jsonDecode(File(path).readAsStringSync()) as Map;
      data['region'] = region;
      File(path).writeAsStringSync(jsonEncode(data));
      final recovery = inlineTerminalRecovery(path, terminal)!;
      expect(recovery, isNot(contains('\x1B[2K')));
      expect(recovery, isNot(contains('\x1B[2J')));
    }
    for (final corrupt in ['not json', '{"version":999}', 'x' * 4097]) {
      File(path).writeAsStringSync(corrupt);
      final recovery = inlineTerminalRecovery(path, terminal)!;
      expect(recovery, contains('\x1B[?7h'));
      expect(recovery, isNot(contains('1049')));
      expect(recovery, isNot(contains('\x1B[<1u')));
      expect(recovery, isNot(contains('\x1B[2K')));
    }
  });
}
