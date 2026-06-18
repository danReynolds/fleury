import 'dart:async';

import 'package:fleury/fleury.dart';

/// Semantic level of a toast, driving the color of its status dot. [info] is
/// neutral (uncolored); the rest color the dot.
enum ToastSeverity { info, success, warning, error }

/// A toast's leading status dot: one uniform, reliably monospace-width glyph for
/// every severity. (Distinct per-severity shapes — ✓ ✗ ▲ — render at
/// inconsistent widths in proportional browser fonts, which threw the text out
/// of alignment.) Severity is carried by the dot's *color* via
/// [_styleForSeverity], not its shape — keeping color use sparse: a neutral
/// frame and message with one colored accent.
const String _severityDot = '●';

CellStyle _styleForSeverity(ToastSeverity severity, ColorScheme colors) =>
    switch (severity) {
      ToastSeverity.info => CellStyle.empty, // neutral by design
      ToastSeverity.success => CellStyle(foreground: colors.success),
      ToastSeverity.warning => CellStyle(foreground: colors.warning),
      ToastSeverity.error => CellStyle(foreground: colors.error),
    };

/// An actionable affordance on a toast — a [label] and the [key] chord
/// that triggers [onPressed] (and dismisses the toast) while it's
/// visible. The chord fires from anywhere in the app, so prefer a
/// modifier chord (e.g. `KeyChord.alt('u')`); a bare letter is swallowed
/// by a focused text field.
class ToastAction {
  const ToastAction({
    required this.label,
    required this.onPressed,
    required this.key,
  });

  final String label;
  final void Function() onPressed;
  final KeyChord key;
}

/// Hosts transient toast notifications. Place one high in the app
/// (wrapping your content); it floats toasts in a screen corner above
/// everything — including modals — via an Overlay entry, stacking them
/// and auto-dismissing each after a delay.
///
/// Fire one imperatively from anywhere below it:
///
/// ```dart
/// Toaster.show(context, 'Saved', severity: ToastSeverity.success);
/// ```
class Toaster extends StatefulWidget {
  const Toaster({
    super.key,
    required this.child,
    this.alignment = Alignment.bottomRight,
    this.duration = const Duration(seconds: 5),
  });

  final Widget child;

  /// Which corner toasts stack in.
  final Alignment alignment;

  /// How long each toast stays before auto-dismissing.
  final Duration duration;

  /// Shows [message] as a toast via the nearest enclosing [Toaster].
  /// Throws if there is no Toaster above [context].
  ///
  /// [severity] picks a default color; [style] overrides it outright when
  /// supplied (merged over the severity's style). An optional [action]
  /// adds a hotkey affordance shown in the toast.
  static void show(
    BuildContext context,
    String message, {
    Duration? duration,
    ToastSeverity severity = ToastSeverity.info,
    CellStyle? style,
    ToastAction? action,
  }) {
    final scope = context.getInheritedWidgetOfExactType<_ToasterScope>();
    if (scope == null) {
      throw StateError(
        'No Toaster above this BuildContext. Wrap your app in a Toaster.',
      );
    }
    final colors = Theme.of(context).colorScheme;
    final resolved = style == null
        ? _styleForSeverity(severity, colors)
        : _styleForSeverity(severity, colors).merge(style);
    scope.state._enqueue(
      message,
      duration ?? scope.state.widget.duration,
      resolved,
      severity,
      action,
    );
  }

  @override
  State<Toaster> createState() => _ToasterState();
}

class _Toast {
  _Toast({
    required this.id,
    required this.message,
    required this.severity,
    required this.style,
    required this.duration,
    required this.action,
  });

  final int id;
  final String message;
  final ToastSeverity severity;
  final CellStyle style;
  final Duration duration;
  final ToastAction? action;
  FrameTicker? timer; // scheduler-driven auto-dismiss clock
}

