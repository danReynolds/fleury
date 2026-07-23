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
    this.maxCompletions = 12,
  });

  /// The app (or subtree) the popup overlays. It shows through unchanged
  /// until a key sequence is pending, then the popup floats above it.
  final Widget child;

  /// How long a sequence must stay pending before the popup appears. Keeps
  /// fast sequences from flashing it.
  final Duration showDelay;

  /// Cap on how many completions the popup lists before collapsing the rest
  /// into a trailing `+N more` — so a leader with many bindings can't render a
  /// popup taller than the screen (which would clip its own title).
  final int maxCompletions;

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
    // A clickable close glyph, ASCII-safe on limited terminals.
    final closeGlyph =
        MediaQuery.glyphTierOf(context) == GlyphTier.ascii ? 'x' : '✕';
    final labeled = [
      for (final completion in pending.completions)
        if (completion.binding.label != null) completion,
    ];
    if (labeled.isEmpty) return widget.child;

    // Bound the height: show the first [maxCompletions], collapse the rest
    // into a trailing "+N more" so the popup can't overrun the viewport.
    final shown = labeled.length > widget.maxCompletions
        ? labeled.take(widget.maxCompletions)
        : labeled;
    final hidden = labeled.length - shown.length;
    final rows = <Widget>[
      for (final completion in shown)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${completion.next}  ', style: keyStyle),
            Text(completion.binding.displayLabel),
          ],
        ),
      if (hidden > 0) Text('+$hidden more', style: const CellStyle(dim: true)),
    ];

    return Stack(
      children: [
        widget.child,
        // styled component, not selectable text (the app child stays selectable)
        SelectionArea.disabled(
          child: Align(
            alignment: Alignment.bottomLeft,
            // A floating popup composites over whatever's painted beneath it, so
            // it must paint its own opaque background or the app content bleeds
            // through the panel. Surface is the same fill the Navigator gives a
            // modal; this popup floats a bare Panel, so it supplies its own.
            child: Surface(
              child: Panel(
                title: pending.prefix.hintLabel,
                // Dismiss affordances: the keyboard hint (Esc, or any
                // non-continuing key) plus a clickable close for pointer users.
                // Both abandon the in-flight sequence, which drops the popup.
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('esc ', style: CellStyle(dim: true)),
                    GestureDetector(
                      onTap: () => KeyBindings.cancelPending(context),
                      child: Text(
                        closeGlyph,
                        style: CellStyle(foreground: theme.colorScheme.primary),
                      ),
                    ),
                  ],
                ),
                expandChild: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: rows,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
