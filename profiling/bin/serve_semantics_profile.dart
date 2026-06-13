// Profiles the SEMANTICS half of the serve wire — the traffic the visual
// profiler (serve_wire_profile.dart) ignores. The serve host ships a full,
// redacted SemanticInspectionSnapshot on every frame whose semantic tree
// changed (gated on the dirty tracker). With NO semantic diffing on the wire,
// a single changed label reserializes and reships the whole tree. This asks:
// how bad is that, deflated, for realistic tree sizes — and how much would a
// changed-subtree diff actually save? Both measured under whole-stream deflate
// (permessage-deflate with context takeover, the realistic socket).
//
// Run: dart run bin/serve_semantics_profile.dart

import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_semantics.dart';

/// Builds a realistic agent-style semantic tree: a status line, a message
/// list of [messages] items, and an input field. [tick] perturbs only a small
/// part (the status counter + the last message body) — the common
/// live-updating case where everything else is identical frame-to-frame.
SemanticTree _appTree({required int messages, required int tick}) {
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
                    // Only the last message grows as tokens stream in.
                    ? 'assistant: thinking about step $tick of the plan'
                    : 'turn $m: a settled message line of moderate length',
                state: SemanticState({'index': m, 'author': m.isEven ? 'user' : 'assistant'}),
              ),
          ],
        ),
        SemanticNode(
          id: const SemanticNodeId('input'),
          role: SemanticRole.textField,
          label: 'Message',
          value: '',
          actions: const {SemanticAction.submit},
        ),
      ],
    ),
  );
}

List<int> _snapshotBytes(SemanticTree tree) =>
    utf8.encode(jsonEncode(tree.toInspectionSnapshot().toJson()));

void main() {
  final z = ZLibCodec(raw: true, level: 6);
  const frames = 100;

  print('Semantics wire, full-resend vs the SemanticsWireEncoder diff.');
  print('z = whole-stream deflate (context takeover). 100 frames, one small');
  print('change per frame (status counter + last message body).');
  print('');
  print('${'tree'.padRight(16)}  nodes  full z/frame  diff z/frame  speedup');
  print('-' * 62);

  for (final messages in [8, 24, 80, 120, 160, 200, 240]) {
    final fullStream = <int>[];
    final diffStream = <int>[];
    final encoder = SemanticsWireEncoder();
    final nodeCount = _appTree(messages: messages, tick: 0)
        .toInspectionSnapshot()
        .nodeCount;
    for (var i = 0; i < frames; i++) {
      final tree = _appTree(messages: messages, tick: i);
      fullStream.addAll(_snapshotBytes(tree));
      final encoded = encoder.encode(tree.toInspectionSnapshot());
      if (encoded != null) diffStream.addAll(encoded);
    }
    final fullZ = z.encode(fullStream).length / frames;
    final diffZ = z.encode(diffStream).length / frames;
    print('${'list of $messages'.padRight(16)}  '
        '${nodeCount.toString().padLeft(5)}  '
        '${fullZ.round().toString().padLeft(11)}  '
        '${diffZ.round().toString().padLeft(11)}  '
        '${(fullZ / diffZ).toStringAsFixed(1).padLeft(6)}x');
  }

  print('');
  print('full = the old full-snapshot-on-change path (deflated /frame).');
  print('diff = SemanticsWireEncoder: full once, then patches (deflated /frame).');
  print('The diff is flat in tree size; full goes off the 32 KiB-window cliff.');
}
