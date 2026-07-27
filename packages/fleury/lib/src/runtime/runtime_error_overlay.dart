import 'dart:async';

import '../foundation/change_notifier.dart';
import '../rendering/border.dart';
import '../rendering/cell.dart';
import '../rendering/edge_insets.dart';
import '../rendering/render_objects.dart' show TextOverflow;
import '../widgets/align.dart';
import '../widgets/basic.dart';
import '../widgets/framework.dart';
import '../widgets/listenable_builder.dart';
import '../widgets/pointer.dart';

/// One captured uncaught runtime error.
class RuntimeErrorRecord {
  RuntimeErrorRecord(this.error, this.stackTrace, this.when);
  final Object error;
  final StackTrace stackTrace;
  final DateTime when;
}

/// Collects uncaught runtime errors — a throwing event handler, a failed async
/// callback, a scheduled-frame error — and drives the on-screen
/// [RuntimeErrorOverlay].
///
/// This mirrors Flutter's default posture: report the error and keep running,
/// rather than tearing the whole app down. The runtime feeds reports in from
/// its zone guard and its event-dispatch try/catch. [isStorming] lets the
/// runtime fall back to a hard stop when errors recur every frame (an
/// unrecoverable loop) instead of spinning forever.
class RuntimeErrorReporter with ChangeNotifier {
  RuntimeErrorReporter({
    this.onLog,
    this.autoDismiss = const Duration(seconds: 8),
  });

  /// Textual sink for each report (e.g. stderr / the debug console), so the
  /// error is logged as well as shown.
  final void Function(String message)? onLog;

  /// How long the banner stays up before fading on its own. Zero keeps it until
  /// dismissed.
  final Duration autoDismiss;

  final List<DateTime> _window = <DateTime>[];
  final List<RuntimeErrorRecord> _history = <RuntimeErrorRecord>[];
  static const _historyCap = 50;
  RuntimeErrorRecord? _current;
  int _shownCount = 0;
  Timer? _dismissTimer;
  bool _disposed = false;

  /// The error currently surfaced, or null when nothing is showing.
  RuntimeErrorRecord? get current => _current;

  /// How many errors have stacked up behind the current banner.
  int get shownCount => _shownCount;

  /// The most recent errors, oldest first, bounded to the last
  /// [_historyCap]. Powers the debug shell's Errors tab; unlike [current]
  /// it survives banner dismissal.
  List<RuntimeErrorRecord> get history =>
      List<RuntimeErrorRecord>.unmodifiable(_history);

  /// True when errors arrive faster than the app can recover — the runtime
  /// treats this as fatal rather than looping forever.
  bool get isStorming => _window.length >= 24;

  /// True once [dispose] has run: [report] is a silent no-op from here on, so
  /// the zone handler must fall back to stderr for anything arriving now.
  bool get isDisposed => _disposed;

  void report(Object error, StackTrace stackTrace) {
    // The zone's uncaught-error handler can call report() AFTER teardown has
    // disposed this reporter. Without this guard it would arm a fresh,
    // uncancellable auto-dismiss Timer (dispose only cancelled the prior one),
    // keeping the isolate alive past app end, and mutate a disposed notifier.
    if (_disposed) return;
    final now = DateTime.now();
    onLog?.call('Uncaught runtime error: $error\n$stackTrace');
    _window.add(now);
    _window.removeWhere((t) => now.difference(t) > const Duration(seconds: 3));
    _shownCount = _current == null ? 1 : _shownCount + 1;
    _current = RuntimeErrorRecord(error, stackTrace, now);
    _history.add(_current!);
    if (_history.length > _historyCap) _history.removeAt(0);
    _dismissTimer?.cancel();
    if (autoDismiss > Duration.zero) {
      _dismissTimer = Timer(autoDismiss, dismiss);
    }
    notifyListeners();
  }

  void dismiss() {
    if (_disposed) return;
    _dismissTimer?.cancel();
    if (_current == null) return;
    _current = null;
    _shownCount = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _dismissTimer?.cancel();
    super.dispose();
  }
}

/// A full-screen overlay *layer* that shows a dismissible error banner whenever
/// [reporter] has a current error, and nothing otherwise. Mounted as its own
/// [OverlayEntry] above the app so it never touches the app's layout — the app
/// keeps running and rendering full-screen underneath.
class RuntimeErrorOverlay extends StatelessWidget {
  const RuntimeErrorOverlay({super.key, required this.reporter});

  final RuntimeErrorReporter reporter;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: reporter,
      builder: (context, _) {
        final record = reporter.current;
        if (record == null) return const SizedBox();
        return Align(
          alignment: Alignment.bottomCenter,
          child: _ErrorBanner(
            record: record,
            count: reporter.shownCount,
            onDismiss: reporter.dismiss,
          ),
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.record,
    required this.count,
    required this.onDismiss,
  });

  final RuntimeErrorRecord record;
  final int count;
  final void Function() onDismiss;

  // Hardcoded error styling (ANSI red): this overlay lives above the user's
  // Theme, so it can't read theme colors — like the build-error [ErrorWidget],
  // it draws a stark red panel of its own.
  static const _red = CellStyle(foreground: AnsiColor(1), bold: true);

  @override
  Widget build(BuildContext context) {
    final firstLine = record.error.toString().split('\n').first;
    final prefix = count > 1 ? '⚠ $count errors · ' : '⚠ ';
    return GestureDetector(
      onTap: onDismiss,
      // The banner floats over the app, so it paints its own opaque
      // background — otherwise the content underneath bleeds through the
      // frame and the error is hard to read. Sitting above the user's Theme,
      // Surface resolves against [ThemeData.fallback], which is deterministic.
      child: Surface(
        child: Container(
          border: const BoxBorder(style: BorderStyle.rounded, cellStyle: _red),
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Text(
            '$prefix$firstLine · click to dismiss',
            style: _red,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
