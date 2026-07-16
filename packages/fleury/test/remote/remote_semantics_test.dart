// The semantic wire diff must be indistinguishable from full-resend on the
// client: replaying FULL + PATCH frames reproduces, frame for frame, the exact
// tree a full snapshot would have — while shipping a fraction of the bytes.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:math';

import 'package:fleury/fleury.dart';
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
          expect(
            _envelope(bytes)['mode'],
            'patch',
            reason: 'steady frames are patches, not full resends',
          );
        }
        final rebuilt = decoder.apply(bytes)!;
        // The client's reconstructed tree equals a full-resend of this frame.
        expect(
          _canonical(rebuilt),
          _canonical(snapshot.toSemanticTree()),
          reason: 'frame $tick diverged',
        );
      }
    });

    test('a steady patch is a tiny fraction of the full frame', () {
      final encoder = SemanticsWireEncoder();
      final full = encoder.encode(_snap(messages: 240, tick: 0))!;
      final patch = encoder.encode(_snap(messages: 240, tick: 1))!;
      expect(_envelope(patch)['mode'], 'patch');
      // The full frame carries 244 nodes; the patch carries the 2 that moved.
      expect(
        patch.length * 20,
        lessThan(full.length),
        reason: 'patch ${patch.length}B vs full ${full.length}B',
      );
      final set = _envelope(patch)['set'] as List;
      expect(set, hasLength(2), reason: 'only status + last message changed');
    });

    test('an unchanged frame encodes to nothing', () {
      final encoder = SemanticsWireEncoder();
      expect(encoder.encode(_snap(messages: 10, tick: 7)), isNotNull);
      expect(
        encoder.encode(_snap(messages: 10, tick: 7)),
        isNull,
        reason: 'no exposed semantics changed → zero bytes',
      );
    });

    test('structural add and remove round-trip through patches', () {
      final encoder = SemanticsWireEncoder();
      final decoder = SemanticsWireDecoder();

      decoder.apply(encoder.encode(_snap(messages: 5, tick: 0))!);
      // Grow the list by one message.
      final grown = decoder.apply(
        encoder.encode(_snap(messages: 6, tick: 1))!,
      )!;
      expect(
        _canonical(grown),
        _canonical(_snap(messages: 6, tick: 1).toSemanticTree()),
      );
      // Shrink it by two.
      final shrunk = decoder.apply(
        encoder.encode(_snap(messages: 4, tick: 2))!,
      )!;
      expect(
        _canonical(shrunk),
        _canonical(_snap(messages: 4, tick: 2).toSemanticTree()),
      );
      // The removed-node ids actually appear in the shrink patch.
      final reEncoder = SemanticsWireEncoder()
        ..encode(_snap(messages: 6, tick: 2));
      final shrinkPatch = reEncoder.encode(_snap(messages: 4, tick: 2))!;
      expect(
        _envelope(shrinkPatch)['removed'],
        containsAll(['msg:4', 'msg:5']),
      );
    });

    test(
      'apply() surfaces the per-frame delta (changedIds / removedIds / full)',
      () {
        final encoder = SemanticsWireEncoder();
        final decoder = SemanticsWireDecoder();

        // FULL frame: every id counts as changed, nothing removed, full flag set.
        decoder.apply(encoder.encode(_snap(messages: 5, tick: 0))!);
        expect(decoder.wasFull, isTrue);
        expect(decoder.changedIds, isNotEmpty);
        expect(decoder.removedIds, isEmpty);

        // PATCH growing the list by one: the new message id is among changedIds.
        decoder.apply(encoder.encode(_snap(messages: 6, tick: 1))!);
        expect(decoder.wasFull, isFalse);
        expect(decoder.changedIds, contains('msg:5'));
        expect(decoder.removedIds, isEmpty);

        // PATCH shrinking by two: those ids appear in removedIds, not changedIds.
        decoder.apply(encoder.encode(_snap(messages: 4, tick: 2))!);
        expect(decoder.wasFull, isFalse);
        expect(decoder.removedIds, containsAll(<String>['msg:4', 'msg:5']));
        expect(decoder.changedIds, isNot(contains('msg:4')));
      },
    );

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
      final encoder = SemanticsWireEncoder()
        ..encode(_snap(messages: 3, tick: 0));
      final patch = encoder.encode(_snap(messages: 3, tick: 1))!;
      // A fresh decoder that missed the full frame must not act on the patch.
      expect(SemanticsWireDecoder().apply(patch), isNull);
    });

    test('malformed payloads are rejected, not thrown', () {
      final decoder = SemanticsWireDecoder();
      expect(decoder.apply(utf8.encode('not json')), isNull);
      expect(decoder.apply(utf8.encode('{"v":1}')), isNull);
      expect(
        decoder.apply(utf8.encode('{"v":999,"mode":"full"}')),
        isNull,
        reason: 'unknown wire version is rejected',
      );
    });

    test('rejected full and patch frames preserve the last-good base', () {
      final encoder = SemanticsWireEncoder();
      final decoder = SemanticsWireDecoder();
      final full = encoder.encode(_snap(messages: 3, tick: 0))!;
      final initial = decoder.apply(full)!;
      final initialJson = _canonical(initial);
      final initialChanged = List<String>.of(decoder.changedIds);

      List<int> wire(Map<String, Object?> envelope) =>
          utf8.encode(jsonEncode(envelope));

      // A malformed FULL must not clear a decoder that already has a good base.
      expect(
        decoder.apply(
          wire(<String, Object?>{
            'v': semanticsWireVersion,
            'mode': 'full',
            'root': 'root',
            'nodes': <Object?>[
              <String, Object?>{'id': 'root'}, // missing required role
            ],
          }),
        ),
        isNull,
      );
      expect(decoder.isPrimed, isTrue);
      expect(decoder.wasFull, isTrue);
      expect(decoder.changedIds, initialChanged);

      // Likewise, a malformed PATCH may stage a replacement but cannot poison
      // the retained map when inspection parsing rejects that candidate.
      expect(
        decoder.apply(
          wire(<String, Object?>{
            'v': semanticsWireVersion,
            'mode': 'patch',
            'root': 'root',
            'set': <Object?>[
              <String, Object?>{'id': 'status'}, // missing required role
            ],
          }),
        ),
        isNull,
      );
      expect(decoder.wasFull, isTrue);
      expect(decoder.changedIds, initialChanged);

      // The sender still believes the original FULL is the base. Its next real
      // PATCH therefore succeeds only if both rejected candidates were atomic.
      final validPatch = encoder.encode(_snap(messages: 3, tick: 1))!;
      final recovered = decoder.apply(validPatch);
      expect(recovered, isNotNull);
      expect(_canonical(recovered!), isNot(initialJson));
      expect(recovered.root.children.first.label, 'streaming — 1 tokens');
    });

    test('flat nodes cannot inject a nested children tree', () {
      List<int> wire({required bool unresolvedChildIds}) => utf8.encode(
        jsonEncode(<String, Object?>{
          'v': semanticsWireVersion,
          'mode': 'full',
          'root': 'root',
          'nodes': <Object?>[
            <String, Object?>{
              'id': 'root',
              'role': 'app',
              if (unresolvedChildIds) 'childIds': <String>['missing'],
              // `children` is not part of the flat wire. If it reaches the
              // inspection parser it bypasses every childIds graph bound.
              'children': <Object?>[
                <String, Object?>{
                  'id': 'injected',
                  'role': 'button',
                  'label': 'must stay hidden',
                },
              ],
            },
          ],
        }),
      );

      for (final unresolved in <bool>[false, true]) {
        final tree = SemanticsWireDecoder().apply(
          wire(unresolvedChildIds: unresolved),
        );
        expect(tree, isNotNull);
        expect(tree!.root.children, isEmpty);
        expect(tree.nodeById(const SemanticNodeId('injected')), isNull);
      }
    });

    test('retained FULL-equivalent bytes are bounded across patches', () {
      const limit = 700;
      List<int> wire(Map<String, Object?> envelope) =>
          utf8.encode(jsonEncode(envelope));
      Map<String, Object?> node(String id, {String? label}) =>
          <String, Object?>{'id': id, 'role': 'text', 'label': ?label};
      final largeALabel = ''.padRight(400, 'a');
      final largeBLabel = ''.padRight(400, 'b');

      final decoder = SemanticsWireDecoder(maxWirePayloadLength: limit);
      final full = wire(<String, Object?>{
        'v': semanticsWireVersion,
        'mode': 'full',
        'root': 'root',
        'nodes': <Object?>[
          <String, Object?>{
            'id': 'root',
            'role': 'app',
            'childIds': <String>['a', 'b'],
          },
          node('a'),
          node('b'),
        ],
      });
      expect(decoder.apply(full), isNotNull);

      final largeA = wire(<String, Object?>{
        'v': semanticsWireVersion,
        'mode': 'patch',
        'root': 'root',
        'set': <Object?>[node('a', label: largeALabel)],
      });
      expect(largeA.length, lessThan(limit));
      final afterA = decoder.apply(largeA);
      expect(afterA, isNotNull);
      expect(afterA!.nodeById(const SemanticNodeId('a'))!.label, largeALabel);

      // This frame is individually below the cap, but retaining both large
      // siblings would make the equivalent reconnect FULL exceed it.
      final largeB = wire(<String, Object?>{
        'v': semanticsWireVersion,
        'mode': 'patch',
        'root': 'root',
        'set': <Object?>[node('b', label: largeBLabel)],
      });
      expect(largeB.length, lessThan(limit));
      expect(decoder.apply(largeB), isNull);

      // Rejection was transactional: a small B patch still lands on the state
      // after A, rather than a hidden retained 400-byte B poisoning the base.
      final smallB = wire(<String, Object?>{
        'v': semanticsWireVersion,
        'mode': 'patch',
        'root': 'root',
        'set': <Object?>[node('b', label: 'ok')],
      });
      final recovered = decoder.apply(smallB);
      expect(recovered, isNotNull);
      expect(
        recovered!.nodeById(const SemanticNodeId('a'))!.label,
        largeALabel,
      );
      expect(recovered.nodeById(const SemanticNodeId('b'))!.label, 'ok');
    });

    test('encoder rejects an unrepresentable retained state then resyncs', () {
      const limit = 700;
      SemanticInspectionSnapshot snapshot(String a, String b) => SemanticTree(
        root: SemanticNode(
          id: const SemanticNodeId('root'),
          role: SemanticRole.app,
          children: <SemanticNode>[
            SemanticNode(
              id: const SemanticNodeId('a'),
              role: SemanticRole.text,
              label: a,
            ),
            SemanticNode(
              id: const SemanticNodeId('b'),
              role: SemanticRole.text,
              label: b,
            ),
          ],
        ),
      ).toInspectionSnapshot();

      final encoder = SemanticsWireEncoder(maxWirePayloadLength: limit);
      final largeA = ''.padRight(400, 'a');
      final largeB = ''.padRight(400, 'b');
      expect(_envelope(encoder.encode(snapshot('a', 'b'))!)['mode'], 'full');
      expect(
        _envelope(encoder.encode(snapshot(largeA, 'b'))!)['mode'],
        'patch',
      );
      expect(encoder.encode(snapshot(largeA, largeB)), isNull);

      final recovered = encoder.encode(snapshot('small-a', 'small-b'));
      expect(recovered, isNotNull);
      expect(_envelope(recovered!)['mode'], 'full');
      expect(SemanticsWireDecoder().apply(recovered), isNotNull);
    });

    test('semantic ids use the action wire UTF-8 bound', () {
      final oversizedId = List<String>.filled(
        maxRemoteSemanticNodeIdBytes ~/ 2 + 1,
        'é',
      ).join();
      final oversizedTree = SemanticTree(
        root: SemanticNode(
          id: SemanticNodeId(oversizedId),
          role: SemanticRole.app,
        ),
      ).toInspectionSnapshot();
      final encoder = SemanticsWireEncoder();
      expect(encoder.encode(oversizedTree), isNull);
      expect(
        _envelope(encoder.encode(_snap(messages: 1, tick: 0))!)['mode'],
        'full',
      );

      List<int> fullWith(Map<String, Object?> root) => utf8.encode(
        jsonEncode(<String, Object?>{
          'v': semanticsWireVersion,
          'mode': 'full',
          'root': root['id'],
          'nodes': <Object?>[root],
        }),
      );
      expect(
        SemanticsWireDecoder().apply(
          fullWith(<String, Object?>{'id': oversizedId, 'role': 'app'}),
        ),
        isNull,
      );
      expect(
        SemanticsWireDecoder().apply(
          fullWith(<String, Object?>{
            'id': 'root',
            'role': 'app',
            'childIds': <String>[oversizedId],
          }),
        ),
        isNull,
      );

      final loneSurrogate = utf8.encode(
        r'{"v":1,"mode":"full","root":"\uD800","nodes":[]}',
      );
      expect(
        () => SemanticsWireDecoder().apply(loneSurrogate),
        returnsNormally,
      );
      expect(SemanticsWireDecoder().apply(loneSurrogate), isNull);
    });

    test('a compact DAG or cycle is rejected instead of expanded', () {
      List<int> dag({required bool cycle}) {
        const depth = 14;
        final nodes = <Map<String, Object?>>[
          for (var i = 0; i < depth; i++)
            <String, Object?>{
              'id': 'n$i',
              'role': 'app',
              if (i < depth - 1)
                'childIds': <String>['n${i + 1}', 'n${i + 1}']
              else if (cycle)
                'childIds': <String>['n0'],
            },
        ];
        return utf8.encode(
          jsonEncode(<String, Object?>{
            'v': semanticsWireVersion,
            'mode': 'full',
            'root': 'n0',
            'nodes': nodes,
          }),
        );
      }

      final dagDecoder = SemanticsWireDecoder();
      expect(dagDecoder.apply(dag(cycle: false)), isNull);
      expect(dagDecoder.isPrimed, isFalse);

      final cycleDecoder = SemanticsWireDecoder();
      expect(cycleDecoder.apply(dag(cycle: true)), isNull);
      expect(cycleDecoder.isPrimed, isFalse);
    });

    test('duplicate leaf ids remain visible for ambiguity diagnostics', () {
      final bytes = utf8.encode(
        jsonEncode(<String, Object?>{
          'v': semanticsWireVersion,
          'mode': 'full',
          'root': 'root',
          'nodes': <Object?>[
            <String, Object?>{
              'id': 'root',
              'role': 'app',
              'childIds': <String>['dup', 'dup'],
            },
            <String, Object?>{
              'id': 'dup',
              'role': 'button',
              'label': 'duplicate',
            },
          ],
        }),
      );
      final tree = SemanticsWireDecoder().apply(bytes);
      expect(tree, isNotNull);
      expect(tree!.root.children, hasLength(2));
      expect(
        tree.root.children.map((child) => child.id.value),
        everyElement('dup'),
      );
    });

    test('node and edge bounds reject oversized semantic graphs', () {
      List<int> wire(List<Map<String, Object?>> nodes) => utf8.encode(
        jsonEncode(<String, Object?>{
          'v': semanticsWireVersion,
          'mode': 'full',
          'root': 'root',
          'nodes': nodes,
        }),
      );

      final tooManyNodes = <Map<String, Object?>>[
        <String, Object?>{'id': 'root', 'role': 'app'},
        for (var i = 1; i <= maxSemanticWireNodes; i++)
          <String, Object?>{'id': 'orphan-$i', 'role': 'text'},
      ];
      expect(SemanticsWireDecoder().apply(wire(tooManyNodes)), isNull);

      final tooManyEdges = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'root',
          'role': 'app',
          'childIds': List<String>.filled(maxSemanticWireEdges + 1, 'missing'),
        },
      ];
      expect(SemanticsWireDecoder().apply(wire(tooManyEdges)), isNull);

      final tooManyRepeatedLeaves = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'root',
          'role': 'app',
          'childIds': List<String>.filled(maxSemanticWireNodes + 1, 'leaf'),
        },
        <String, Object?>{'id': 'leaf', 'role': 'text'},
      ];
      expect(SemanticsWireDecoder().apply(wire(tooManyRepeatedLeaves)), isNull);
    });

    test('unreachable patch nodes are pruned and cannot later resurrect', () {
      List<int> wire(Map<String, Object?> envelope) =>
          utf8.encode(jsonEncode(envelope));
      final decoder = SemanticsWireDecoder();
      final full = wire(<String, Object?>{
        'v': semanticsWireVersion,
        'mode': 'full',
        'root': 'root',
        'nodes': <Object?>[
          <String, Object?>{'id': 'root', 'role': 'app'},
        ],
      });
      expect(decoder.apply(full), isNotNull);

      final orphanPatch = wire(<String, Object?>{
        'v': semanticsWireVersion,
        'mode': 'patch',
        'root': 'root',
        'set': <Object?>[
          <String, Object?>{
            'id': 'orphan',
            'role': 'button',
            'label': 'must not persist',
          },
        ],
      });
      final afterOrphan = decoder.apply(orphanPatch)!;
      expect(afterOrphan.root.children, isEmpty);
      expect(decoder.changedIds, isEmpty);

      // Reference the old id without re-sending its node. A retained orphan
      // would now become visible; a pruned one remains a missing child.
      final linkPatch = wire(<String, Object?>{
        'v': semanticsWireVersion,
        'mode': 'patch',
        'root': 'root',
        'set': <Object?>[
          <String, Object?>{
            'id': 'root',
            'role': 'app',
            'childIds': <String>['orphan'],
          },
        ],
      });
      final afterLink = decoder.apply(linkPatch)!;
      expect(afterLink.root.children, isEmpty);
    });

    test(
      'a childIds chain deeper than the cap is pruned, not a stack overflow',
      () {
        // A hostile/corrupt full frame: a linear chain far deeper than any real
        // UI. Reconstruction must terminate (pruned at maxSemanticTreeDepth)
        // rather than recursing to a crash.
        const depth = maxSemanticTreeDepth + 200;
        final nodes = <Map<String, Object?>>[
          for (var i = 0; i < depth; i++)
            <String, Object?>{
              'id': 'n$i',
              'role': 'app',
              'enabled': true,
              if (i < depth - 1) 'childIds': <String>['n${i + 1}'],
            },
        ];
        final bytes = utf8.encode(
          jsonEncode(<String, Object?>{
            'v': semanticsWireVersion,
            'mode': 'full',
            'root': 'n0',
            'nodes': nodes,
          }),
        );
        final tree = SemanticsWireDecoder().apply(bytes);
        expect(tree, isNotNull, reason: 'pruned tree, not a crash');
        // The reconstructed chain is bounded by the depth cap.
        var node = tree!.root;
        var measured = 1;
        while (node.children.isNotEmpty) {
          node = node.children.single;
          measured++;
        }
        expect(measured, lessThanOrEqualTo(maxSemanticTreeDepth));
      },
    );

    test('fuzzing random envelopes never throws (returns tree-or-null)', () {
      final rng = Random(0x5E3A);
      const ids = ['root', 'a', 'b', 'c', 'self', 'missing'];
      Object? randomValue(int budget) {
        switch (rng.nextInt(budget <= 0 ? 4 : 6)) {
          case 0:
            return rng.nextBool();
          case 1:
            return rng.nextInt(1000);
          case 2:
            return ['x', '<redacted>', '', 'lbl ${rng.nextInt(9)}'][rng.nextInt(
              4,
            )];
          case 3:
            return null;
          case 4:
            return [
              for (var i = 0; i < rng.nextInt(4); i++) randomValue(budget - 1),
            ];
          default:
            return {
              for (var i = 0; i < rng.nextInt(4); i++)
                'k$i': randomValue(budget - 1),
            };
        }
      }

      Map<String, Object?> randomNode() => <String, Object?>{
        if (rng.nextInt(10) != 0) 'id': ids[rng.nextInt(ids.length)],
        if (rng.nextBool()) 'role': rng.nextBool() ? 'button' : 'qux',
        if (rng.nextBool()) 'label': randomValue(2),
        if (rng.nextBool()) 'state': randomValue(2),
        if (rng.nextBool())
          'childIds': [
            for (var i = 0; i < rng.nextInt(5); i++)
              ids[rng.nextInt(ids.length)],
          ],
        if (rng.nextInt(8) == 0) 'actions': ['activate', rng.nextBool()],
      };

      final decoder = SemanticsWireDecoder();
      for (var iter = 0; iter < 1000; iter++) {
        final envelope = <String, Object?>{
          'v': rng.nextInt(12) == 0 ? rng.nextInt(3) : semanticsWireVersion,
          'mode': ['full', 'patch', 'bogus'][rng.nextInt(3)],
          if (rng.nextBool()) 'root': ids[rng.nextInt(ids.length)],
          if (rng.nextBool())
            'nodes': [for (var i = 0; i < rng.nextInt(6); i++) randomNode()],
          if (rng.nextBool())
            'set': [for (var i = 0; i < rng.nextInt(6); i++) randomNode()],
          if (rng.nextBool())
            'removed': [
              for (var i = 0; i < rng.nextInt(4); i++)
                ids[rng.nextInt(ids.length)],
            ],
        };
        // Must never throw — a tree or null, whatever the random shape.
        expect(
          () => decoder.apply(utf8.encode(jsonEncode(envelope))),
          returnsNormally,
        );
      }
    });

    test('truncated / byte-corrupted frames degrade safely and never wedge the '
        'decoder', () {
      final decoder = SemanticsWireDecoder();
      // Prime with a valid full frame, then corrupt copies of a real frame.
      expect(
        decoder.apply(
          SemanticsWireEncoder().encode(_snap(messages: 5, tick: 0))!,
        ),
        isNotNull,
      );
      final valid = SemanticsWireEncoder().encode(_snap(messages: 6, tick: 1))!;

      // Every prefix length: a frame truncated mid-stream must not throw.
      for (var len = 0; len <= valid.length; len += (valid.length ~/ 41) + 1) {
        expect(
          () => decoder.apply(valid.sublist(0, len)),
          returnsNormally,
          reason: 'truncated to $len bytes',
        );
      }
      // Deterministic single-bit flips across the frame.
      final rng = Random(0xB17F1);
      for (var i = 0; i < 200; i++) {
        final bytes = List<int>.of(valid)
          ..[rng.nextInt(valid.length)] ^= 1 << rng.nextInt(8);
        expect(() => decoder.apply(bytes), returnsNormally);
      }

      // Not wedged: a fresh full frame still decodes after all the garbage.
      expect(
        decoder.apply(
          SemanticsWireEncoder().encode(_snap(messages: 8, tick: 2))!,
        ),
        isNotNull,
      );
    });
  });
}
