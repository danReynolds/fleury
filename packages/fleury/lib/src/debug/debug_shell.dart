// DebugShell — the top-level wrapper installed by runApp. Composes
// the user app with the debug panel according to controller.mode:
//
//   off        → child verbatim (short-circuit; zero overhead)
//   docked     → Row(or Column) with the app reflowed into the
//                remaining cells and DebugPanel pinned to one edge
//   fullscreen → Stack with the app still mounted underneath and
//                the panel covering it (state preserved, only
//                visibility flipped)
//
// Hotkey dispatch is NOT done here. The shell's hotkeys (Ctrl+G, F11,
// Esc-in-fullscreen, F12, paint-flash 'p') are framework escape
// hatches — they must fire even when a modal route (e.g. Navigator's
// active screen) is suppressing globals. runApp's event handler
// consumes them BEFORE the InputDispatcher walks the focus chain, in
// the same tier as the Ctrl+C exit-guard. Putting them in a tree-level
// KeyBindings would correctly land inside the modal scope filter and
// stop firing the moment the user opened a route — bad.

import '../foundation/geometry.dart';
import '../rendering/render_flex.dart' show CrossAxisAlignment;
import '../terminal/events.dart';
import '../widgets/basic.dart';
import '../widgets/framework.dart';
import '../widgets/layout_builder.dart';
import '../widgets/listenable_builder.dart';
import '../widgets/media_query.dart';
import 'debug_panel.dart';
import 'debug_state.dart';

/// Wraps [child] in the debug shell. Pass the runApp-resolved
/// controller; if `controller.config.enabled == false`, this is a
/// no-op shell that just returns [child].
class DebugShell extends StatefulWidget {
  const DebugShell({super.key, required this.controller, required this.child});

  final DebugController controller;
  final Widget child;

  @override
  State<DebugShell> createState() => _DebugShellState();
}

class _DebugShellState extends State<DebugShell> {
  @override
  Widget build(BuildContext context) {
    if (!widget.controller.config.enabled) return widget.child;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _layout(context),
    );
  }

  Widget _layout(BuildContext context) {
    final mode = widget.controller.mode;
    if (mode == DebugMode.off) {
      // Pure pass-through — no extra widgets, no MediaQuery override,
      // no DebugPanel mounted. The whole debug system has zero
      // structural cost in this branch.
      return widget.child;
    }

    if (mode == DebugMode.fullscreen) {
      // Stack: app stays mounted at full size (state + tickers
      // preserved), panel paints on top covering everything.
      return Stack(
        children: [
          widget.child,
          DebugPanel(controller: widget.controller),
        ],
      );
    }

    // Docked. Use LayoutBuilder so we size off real incoming
    // constraints rather than the ambient MediaQuery — the shell isn't
    // always the root (tests, embedded uses), and the two can differ.
    final config = widget.controller.config;
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalCols = constraints.maxCols ?? config.panelWidth + 1;
        final totalRows = constraints.maxRows ?? config.panelHeight + 1;
        final media = MediaQuery.maybeOf(context);

        if (config.side == DebugPanelSide.right) {
          final panelW = config.panelWidth.clamp(1, totalCols - 1);
          final appW = (totalCols - panelW).clamp(1, totalCols);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: appW,
                height: totalRows,
                child: _withMedia(
                  media,
                  CellSize(appW, totalRows),
                  widget.child,
                ),
              ),
              SizedBox(
                width: panelW,
                height: totalRows,
                child: DebugPanel(controller: widget.controller),
              ),
            ],
          );
        }
        final panelH = config.panelHeight.clamp(1, totalRows - 1);
        final appH = (totalRows - panelH).clamp(1, totalRows);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: totalCols,
              height: appH,
              child: _withMedia(media, CellSize(totalCols, appH), widget.child),
            ),
            SizedBox(
              width: totalCols,
              height: panelH,
              child: DebugPanel(controller: widget.controller),
            ),
          ],
        );
      },
    );
  }

  Widget _withMedia(MediaQueryData? media, CellSize size, Widget child) {
    if (media == null) return child;
    return MediaQuery(
      data: media.copyWith(size: size),
      child: child,
    );
  }
}

/// Tries to consume [event] as a debug-shell hotkey, returning true
/// when it did. Called by runApp's event loop BEFORE the dispatcher,
/// in the same escape-hatch tier as the Ctrl+C exit guard — so debug
/// hotkeys fire even inside a modal route's `suppressGlobals: true`
/// scope.
///
/// Bindings:
///   Ctrl+G              toggle off ↔ last-used open mode
///   F11                 docked ↔ fullscreen (only while open)
///   Esc                 fullscreen → docked (only when fullscreen)
///   F12                 show/hide Logs tab (open if off, close if
///                       already on Logs, switch tab otherwise)
///   p                   toggle paint-flash (only when shell is open)
///   ↑/↓/Home            move semantic cursor while Tree tab is active
bool tryConsumeDebugKey(DebugController controller, KeyEvent event) {
  if (!controller.config.enabled) return false;

  if (event.char == 'g' && event.hasCtrl) {
    controller.toggleOnOff();
    return true;
  }
  if (event.keyCode == KeyCode.f11) {
    if (controller.mode != DebugMode.off) {
      controller.toggleExpand();
      return true;
    }
    return false;
  }
  if (event.keyCode == KeyCode.escape) {
    if (controller.mode == DebugMode.fullscreen) {
      controller.collapseFromFullscreen();
      return true;
    }
    return false;
  }
  if (event.keyCode == KeyCode.f12) {
    if (controller.mode == DebugMode.off) {
      controller.selectTab(DebugTab.logs);
      controller.toggleOnOff();
    } else if (controller.tab == DebugTab.logs) {
      controller.toggleOnOff();
    } else {
      controller.selectTab(DebugTab.logs);
    }
    return true;
  }
  if (event.char == 'p' && !event.hasCtrl && !event.hasAlt) {
    if (controller.mode != DebugMode.off) {
      controller.togglePaintFlash();
      return true;
    }
    return false;
  }
  if (controller.mode != DebugMode.off && controller.tab == DebugTab.tree) {
    if (event.keyCode == KeyCode.arrowDown) {
      controller.moveSemanticCursor(1);
      return true;
    }
    if (event.keyCode == KeyCode.arrowUp) {
      controller.moveSemanticCursor(-1);
      return true;
    }
    if (event.keyCode == KeyCode.home) {
      controller.resetSemanticCursor();
      return true;
    }
  }
  return false;
}
