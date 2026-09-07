// Real runApp input -> dispatch -> scheduled frame -> semantic wire output.
// The in-memory peer removes socket/display noise. Completion is the first
// event-loop turn after onEvent: the runtime's frame/semantic microtasks have
// drained, including inputs that correctly produce no output. These are NOT
// physical input-to-display timings. TickerMode mutes animation tickers;
// TextInput's separate caret timer remains active and can add visual frames.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_wire.dart';
import 'package:fleury/src/remote/remote_driver.dart';
import 'package:fleury_samples/samples.dart';

final class _Peer
    with SynchronousSendTransport
    implements RemoteFrameTransport {
  final input = StreamController<RemoteFrame>.broadcast();
  final output = <RemoteFrame>[];
  @override
  Stream<RemoteFrame> get incoming => input.stream;
  @override
  void send(RemoteFrame frame) => output.add(frame);
  @override
  Future<void> close() async {
    if (!input.isClosed) await input.close();
  }
}

int _hash(String value, [int hash = 0x811c9dc5]) {
  for (final unit in value.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

// Preserve the full positional path; normalize ONLY the object identities
// chosen by the runtime's overlay/route roots. The dashboard also shows a
// wall-clock string. Neither is expected to match between fresh processes.
final _sessionKey = RegExp(r'(OverlayEntry|UniqueKey)#[0-9a-z]+');
final _wallClock = RegExp(r'\b\d{2}:\d{2}:\d{2}\b');
Object? _normalize(Object? value, Map<String, String> keys, bool clock) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key: _normalize(entry.value, keys, clock),
    };
  }
  if (value is List)
    return value.map((v) => _normalize(v, keys, clock)).toList();
  if (value is String) {
    if (value.startsWith('auto:') || value.startsWith('key:')) {
      return value.replaceAllMapped(
          _sessionKey,
          (m) =>
              keys.putIfAbsent(m[0]!, () => '${m[1]}#session${keys.length}'));
    }
    if (clock) return value.replaceAll(_wallClock, '<clock>');
  }
  return value;
}

Future<void> main(List<String> args) async {
  final iterations = args.isEmpty ? 300 : int.parse(args.single);
  if (iterations <= 0 || iterations.isOdd) {
    throw ArgumentError('iterations must be positive and even');
  }
  stdout.writeln(
      jsonEncode({'dart': Platform.version, 'iterations': iterations}));
  for (final (name, app) in <(String, Widget)>[
    ('dashboard', const DashboardApp()),
    ('files', const FileManagerApp()),
    ('forms', const FormsShowcaseApp()),
  ]) {
    for (final mode in [
      'ignored-key',
      'pointer-idle',
      'tab',
      if (name == 'forms') 'typing',
      if (name == 'files') 'selection',
    ]) {
      final peer = _Peer();
      Completer<void>? completion;
      final watch = Stopwatch();
      final done = runApp(
        TickerMode(enabled: false, child: app),
        driver: RemoteTerminalDriver(peer),
        enableHotReload: false,
        requireInteractiveTerminal: false,
        debug: const DebugConfig(enabled: false),
        onEvent: (_) {
          Timer.run(() {
            watch.stop();
            completion?.complete();
            completion = null;
          });
          return null;
        },
      );
      scheduleMicrotask(() => peer.input.add(const InitFrame(
            size: CellSize(120, 40),
            colorMode: ColorMode.truecolor,
            imageProtocol: ImageProtocol.halfBlock,
            tmuxPassthrough: false,
          )));
      final decoder = SemanticsWireDecoder();
      SemanticTree? tree;
      void consume() {
        for (final frame in peer.output.whereType<SemanticsFrame>()) {
          tree = decoder.apply(frame.json);
          if (tree == null) throw StateError('Invalid semantic wire chain');
        }
      }

      try {
        // Mount/adaptive-layout settling is outside every measured window.
        await Future<void>.delayed(const Duration(milliseconds: 60));
        consume();
        if (tree == null) throw StateError('No initial semantic tree: $name');
        final sessionKeys = <String, String>{};
        final times = <int>[];
        var plans = 0, semanticFrames = 0, semanticBytes = 0;
        var fingerprint = 0x811c9dc5;
        var changedSnapshots = 0;
        String? previousSnapshot;
        for (var i = -30; i < iterations; i++) {
          final TuiEvent event = switch (mode) {
            'ignored-key' => const KeyEvent(KeyCode.f12),
            'pointer-idle' => const MouseEvent(
                kind: MouseEventKind.moved,
                button: MouseButton.none,
                col: 119,
                row: 39,
              ),
            'tab' => KeyEvent(KeyCode.tab,
                modifiers: i.isOdd ? const {KeyModifier.shift} : const {}),
            'typing' => i.isEven
                ? const InputBatch(key: KeyEvent(KeyCode.a), committedText: 'a')
                : const KeyEvent(KeyCode.backspace),
            'selection' =>
              KeyEvent(i.isEven ? KeyCode.arrowDown : KeyCode.arrowUp),
            _ => throw StateError(mode),
          };
          peer.output.clear();
          final ready = completion = Completer<void>();
          watch
            ..reset()
            ..start();
          peer.input.add(InputEventFrame(event));
          await ready.future.timeout(const Duration(seconds: 3));
          final elapsed = watch.elapsedMicroseconds;
          consume();
          final snapshot = jsonEncode(_normalize(
              tree!.toInspectionSnapshot().toJson(),
              sessionKeys,
              name == 'dashboard'));
          if (mode == 'typing' &&
              tree!.byLabel('Service name').single.value !=
                  (i.isEven ? 'a' : '')) {
            throw StateError('Typing did not reach the service-name field');
          }
          if (i >= 0 &&
              (mode == 'typing' ||
                  mode == 'selection' ||
                  (name == 'forms' && mode == 'tab')) &&
              snapshot == previousSnapshot) {
            throw StateError('Expected a changed snapshot for $name/$mode');
          }
          if (i >= 0) {
            times.add(elapsed);
            plans += peer.output.whereType<PlanFrame>().length;
            final semantics = peer.output.whereType<SemanticsFrame>();
            semanticFrames += semantics.length;
            semanticBytes +=
                semantics.fold(0, (n, frame) => n + frame.json.length);
            fingerprint = _hash(snapshot, fingerprint);
            if (snapshot != previousSnapshot) changedSnapshots++;
          }
          previousSnapshot = snapshot;
        }
        times.sort();
        stdout.writeln(jsonEncode({
          'app': name,
          'mode': mode,
          'iterations': iterations,
          'medianUs': times[times.length ~/ 2],
          'p95Us': times[(times.length * .95).ceil() - 1],
          'p99Us': times[(times.length * .99).ceil() - 1],
          'plans': plans,
          'semanticFrames': semanticFrames,
          'semanticBytes': semanticBytes,
          'nodes': tree!.nodeCount,
          'changedSnapshots': changedSnapshots,
          'fingerprint': fingerprint,
        }));
      } finally {
        await peer.close();
        await done.timeout(const Duration(seconds: 5));
      }
    }
  }
}