class _ToasterState extends State<Toaster> {
  final List<_Toast> _toasts = <_Toast>[];
  TuiBinding? _binding;
  OverlayEntry? _entry;
  var _nextToastId = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _binding ??= TuiBinding.maybeOf(context);
    if (_entry == null) {
      final overlay = Overlay.maybeOf(context);
      if (overlay != null) {
        _entry = OverlayEntry(builder: (_) => _buildLayer());
        overlay.insert(_entry!);
      }
    }
  }

  void _enqueue(
    String message,
    Duration duration,
    CellStyle style,
    ToastSeverity severity,
    ToastAction? action,
  ) {
    final toast = _Toast(
      id: ++_nextToastId,
      message: message,
      severity: severity,
      style: style,
      duration: duration,
      action: action,
    );
    _toasts.add(toast);
    _refresh();
    final binding = _binding;
    if (binding == null) return;
    // A one-shot timer on the shared scheduler (so it's FakeClock-driven
    // in tests): the first tick at +duration dismisses the toast.
    toast.timer =
        FrameTicker(interval: duration, scheduler: binding.tickerScheduler)
          ..addListener(() => _dismiss(toast))
          ..start();
  }

  void _dismiss(_Toast toast) {
    if (!_toasts.remove(toast)) return;
    // The tick is firing right now (this runs from the ticker's listener);
    // defer disposal so we don't tear the ticker down mid-notify.
    final ticker = toast.timer;
    toast.timer = null;
    scheduleMicrotask(() => ticker?.dispose());
    _refresh();
  }

  /// Rebuilds both the floating layer (an Overlay entry) and this widget's
  /// own subtree, where the action hotkeys live as `KeyBindings`.
  void _refresh() {
    _entry?.markNeedsBuild();
    if (mounted) setState(() {});
  }

  Widget _buildLayer() {
    return Align(
      alignment: widget.alignment,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final toast in _toasts)
            Semantics(
              id: SemanticNodeId('toast-${toast.id}'),
              role: SemanticRole.notification,
              label: toast.message,
              hint: toast.action == null
                  ? 'Transient notification'
                  : '${toast.action!.label} (${toast.action!.key.hintLabel})',
              actions: <SemanticAction>{
                SemanticAction.dismiss,
                if (toast.action != null) SemanticAction.activate,
              },
              state: _toastSemanticState(toast),
              includeChildren: false,
              onAction: (action) {
                switch (action) {
                  case SemanticAction.dismiss:
                    _dismiss(toast);
                  case SemanticAction.activate:
                    _activateAction(toast);
                  default:
                    break;
                }
              },
              child: Container(
                // A normal (neutral) frame — severity lives in the dot, not the
                // border — with horizontal padding so the content breathes.
                border: const BoxBorder(style: BorderStyle.rounded),
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: _toastContent(toast),
              ),
            ),
        ],
      ),
    );
  }

  SemanticState _toastSemanticState(_Toast toast) {
    return SemanticState(<String, Object?>{
      'severity': toast.severity.name,
      'notificationIndex': _toasts.indexOf(toast) + 1,
      'notificationCount': _toasts.length,
      'autoDismissMs': toast.duration.inMilliseconds,
      if (toast.action case final action?) ...<String, Object?>{
        'notificationActionLabel': action.label,
        'notificationActionKey': action.key.hintLabel,
      },
    });
  }

  Widget _toastContent(_Toast toast) {
    final action = toast.action;
    // Sparse color: only the status dot carries the severity color; the message
    // is neutral and the frame is plain. The action (if any) gets the one
    // interactive accent, so it's clearly the part you can act on.
    final dot = Text(_severityDot, style: toast.style);
    final message = Text(' ${toast.message}');
    if (action == null) {
      return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[dot, message]);
    }
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        dot,
        message,
        const Text('   '),
        Text(
          action.label,
          style: CellStyle(foreground: theme.colorScheme.primary, bold: true),
        ),
        Text(' [${action.key.hintLabel}]', style: theme.mutedStyle),
      ],
    );
  }

  void _activateAction(_Toast toast) {
    final action = toast.action;
    if (action == null) return;
    if (!_toasts.contains(toast)) return;
    _dismiss(toast);
    action.onPressed();
  }

  @override
  void dispose() {
    _entry?.remove();
    for (final toast in _toasts) {
      toast.timer?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Action hotkeys live here (not in the floating layer): the Toaster
    // wraps the whole app, so these KeyBindings are an ancestor of
    // whatever is focused and fire from anywhere. Newest-first so a newer
    // toast wins a chord shared with an older one.
    final actionable = [
      for (final toast in _toasts.reversed)
        if (toast.action != null) toast,
    ];
    final bindings = <KeyBinding>[
      for (final toast in actionable)
        KeyBinding(
          toast.action!.key,
          onEvent: (_) {
            _activateAction(toast);
          },
          hideFromHintBar: true,
        ),
      // Esc dismisses the most recent toast so plain (action-less) toasts are
      // keyboard-dismissible (WCAG 2.1.1). Bound at the app's outermost layer,
      // so a modal/menu that uses Esc consumes it first; it only fires here
      // when a toast is showing and nothing inner handled it.
      if (_toasts.isNotEmpty)
        KeyBinding(
          KeyChord.escape,
          onEvent: (event) {
            if (_toasts.isEmpty) {
              event.bubble();
              return;
            }
            _dismiss(_toasts.last);
          },
          hideFromHintBar: true,
        ),
    ];
    // Always wrap (even with no bindings) so the child's position in the tree
    // is stable: conditionally adding/removing this wrapper as toasts come and
    // go would re-parent the child and tear down e.g. an open menu's overlay.
    return _ToasterScope(
      state: this,
      child: KeyBindings(bindings: bindings, child: widget.child),
    );
  }
}

class _ToasterScope extends InheritedWidget {
  const _ToasterScope({required this.state, required super.child});

  final _ToasterState state;

  @override
  bool updateShouldNotify(_ToasterScope old) => !identical(state, old.state);
}
