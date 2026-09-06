import 'dart:convert';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_wire.dart';
import 'package:test/test.dart';

void main() {
  for (final live in [false, true]) {
    test('UTF-8 wire parity and exact payload limits (live: $live)', () {
      SemanticTree tree(String suffix) => SemanticTree(
        root: SemanticNode(
          id: const SemanticNodeId('status'),
          role: SemanticRole.status,
          label: 'café 漢字 👩‍💻 "quoted" \\ ${'x' * 512} $suffix',
          hint: 'line\nwith\ttabs',
          value: 'private value',
          state: const SemanticState({'redactedValue': true, 'progress': 1.25}),
        ),
      );
      Map<String, Object?> scalar(SemanticTree tree) => tree
          .toInspectionSnapshot()
          .root
          .toScalarJson(includeBounds: true, includeActionTargetToken: true);
      List<int> referenceFull(SemanticTree tree) => utf8.encode(
        jsonEncode({
          'v': semanticsWireVersion,
          'mode': 'full',
          'root': 'status',
          'nodes': [scalar(tree)],
        }),
      );
      List<int>? encode(SemanticsWireEncoder encoder, SemanticTree tree) => live
          ? encoder.encodeTree(tree)
          : encoder.encode(tree.toInspectionSnapshot());

      final first = tree('A');
      final next = tree('B');
      final full = referenceFull(first);
      final encoder = SemanticsWireEncoder(maxWirePayloadLength: full.length);
      final decoder = SemanticsWireDecoder(maxWirePayloadLength: full.length);
      final actualFull = encode(encoder, first)!;
      expect(actualFull, orderedEquals(full));
      expect(utf8.decode(actualFull), isNot(contains('private value')));
      expect(decoder.apply(actualFull)!.root.label, first.root.label);

      final patch = encode(encoder, next)!;
      expect(
        patch,
        orderedEquals(
          utf8.encode(
            jsonEncode({
              'v': semanticsWireVersion,
              'mode': 'patch',
              'root': 'status',
              'set': [scalar(next)],
            }),
          ),
        ),
      );
      expect(decoder.apply(patch)!.root.label, next.root.label);
      expect(encode(encoder, next), isNull);
      expect(
        encode(
          SemanticsWireEncoder(maxWirePayloadLength: full.length - 1),
          first,
        ),
        isNull,
      );
    });
  }
}
