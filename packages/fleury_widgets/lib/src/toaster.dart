import 'dart:async';

import 'package:fleury/fleury.dart';

/// Semantic level of a toast, driving its default color. [info] is
/// neutral (uncolored); the rest tint the border and text.
enum ToastSeverity { info, success, warning, error }

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
    this.duration = const Duration(seconds: 3),
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
      action,
    );
  }

  @override
  State<Toaster> createState() => _ToasterState();
}

class _Toast {
  _Toast(this.message, this.style, this.action);
  final String message;
  final CellStyle style;
  final ToastAction? action;
  FrameTicker? timer; // scheduler-driven auto-dismiss clock
}

class _ToasterState extends State<Toaster> {
  final List<_Toast> _toasts = <_Toast>[];
  TuiBinding? _binding;
  OverlayEntry? _entry;

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
    ToastAction? action,
  ) {
    final toast = _Toast(message, style, action);
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
            Container(
              border: BoxBorder(
                style: BorderStyle.rounded,
                cellStyle: toast.style,
              ),
              child: _toastContent(toast),
            ),
        ],
      ),
    );
  }

  Widget _toastContent(_Toast toast) {
    final action = toast.action;
    if (action == null) return Text(toast.message, style: toast.style);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(toast.message, style: toast.style),
        Text(
          '  [${action.key.hintLabel}] ${action.label}',
          style: toast.style.merge(const CellStyle(bold: true)),
        ),
      ],
    );
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
    Widget child = widget.child;
    if (actionable.isNotEmpty) {
      child = KeyBindings(
        bindings: [
          for (final toast in actionable)
            KeyBinding(
              toast.action!.key,
              onEvent: (_) {
                final action = toast.action!;
                _dismiss(toast);
                action.onPressed();
              },
              hideFromHintBar: true,
            ),
        ],
        child: child,
      );
    }
    return _ToasterScope(state: this, child: child);
  }
}

class _ToasterScope extends InheritedWidget {
  const _ToasterScope({required this.state, required super.child});

  final _ToasterState state;

  @override
  bool updateShouldNotify(_ToasterScope old) => !identical(state, old.state);
}
