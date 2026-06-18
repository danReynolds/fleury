import 'package:fleury/src/terminal/capabilities.dart';
import 'package:fleury/src/terminal/terminal_probe.dart';
import 'package:test/test.dart';

class _FakeTransport implements TerminalProbeTransport {
  _FakeTransport(this.reply);
  final List<int> reply;
  String? sent;

  @override
  Future<List<int>> request(String bytes, {required Duration timeout}) async {
    sent = bytes;
    return reply;
  }
}

void main() {
  group('probeImageProtocol', () {
    test('confirms Kitty from a graphics-OK reply', () async {
      // A real Kitty graphics OK reply (APC _G … ST) followed by the DA1 reply.
      final reply = '\x1B_Gi=31;OK\x1B\\\x1B[?62;4c'.codeUnits;
      final transport = _FakeTransport(reply);
      expect(await probeImageProtocol(transport), ImageProtocol.kitty);
      expect(transport.sent, contains('_G'),
          reason: 'sent the Kitty graphics query');
    });

    test('returns null when only DA replies (terminal lacks graphics)', () async {
      final reply = '\x1B[?62;4c'.codeUnits; // DA1 only — no graphics APC.
      expect(await probeImageProtocol(_FakeTransport(reply)), isNull);
    });

    test('returns null on no reply (timeout)', () async {
      expect(await probeImageProtocol(_FakeTransport(const <int>[])), isNull);
    });

    test('swallows a transport failure and reports no protocol', () async {
      final transport = _ThrowingTransport();
      expect(await probeImageProtocol(transport), isNull);
    });
  });
}

class _ThrowingTransport implements TerminalProbeTransport {
  @override
  Future<List<int>> request(String bytes, {required Duration timeout}) async {
    throw StateError('write failed');
  }
}
