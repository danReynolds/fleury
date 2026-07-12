// Shared plumbing for the profiling gates and probes (paint_gate,
// alloc_gate, paint_walk_probe): the null sink, numeric flag parsing,
// baseline JSON IO, the probe/gate row fixtures, and the ambient-scope
// mount used to run real widgets outside a test runner.
//
// Not a package library on purpose: profiling keeps its harness code flat
// (see analyze.dart / capture_pty.dart at the package root), and the gates
// import this relatively.

import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';

/// Discards output — keeps a measurement to the renderer's own work and
/// nothing else (the runtime's real sink writes to dart:io).
final class NullAnsiSink implements AnsiSink {
  const NullAnsiSink();
  @override
  void write(String data) {}
  @override
  Future<void> flush() async {}
}

/// Parses the integer value of a `--<name>=<int>` flag.
///
/// Returns null when [arg] is not this flag (so callers chain flags with
/// `??`). A malformed value (`--frames=abc`, `--frames=`) is a usage error:
/// prints the problem and exits 64 — never an uncaught FormatException.
/// Call during argument parsing only, before any resource is open.
int? parseIntFlag(String arg, String name) {
  final prefix = '--$name=';
  if (!arg.startsWith(prefix)) return null;
  final raw = arg.substring(prefix.length);
  final value = int.tryParse(raw);
  if (value == null) {
    stderr.writeln("invalid --$name: expected an integer, got '$raw'");
    exit(64);
  }
  return value;
}

/// Reads a gate baseline JSON map. When the file is missing, prints the
/// standard "run with --update-baseline first" hint (prefixed with
/// [gateName]) and returns null — the caller sets exitCode 64 and returns,
/// keeping its own cleanup path.
Map<String, Object?>? readBaselineOrNull(
  String path, {
  required String gateName,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln(
      '$gateName: no baseline at $path — run with --update-baseline first.',
    );
    return null;
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

/// Writes [data] as the canonical baseline format: two-space-indented JSON
/// plus a trailing newline.
void writeBaselineJson(String path, Map<String, Object?> data) {
  final json = const JsonEncoder.withIndent('  ').convert(data);
  File(path).writeAsStringSync('$json\n');
}

// ---------------------------------------------------------------------------
// Row fixtures — shared by the paint-walk probe and the paint gate so both
// provably measure the same row shape.
// ---------------------------------------------------------------------------

/// A per-row reactive model: [bump] notifies this row's listeners only —
/// the localized-update primitive of the probe and the gate.
class RowModel extends ChangeNotifier {
  int v = 0;
  void bump() {
    v++;
    notifyListeners();
  }
}

/// Full-width styled row: color + ~[cols] graphemes, padded to a FIXED
/// width so paint bounds — and the paint gate's copiedCellCount — cannot
/// wobble as the tick grows. This is the probe's "skipping the repaint is a
/// real saving" row.
Widget styledRow({required int index, required int tick, required int cols}) {
  final label = 'row $index  tick=$tick  ';
  return Text(
    label.padRight(cols, '·'),
    style: CellStyle(
      foreground: RgbColor(120 + (index % 8) * 12, 200, 160),
      bold: index.isEven,
    ),
  );
}

/// [styledRow] listening to its OWN [model] — the streaming-token /
/// live-row update shape whose localized repaint the boundaries prune.
Widget liveRow({required int index, required RowModel model, required int cols}) {
  return ListenableBuilder(
    listenable: model,
    builder: (context, _) => styledRow(index: index, tick: model.v, cols: cols),
  );
}

// ---------------------------------------------------------------------------
// Ambient mount
// ---------------------------------------------------------------------------

/// Wraps [scene] in the ambient scopes the widget tests install — binding,
/// media query (explicit [SurfaceCapabilities], the tester's defaults),
/// focus, pointer, and clipboard — so real widgets (ListView, Overlay,
/// Toaster) run under test-equivalent chrome from a bare BuildOwner.
///
/// This mirrors `FleuryTester._wrap` pending a public mount helper in
/// fleury_test (named follow-up — do not reach into core packages from
/// here); if that wrap changes, change this with it.
Widget wrapWithAmbientScopes({
  required Widget scene,
  required TuiBinding binding,
  required FocusManager focusManager,
  required PointerRouter pointerRouter,
  required CellSize size,
  Clipboard? clipboard,
}) {
  return TuiBindingScope(
    binding: binding,
    child: MediaQuery(
      data: MediaQueryData(
        size: size,
        capabilities: const SurfaceCapabilities(
          colorMode: ColorMode.truecolor,
          glyphTier: GlyphTier.unicode,
          images: InlineImageSupport.none,
        ),
      ),
      child: FocusManagerScope(
        manager: focusManager,
        child: PointerRouterScope(
          router: pointerRouter,
          child: ClipboardScope(
            clipboard: clipboard ?? InProcessClipboard(),
            child: scene,
          ),
        ),
      ),
    ),
  );
}
