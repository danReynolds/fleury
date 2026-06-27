// KeyHintBar: a one-line widget that auto-discovers the currently
// active key bindings by walking the focus chain and renders them as
// "hint description · hint description" along the available width.

import '../rendering/cell.dart';
import 'basic.dart';
import 'focus.dart';
import 'framework.dart';
import 'key_bindings.dart';

/// Walks the active focus chain and renders each visible binding as
/// "[label]". Updates automatically when focus moves (because it
/// depends on the [FocusManager] via [Focus.of]).
///
/// Filtering rules:
///   1. Bindings with `label == null` are hidden (the chord's
///      auto-label alone isn't enough — a binding needs a written
///      label to qualify for the bar).
///   2. Bindings with `hideFromHintBar: true` are hidden.
///   3. Bindings with `enabled: false` are hidden.
///   4. Duplicate chords keep the nearest (deeper) binding.
///   5. Global bindings (passed via [globalBindings]) appear last.
class KeyHintBar extends StatelessWidget {
  const KeyHintBar({
    super.key,
    this.maxBindings = 12,
    this.separator = ' · ',
    this.style = CellStyle.empty,
    this.globalBindings = const [],
  });

  /// Maximum number of bindings to render. Bindings beyond this limit
  /// are silently dropped. Keep small to avoid wrapping issues.
  final int maxBindings;

  /// Separator between bindings. Default: `' · '`.
  final String separator;

  /// Style applied to the entire rendered text.
  final CellStyle style;

  /// Bindings from `runApp`'s `globalBindings` parameter. Pass these
  /// in explicitly so the hint bar can show them; the framework
  /// doesn't currently expose them via an InheritedWidget.
  final List<KeyBinding> globalBindings;

  @override
  Widget build(BuildContext context) {
    final manager = Focus.maybeOf(context);
    if (manager == null) return const EmptyBox();
    final bindings = _collectVisibleBindings(manager);
    if (bindings.isEmpty) return const EmptyBox();
    final rendered = bindings
        .take(maxBindings)
        .map((b) => '[${b.chords.first.hintLabel}] ${b.displayLabel}')
        .join(separator);
    return Text(rendered, style: style, softWrap: false);
  }

  List<KeyBinding> _collectVisibleBindings(FocusManager manager) {
    final result = <KeyBinding>[];
    final seenChords = <String>{};

    void consider(KeyBinding binding) {
      if (binding.label == null) return;
      if (binding.hideFromHintBar) return;
      if (!binding.enabled) return;
      final key = binding.chords.first.hintLabel;
      if (seenChords.contains(key)) return;
      seenChords.add(key);
      result.add(binding);
    }

    for (final node in manager.activeChain()) {
      final source = node.bindingSource;
      if (source == null) continue;
      for (final binding in source.activeBindings) {
        consider(binding);
      }
    }
    if (!manager.suppressGlobals) {
      for (final binding in globalBindings) {
        consider(binding);
      }
    }
    return result;
  }
}
