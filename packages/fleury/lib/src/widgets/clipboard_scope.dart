// ClipboardScope: shares the host-installed Clipboard with descendants.
//
// The clipboard is a host service, not a global: runApp installs
// SystemClipboard (platform tools + OSC 52), the browser hosts install
// WebClipboard, and FleuryTester installs InProcessClipboard — each into
// its own runtime's tree, so two runtimes in one isolate never share a
// clipboard and a test override can't leak past its tester.

import '../runtime/clipboard.dart';
import 'framework.dart';

/// Shares the host-installed [Clipboard] with descendants — a
/// `Scope<Clipboard>`.
///
/// Installed above the app by every host (`runApp`, `mountApp`,
/// `FleuryTester`); widgets reach it with [of] from event handlers. Wrap a
/// subtree in another [ClipboardScope] to override it locally (nearest
/// wins) — e.g. to capture copies in one pane.
class ClipboardScope extends Scope<Clipboard> {
  const ClipboardScope({
    super.key,
    required Clipboard clipboard,
    required super.child,
  }) : super(value: clipboard);

  /// The nearest scope's clipboard. A non-dependent read: call sites are
  /// event handlers (copy chords, drag-end), not build methods, and the
  /// instance is stable for the session — no rebuild coupling wanted.
  static Clipboard of(BuildContext context) {
    final clipboard = maybeOf(context);
    if (clipboard == null) {
      throw StateError(
        'ClipboardScope.of: no ClipboardScope ancestor. Hosts (runApp, '
        'mountApp, FleuryTester) install one above the app; a bare '
        'BuildOwner harness must wrap the tree in ClipboardScope itself.',
      );
    }
    return clipboard;
  }

  /// Like [of], but null when no scope is installed.
  static Clipboard? maybeOf(BuildContext context) =>
      Scope.maybeOfWithoutDependency<Clipboard>(context);
}
