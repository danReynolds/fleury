// The host-neutral composition root.
//
// Every Fleury host mounts the SAME widget scope stack around the app:
//
//   TuiBindingScope → MediaQuery → FocusManagerScope → PointerRouterScope
//     → ClipboardScope → (LogBufferScope?) → (DebugShell?) → Overlay[…]
//
// It used to be hand-written twice — once in `runApp` (native terminal) and
// once in `runTuiSurface` (browser embed) — and the two drifted: the browser
// copy silently lacked the log buffer and the debug shell because nothing
// forced it to account for them. Defining the stack ONCE here makes host
// parity structural: an optional layer is a named parameter, so a host that
// doesn't have that service passes an explicit `null` (a visible decision),
// and adding a new shared layer is a compile-time obligation on every host
// rather than a comment to keep in sync.

import '../debug/debug_shell.dart';
import '../debug/debug_state.dart';
import '../foundation/geometry.dart';
import '../rendering/surface_capabilities.dart';
import '../widgets/clipboard_scope.dart';
import '../widgets/focus.dart';
import '../widgets/framework.dart';
import '../widgets/media_query.dart';
import '../widgets/output_capture_view.dart';
import '../widgets/overlay.dart';
import '../widgets/pointer.dart';
import '../widgets/tui_binding.dart';
import 'clipboard.dart';
import 'output_capture.dart';

/// Assembles the shared scope stack a Fleury host mounts around [overlayEntries]
/// (the app's Navigator route entry, plus any host-owned floating entries like
/// the runtime-error overlay — created once by the caller so their subtree
/// state survives a resize rebuild).
///
/// [logBuffer] and [debugController] are optional layers: supply them to get
/// the captured-output scope and the debug shell (the native terminal host
/// does); pass null to omit them (the browser embed has neither yet). The
/// omission is explicit at the call site, which is the whole point — a host
/// can't silently lack a layer the other host has.
Widget buildTuiRoot({
  required TuiBinding binding,
  required CellSize size,
  required SurfaceCapabilities capabilities,
  required FocusManager focusManager,
  required PointerRouter pointerRouter,
  required Clipboard clipboard,
  required GlobalKey<OverlayState> overlayKey,
  required List<OverlayEntry> overlayEntries,
  // Required-but-nullable on purpose: a host must state whether it has these
  // layers (`null` to omit), so it can't silently lack one the other host has.
  required LogBuffer? logBuffer,
  required DebugController? debugController,
}) {
  // The Overlay is the innermost shared layer; the app's Navigator and any
  // floating host entries live inside it. Entry repaint boundaries stay on
  // (the default): every floating widget — toast, menu, palette — inserts
  // into THIS overlay via Overlay.of, so it is exactly where sibling-churn
  // pruning pays. Engagement is adaptive (see Overlay.addRepaintBoundaries):
  // frames where only one entry is visible pay no cache-write/blit tax.
  Widget tree = Overlay(key: overlayKey, initialEntries: overlayEntries);
  // DebugShell wraps the Overlay so docking the panel shares cells with the
  // app (off-mode is a pure pass-through, no layout cost).
  if (debugController != null) {
    tree = DebugShell(controller: debugController, child: tree);
  }
  // The captured-output buffer sits above the shell so both the app and the
  // floating console can read it.
  if (logBuffer != null) {
    tree = LogBufferScope(buffer: logBuffer, child: tree);
  }
  // Host services (clipboard) and the ambient frameworks (media, focus,
  // pointer) wrap everything, so the app and the debug console alike can
  // reach them.
  return TuiBindingScope(
    binding: binding,
    child: MediaQuery(
      data: MediaQueryData(size: size, capabilities: capabilities),
      child: FocusManagerScope(
        manager: focusManager,
        child: PointerRouterScope(
          router: pointerRouter,
          child: ClipboardScope(clipboard: clipboard, child: tree),
        ),
      ),
    ),
  );
}
