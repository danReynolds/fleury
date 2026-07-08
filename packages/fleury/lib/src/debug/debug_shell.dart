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
import '../input/events.dart';
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
/// Key-code bindings. The printable shortcuts — `p`, `/`, `s`, and the typed
/// Logs-search query — arrive as text, not key codes, and are handled by the
/// companion [tryConsumeDebugText].
///   Ctrl+G              toggle off ↔ last-used open mode
///   F11                 docked ↔ fullscreen (only while open)
///   Tab / Shift+Tab     next / previous panel tab (only while open)
///   Esc                 clear a Logs search, else fullscreen → docked
///   F12                 show/hide Logs tab (open if off, close if
///                       already on Logs, switch tab otherwise)
///   Enter / Backspace   commit / edit the Logs search (while searching)
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
    // In the Logs tab, Esc first backs out of search — cancel an open field or
    // clear a committed query — before it collapses fullscreen.
    if (controller.mode != DebugMode.off &&
        controller.tab == DebugTab.logs &&
        (controller.logSearching || controller.logQuery.isNotEmpty)) {
      controller.cancelLogSearch();
      return true;
    }
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
  // Logs search field: Enter commits, Backspace edits. These are keyCode
  // events so they arrive here; the typed query characters are printable text,
  // handled by [tryConsumeDebugText].
  if (controller.mode != DebugMode.off &&
      controller.tab == DebugTab.logs &&
      controller.logSearching) {
    if (event.keyCode == KeyCode.enter) {
      controller.commitLogSearch();
      return true;
    }
    if (event.keyCode == KeyCode.backspace) {
      controller.backspaceLogQuery();
      return true;
    }
  }
  if (controller.mode != DebugMode.off &&
      event.keyCode == KeyCode.tab &&
      !event.hasCtrl &&
      !event.hasAlt) {
    // While the shell is open, Tab / Shift+Tab cycle the panel tabs.
    controller.nextTab(event.hasShift ? -1 : 1);
    return true;
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

/// Consumes a printable [TextInputEvent] as a debug-shell shortcut — the
/// companion to [tryConsumeDebugKey] for keys the terminal delivers as *text*
/// rather than key codes. Fleury's input parser emits `TextInputEvent` for
/// printable ASCII (a plain `p`, `/`, `s`, or a typed query character), so
/// these bindings can't live in the `KeyEvent`-only path. Returns true when the
/// shell handled it, so the caller skips the normal input dispatcher.
///
/// Bindings (only while the shell is open):
///   p           toggle paint-flash
///   / · s       Logs tab: open search · cycle source filter
///   `text`      while the Logs search field is open, append to the query — and
///               capture it so typed characters don't leak into the app beneath
bool tryConsumeDebugText(DebugController controller, TextInputEvent event) {
  if (!controller.config.enabled || controller.mode == DebugMode.off) {
    return false;
  }
  // While the search field is open, all typed text edits the query and is
  // captured (so it can't fall through to the app under the shell).
  if (controller.tab == DebugTab.logs && controller.logSearching) {
    controller.appendLogQuery(event.text);
    return true;
  }
  if (event.text == 'p') {
    controller.togglePaintFlash();
    return true;
  }
  if (controller.tab == DebugTab.logs) {
    if (event.text == '/') {
      controller.startLogSearch();
      return true;
    }
    if (event.text == 's') {
      controller.cycleLogSource();
      return true;
    }
  }
  return false;
}
