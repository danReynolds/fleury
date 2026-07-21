// WhichKey: a Spacemacs / vim-which-key style popup that appears while the
// user is partway through a multi-step key sequence, listing the keys that
// continue it. It reads the dispatcher's live pending state via
// [KeyBindings.pendingOf] — no wiring beyond wrapping the app.

import 'dart:async';

import 'package:fleury/fleury_core.dart';

import 'panel.dart';

/// Wraps [child] and, once the user presses a leader key (`Space`, `Ctrl+X`)
/// and the dispatcher is holding for the next step, shows a popup listing the
/// available continuations — `f  Find file`, `b  Buffers`.
///
/// The popup appears only after [showDelay] of a sequence staying pending, so
/// a fast completion (a vim `dd` in ~80 ms) never flashes it. It reads
/// [KeyBindings.pendingOf], so it updates as the sequence advances and
/// vanishes the moment it completes, cancels, or times out.
///
/// Only completions whose binding carries a [KeyBinding.label] are listed
/// (the same discoverability rule as `KeyHintBar`); an unlabeled binding still
/// fires but isn't advertised. For a custom layout, read
/// [KeyBindings.pendingOf] directly instead of using this widget.
class WhichKey extends StatefulWidget {
  const WhichKey({
    super.key,
    required this.child,
    this.showDelay = const Duration(milliseconds: 150),
  });

  final Widget child;

  /// How long a sequence must stay pending before the popup appears. Keeps
  /// fast sequences from flashing it.
  final Duration showDelay;

  @override
  State<WhichKey> createState() => _WhichKeyState();
}

class _WhichKeyState extends State<WhichKey> {
  PendingKeySequenceMatch? _pending;
  bool _visible = false;
  Timer? _showTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-read whenever the pending notifier fires (start / advance / clear).
    final pending = KeyBindings.pendingOf(context);
    _pending = pending;
    if (pending == null) {
      // Sequence completed, cancelled, or timed out — hide immediately and
      // disarm any not-yet-fired reveal.
      _showTimer?.cancel();
      _showTimer = null;
      _visible = false;
    } else if (!_visible && _showTimer == null) {
      if (widget.showDelay <= Duration.zero) {
        // No delay — reveal on this same frame (build runs after this).
        _visible = true;
      } else {
        // A sequence is in flight; reveal only if it outlives the delay so a
        // fast completion never flashes the popup.
        _showTimer = Timer(widget.showDelay, () {
          if (!mounted) return;
          setState(() => _visible = true);
        });
      }
    }
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    if (!_visible || pending == null) return widget.child;

    final theme = Theme.of(context);
    final keyStyle = CellStyle(
      foreground: theme.colorScheme.primary,
      bold: true,
    );
    final rows = <Widget>[
      for (final completion in pending.completions)
        if (completion.binding.label != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${completion.next}  ', style: keyStyle),
              Text(completion.binding.displayLabel),
            ],
          ),
    ];
    if (rows.isEmpty) return widget.child;

    return Stack(
      children: [
        widget.child,
        Align(
          alignment: Alignment.bottomLeft,
          child: Panel(
            title: pending.prefix.hintLabel,
            expandChild: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: rows,
            ),
          ),
        ),
      ],
    );
  }
}
