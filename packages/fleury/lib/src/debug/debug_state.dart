// Debug panel state — mode (off / docked / fullscreen) + the
// in-panel toggles (paint-flashing, no-reflow, …). A small
// `ChangeNotifier` so the shell rebuilds on mode flips.

import '../foundation/change_notifier.dart';
import '../semantics/semantics.dart';
import '../terminal/diagnostics.dart';

/// Three-state lifecycle of the debug surface.
///   - off:        no panel mounted; user app uses full terminal;
///                 zero-overhead enforced by the shell short-circuit
///   - docked:     panel on the side; user app reflows into the
///                 remaining cells
///   - fullscreen: panel covers the terminal; user app still mounted
///                 + ticking behind it (state preserved, just hidden)
enum DebugMode { off, docked, fullscreen }

/// Which edge the docked panel hugs.
enum DebugPanelSide { right, bottom }

/// Which tab in the panel is selected. Only `live` ships in P0;
/// `tree`, `rebuilds`, `logs` are stubs that promote in P1.
enum DebugTab { live, tree, rebuilds, logs }

/// Top-level config the app declares once via `runApp(debug: ...)`.
class DebugConfig {
  const DebugConfig({
    this.enabled = true,
    this.startMode = DebugMode.off,
    this.side = DebugPanelSide.right,
    this.panelWidth = 32,
    this.panelHeight = 12,
  });

  /// When false, the shell becomes a no-op — `DebugShell` returns
  /// `child` verbatim and no events flow. Use for prod builds where
  /// you want the framework stripped of debug behaviour.
  final bool enabled;

  /// What state to open in. Default `off` keeps cold-start clean;
  /// set to `docked` (or pass `--debug` from your app's CLI) for
  /// dev launches.
  final DebugMode startMode;

  /// Default edge for docked mode. `right` matches IDE convention
  /// and preserves terminal height (usually the more constrained
  /// dimension on dev monitors).
  final DebugPanelSide side;

  /// Docked panel width when `side == right`. Cells.
  final int panelWidth;

  /// Docked panel height when `side == bottom`. Cells.
  final int panelHeight;
}

/// Mutable runtime state — flips between modes, switches tabs,
/// toggles in-panel options. The shell + panel listen and rebuild.
class DebugController extends ChangeNotifier {
  DebugController(this._config) : _mode = _config.startMode;

  final DebugConfig _config;
  DebugMode _mode;
  DebugMode _lastOpen = DebugMode.docked;
  DebugTab _tab = DebugTab.live;
  bool _paintFlash = false;
  int _semanticCursorIndex = 0;
  SemanticTree? Function()? _semanticTreeProvider;
  TerminalDiagnosis? Function()? _terminalDiagnosisProvider;
  bool _disposed = false;

  DebugConfig get config => _config;
  DebugMode get mode => _mode;
  DebugTab get tab => _tab;
  bool get paintFlash => _paintFlash;
  int get semanticCursorIndex => _semanticCursorIndex;

  /// Supplies the current semantic tree to the debug panel's Tree tab.
  ///
  /// The provider is nullable so tests and embedders can opt in without
  /// making debug state depend on a particular app root. It is evaluated only
  /// when the panel asks for a snapshot.
  void setSemanticTreeProvider(SemanticTree? Function()? provider) {
    _checkNotDisposed();
    _semanticTreeProvider = provider;
    notifyListeners();
  }

  SemanticTree? semanticSnapshot() => _semanticTreeProvider?.call();

  /// Supplies the current terminal profile/capability diagnosis to the
  /// inspector. Evaluated on demand so resize and driver capability changes
  /// are reflected without per-frame capture.
  void setTerminalDiagnosisProvider(TerminalDiagnosis? Function()? provider) {
    _checkNotDisposed();
    _terminalDiagnosisProvider = provider;
    notifyListeners();
  }

  TerminalDiagnosis? terminalDiagnosisSnapshot() =>
      _terminalDiagnosisProvider?.call();

  /// Ctrl+G — off ↔ last-opened mode. Means a user who docked then
  /// closed gets back to docked, not bounced to fullscreen.
  void toggleOnOff() {
    _checkNotDisposed();
    if (_mode == DebugMode.off) {
      _mode = _lastOpen;
    } else {
      _lastOpen = _mode;
      _mode = DebugMode.off;
    }
    notifyListeners();
  }

  /// Shift+Ctrl+G / F11 — docked ↔ fullscreen. No-op when off.
  void toggleExpand() {
    _checkNotDisposed();
    if (_mode == DebugMode.off) return;
    _mode = _mode == DebugMode.docked ? DebugMode.fullscreen : DebugMode.docked;
    _lastOpen = _mode;
    notifyListeners();
  }

  /// Esc when fullscreen → back to docked.
  void collapseFromFullscreen() {
    _checkNotDisposed();
    if (_mode != DebugMode.fullscreen) return;
    _mode = DebugMode.docked;
    _lastOpen = _mode;
    notifyListeners();
  }

  void selectTab(DebugTab tab) {
    _checkNotDisposed();
    if (_tab == tab) return;
    _tab = tab;
    notifyListeners();
  }

  void togglePaintFlash() {
    _checkNotDisposed();
    _paintFlash = !_paintFlash;
    notifyListeners();
  }

  void moveSemanticCursor(int delta) {
    _checkNotDisposed();
    final next = _semanticCursorIndex + delta;
    final clamped = next < 0 ? 0 : next;
    if (clamped == _semanticCursorIndex) return;
    _semanticCursorIndex = clamped;
    notifyListeners();
  }

  void resetSemanticCursor() {
    _checkNotDisposed();
    if (_semanticCursorIndex == 0) return;
    _semanticCursorIndex = 0;
    notifyListeners();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('DebugController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _semanticTreeProvider = null;
    _terminalDiagnosisProvider = null;
    super.dispose();
  }
}
