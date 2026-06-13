// The semantic wire diff must be indistinguishable from full-resend on the
// client: replaying FULL + PATCH frames reproduces, frame for frame, the exact
// tree a full snapshot would have — while shipping a fraction of the bytes.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_semantics.dart';
import 'package:test/test.dart';

/// A realistic agent tree: status + a message list + an input. [tick] perturbs
/// only the status counter and the last message — the common streaming case.
SemanticInspectionSnapshot _snap({required int messages, required int tick}) {
  return SemanticTree(
    root: SemanticNode(
      id: const SemanticNodeId('root'),
      role: SemanticRole.app,
      children: [
        SemanticNode(
          id: const SemanticNodeId('status'),
          role: SemanticRole.status,
          label: 'streaming — $tick tokens',
        ),
        SemanticNode(
          id: const SemanticNodeId('messages'),
          role: SemanticRole.messageList,
          children: [
            for (var m = 0; m < messages; m++)
              SemanticNode(
                id: SemanticNodeId('msg:$m'),
                role: SemanticRole.message,
                label: m == messages - 1
                    ? 'assistant: step $tick'
                    : 'turn $m: a settled line',
                state: SemanticState({'index': m}),
              ),
          ],
        ),
        const SemanticNode(
          id: SemanticNodeId('input'),
          role: SemanticRole.textField,
          label: 'Message',
          actions: {SemanticAction.submit},
        ),
      ],
    ),
  ).toInspectionSnapshot();
}

String _canonical(SemanticTree tree) =>
    jsonEncode(tree.toInspectionSnapshot().toJson());

Map<String, Object?> _envelope(List<int> bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;

void main() {
  group('SemanticsWire encode/decode', () {
    test('a FULL then PATCH stream reproduces every frame exactly', () {
      final encoder = SemanticsWireEncoder();
      final decoder = SemanticsWireDecoder();

      for (var tick = 0; tick < 50; tick++) {
        final snapshot = _snap(messages: 40, tick: tick);
        final bytes = encoder.encode(snapshot)!;
        if (tick == 0) {
          expect(_envelope(bytes)['mode'], 'full');
        } else {
          expect(_envelope(bytes)['mode'], 'patch',
              reason: 'steady frames are patches, not full resends');
        }
        final rebuilt = decoder.apply(bytes)!;
        // The client's reconstructed tree equals a full-resend of this frame.
        expect(_canonical(rebuilt), _canonical(snapshot.toSemanticTree()),
            reason: 'frame $tick diverged');
      }
    });

    test('a steady patch is a tiny fraction of the full frame', () {
      final encoder = SemanticsWireEncoder();
      final full = encoder.encode(_snap(messages: 240, tick: 0))!;
      final patch = encoder.encode(_snap(messages: 240, tick: 1))!;
      expect(_envelope(patch)['mode'], 'patch');
      // The full frame carries 244 nodes; the patch carries the 2 that moved.
      expect(patch.length * 20, lessThan(full.length),
          reason: 'patch ${patch.length}B vs full ${full.length}B');
      final set = _envelope(patch)['set'] as List;
      expect(set, hasLength(2), reason: 'only status + last message changed');
    });

    test('an unchanged frame encodes to nothing', () {
      final encoder = SemanticsWireEncoder();
      expect(encoder.encode(_snap(messages: 10, tick: 7)), isNotNull);
      expect(encoder.encode(_snap(messages: 10, tick: 7)), isNull,
          reason: 'no exposed semantics changed → zero bytes');
    });

    test('structural add and remove round-trip through patches', () {
      final encoder = SemanticsWireEncoder();
      final decoder = SemanticsWireDecoder();

      decoder.apply(encoder.encode(_snap(messages: 5, tick: 0))!);
      // Grow the list by one message.
      final grown = decoder.apply(encoder.encode(_snap(messages: 6, tick: 1))!)!;
      expect(_canonical(grown),
          _canonical(_snap(messages: 6, tick: 1).toSemanticTree()));
      // Shrink it by two.
      final shrunk =
          decoder.apply(encoder.encode(_snap(messages: 4, tick: 2))!)!;
      expect(_canonical(shrunk),
          _canonical(_snap(messages: 4, tick: 2).toSemanticTree()));
      // The removed-node ids actually appear in the shrink patch.
      final reEncoder = SemanticsWireEncoder()
        ..encode(_snap(messages: 6, tick: 2));
      final shrinkPatch = reEncoder.encode(_snap(messages: 4, tick: 2))!;
      expect(_envelope(shrinkPatch)['removed'], containsAll(['msg:4', 'msg:5']));
    });

    test('redaction survives the diff — no plaintext crosses the wire', () {
      final encoder = SemanticsWireEncoder();
      final decoder = SemanticsWireDecoder();
      // The secret value is redacted; a visible label changes per frame so a
      // real patch is produced (and must still carry no plaintext).
      SemanticInspectionSnapshot secretSnap(String token, String label) =>
          SemanticTree(
            root: SemanticNode(
              id: const SemanticNodeId('root'),
              role: SemanticRole.app,
              children: [
                SemanticNode(
                  id: const SemanticNodeId('field'),
                  role: SemanticRole.textField,
                  label: label,
                  value: token,
                  state: const SemanticState({'redactedValue': true}),
                ),
              ],
            ),
          ).toInspectionSnapshot();

      final full = encoder.encode(secretSnap('secret-aaa', 'API key 1'))!;
      expect(utf8.decode(full), isNot(contains('secret-aaa')));
      final patch = encoder.encode(secretSnap('secret-bbb', 'API key 2'))!;
      expect(_envelope(patch)['mode'], 'patch');
      expect(utf8.decode(patch), isNot(contains('secret-bbb')));
      final tree = decoder.apply(full)!;
      expect(tree.root.children.single.value, '<redacted>');
      final rebuilt = decoder.apply(patch)!;
      expect(rebuilt.root.children.single.value, '<redacted>');
      expect(rebuilt.root.children.single.label, 'API key 2');
    });

    test('a patch before any full frame is ignored (resync safety)', () {
      final encoder = SemanticsWireEncoder()..encode(_snap(messages: 3, tick: 0));
      final patch = encoder.encode(_snap(messages: 3, tick: 1))!;
      // A fresh decoder that missed the full frame must not act on the patch.
      expect(SemanticsWireDecoder().apply(patch), isNull);
    });

    test('malformed payloads are rejected, not thrown', () {
      final decoder = SemanticsWireDecoder();
      expect(decoder.apply(utf8.encode('not json')), isNull);
      expect(decoder.apply(utf8.encode('{"v":1}')), isNull);
      expect(decoder.apply(utf8.encode('{"v":999,"mode":"full"}')), isNull,
          reason: 'unknown wire version is rejected');
    });
  });
}
