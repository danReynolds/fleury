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
  print('');
  _cpu();
}

/// Server-side CPU per changed frame: build the redacted snapshot, then encode
/// the wire diff. The encoder re-serializes every node each frame to detect
/// what changed (O(tree) work for an O(changed) wire), so this is where the
/// "is the diff cheap to compute?" assumption gets tested.
void _cpu() {
  print('Server CPU per changed frame (steady-state patch), µs:');
  print('${'tree'.padRight(16)}  nodes  snapshot µs  encode µs  total µs');
  print('-' * 56);
  for (final messages in [24, 80, 240]) {
    final nodeCount =
        _appTree(messages: messages, tick: 0).toInspectionSnapshot().nodeCount;
    final encoder = SemanticsWireEncoder()
      ..encode(_appTree(messages: messages, tick: 0).toInspectionSnapshot());

    const iters = 2000;
    // Warm up the JIT.
    for (var i = 0; i < 200; i++) {
      final s = _appTree(messages: messages, tick: i).toInspectionSnapshot();
      encoder.encode(s);
    }

    var snapNs = 0;
    var encNs = 0;
    final sw = Stopwatch();
    for (var i = 0; i < iters; i++) {
      final tree = _appTree(messages: messages, tick: 1000 + i);
      sw
        ..reset()
        ..start();
      final snapshot = tree.toInspectionSnapshot();
      sw.stop();
      snapNs += sw.elapsedMicroseconds;
      sw
        ..reset()
        ..start();
      encoder.encode(snapshot);
      sw.stop();
      encNs += sw.elapsedMicroseconds;
    }
    final snapUs = snapNs / iters;
    final encUs = encNs / iters;
    print('${'list of $messages'.padRight(16)}  '
        '${nodeCount.toString().padLeft(5)}  '
        '${snapUs.toStringAsFixed(1).padLeft(11)}  '
        '${encUs.toStringAsFixed(1).padLeft(9)}  '
        '${(snapUs + encUs).toStringAsFixed(1).padLeft(8)}');
  }
  print('');
  print('At 60 fps one frame is 16667 µs; semantics is a tiny slice even at');
  print('the top size. snapshot = redaction walk; encode = flatten+diff.');
}
