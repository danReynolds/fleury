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

void main(List<String> args) {
  if (args.contains('--gate')) {
    _gate();
    return;
  }

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

/// Regression gate for the semantics wire's headline invariant: the diff stays
/// FLAT in tree size, so a large served UI never falls off the 32 KiB DEFLATE
/// cliff. The `SemanticsWireEncoder` diff is the only thing standing between a
/// realistic agent/screen-reader tree and a ~57x per-frame wire blow-up
/// (measured at 244 nodes). A revert to full-resend, or a diff that stops being
/// O(changed), would silently reopen the cliff — this fails the check instead.
///
///   dart run bin/serve_semantics_profile.dart --gate
void _gate() {
  final z = ZLibCodec(raw: true, level: 6);
  const frames = 100;

  double diffZPerFrame(int messages) {
    final encoder = SemanticsWireEncoder();
    final stream = <int>[];
    for (var i = 0; i < frames; i++) {
      final e = encoder.encode(
        _appTree(messages: messages, tick: i).toInspectionSnapshot(),
      );
      if (e != null) stream.addAll(e);
    }
    return z.encode(stream).length / frames;
  }

  final small = diffZPerFrame(24); // ~12 B/frame today
  final large = diffZPerFrame(240); // ~38 B/frame today (must stay flat)
  final growth = small == 0 ? 0.0 : large / small;

  // Generous vs today's 38 B; a revert to full-resend hits ~2180 B at 240 nodes
  // (57x), and growth jumps from ~3x to ~64x — either trips this comfortably.
  const maxLargeBytes = 120.0;
  const maxGrowth = 6.0;
  final ok = large < maxLargeBytes && growth < maxGrowth;

  stdout.writeln('serve semantics gate: diff z/frame — 24-node ${small.round()} '
      'B, 240-node ${large.round()} B (growth ${growth.toStringAsFixed(1)}x)');
  if (ok) {
    stdout.writeln('serve semantics gate: pass — the wire diff is flat in tree '
        'size; the DEFLATE cliff is held off.');
  } else {
    stdout.writeln('serve semantics gate: FAIL — the semantics wire diff is no '
        'longer flat in tree size (regressed toward full-resend → the 32 KiB '
        'DEFLATE cliff). Want 240-node < ${maxLargeBytes.round()} B and growth < '
        '${maxGrowth.toStringAsFixed(0)}x.');
    exitCode = 1;
  }
}

/// Server-side CPU per changed frame: build the redacted snapshot, then encode
/// the wire diff. The encoder re-serializes every node each frame to detect
/// what changed (O(tree) work for an O(changed) wire), so this is where the
/// "is the diff cheap to compute?" assumption gets tested.
SemanticWireDelta _delta(SemanticsOwner owner, SemanticTree tree) {
  final update = owner.update(tree);
  return SemanticWireDelta(
    changed: {
      for (final id in update.added) id.value,
      for (final id in update.updated) id.value,
    },
    removed: {for (final id in update.removed) id.value},
  );
}

void _cpu() {
  print('Server CPU per changed frame (steady-state patch), µs:');
  print('${'tree'.padRight(16)}  nodes  full-encode µs  delta-encode µs  win');
  print('-' * 60);
  for (final messages in [24, 80, 240]) {
    final nodeCount =
        _appTree(messages: messages, tick: 0).toInspectionSnapshot().nodeCount;

    // Full path: encode with no delta (re-flatten + full compare every frame).
    // Delta path: a parallel owner yields the changed-set the encoder trusts.
    final fullEnc = SemanticsWireEncoder()
      ..encode(_appTree(messages: messages, tick: 0).toInspectionSnapshot());
    final deltaEnc = SemanticsWireEncoder()
      ..encode(_appTree(messages: messages, tick: 0).toInspectionSnapshot());
    final owner = SemanticsOwner()..update(_appTree(messages: messages, tick: 0));

    const iters = 2000;
    for (var i = 0; i < 200; i++) {
      final tree = _appTree(messages: messages, tick: i);
      final s = tree.toInspectionSnapshot();
      fullEnc.encode(s);
      deltaEnc.encode(s, delta: _delta(owner, tree));
    }

    var fullNs = 0;
    var deltaNs = 0;
    final sw = Stopwatch();
    for (var i = 0; i < iters; i++) {
      final tree = _appTree(messages: messages, tick: 1000 + i);
      final snapshot = tree.toInspectionSnapshot();
      final delta = _delta(owner, tree);
      sw
        ..reset()
        ..start();
      fullEnc.encode(snapshot);
      sw.stop();
      fullNs += sw.elapsedMicroseconds;
      sw
        ..reset()
        ..start();
      deltaEnc.encode(snapshot, delta: delta);
      sw.stop();
      deltaNs += sw.elapsedMicroseconds;
    }
    final fullUs = fullNs / iters;
    final deltaUs = deltaNs / iters;
    print('${'list of $messages'.padRight(16)}  '
        '${nodeCount.toString().padLeft(5)}  '
        '${fullUs.toStringAsFixed(1).padLeft(14)}  '
        '${deltaUs.toStringAsFixed(1).padLeft(15)}  '
        '${(fullUs / deltaUs).toStringAsFixed(1).padLeft(4)}x');
  }
  print('');
  print('full-encode = re-flatten whole tree + structural compare (O(tree)).');
  print('delta-encode = re-serialize only the owner\'s changed nodes '
      '(O(changed)).');
}
