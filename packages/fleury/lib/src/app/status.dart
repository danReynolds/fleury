import 'package:meta/meta.dart';

import '../foundation/collections.dart';
import '../foundation/change_notifier.dart';
import '../rendering/cell.dart';
import '../semantics/semantics.dart';
import '../widgets/basic.dart';
import '../widgets/framework.dart';
import '../widgets/theme.dart';
import 'commands.dart';

enum StatusSeverity { info, success, warning, error }

/// One status contribution from an app, screen, task, or capability check.
final class StatusItem {
  const StatusItem({
    required this.id,
    required this.label,
    this.value,
    this.severity = StatusSeverity.info,
    this.action,
  });

  factory StatusItem.text(
    String label, {
    String? id,
    String? value,
    CommandId? action,
  }) {
    return StatusItem(
      id: id ?? label,
      label: label,
      value: value,
      action: action,
    );
  }

  factory StatusItem.success(
    String label, {
    String? id,
    String? value,
    CommandId? action,
  }) {
    return StatusItem(
      id: id ?? label,
      label: label,
      value: value,
      severity: StatusSeverity.success,
      action: action,
    );
  }

  factory StatusItem.warning(
    String label, {
    String? id,
    String? value,
    CommandId? action,
  }) {
    return StatusItem(
      id: id ?? label,
      label: label,
      value: value,
      severity: StatusSeverity.warning,
      action: action,
    );
  }

  factory StatusItem.error(
    String label, {
    String? id,
    String? value,
    CommandId? action,
  }) {
    return StatusItem(
      id: id ?? label,
      label: label,
      value: value,
      severity: StatusSeverity.error,
      action: action,
    );
  }

  final String id;
  final String label;
  final String? value;
  final StatusSeverity severity;
  final CommandId? action;

  String get displayText => value == null ? label : '$label: $value';

  @override
  bool operator ==(Object other) =>
      other is StatusItem &&
      other.id == id &&
      other.label == label &&
      other.value == value &&
      other.severity == severity &&
      other.action == action;

  @override
  int get hashCode => Object.hash(id, label, value, severity, action);
}

/// Mutable status model installed by [FleuryApp].
///
/// Two sources feed it. An app or command sets the items it reports itself —
/// a task's progress, a command's result — with [put], [remove] and
/// [update]. [FleuryApp] also derives items from its `status` builder and
/// extensions, and re-derives them after every command and rebuild; those
/// never replace a set item. [items] shows the derived items, each replaced
/// by a set item with the same id, then the set items with ids of their own.
///
/// ```dart
/// run: (context) async {
///   context.status!.put(StatusItem.text('Deploy', value: 'running'));
///   await deploy();
///   context.status!.put(StatusItem.success('Deploy', value: 'done'));
/// },
/// ```
class StatusController extends Notifier {
  StatusController({List<StatusItem> items = const <StatusItem>[]})
    : _set = List<StatusItem>.of(items),
      _items = List<StatusItem>.of(items);

  List<StatusItem> _set;
  List<StatusItem> _derived = const <StatusItem>[];
  List<StatusItem> _items;
  bool _disposed = false;

  List<StatusItem> get items => List<StatusItem>.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  int get length => _items.length;

  /// Sets [item], replacing the set item with its id and leaving the others:
  /// for a writer that owns one item beside items others set.
  void put(StatusItem item) {
    _checkNotDisposed();
    final index = _set.indexWhere((existing) => existing.id == item.id);
    _set = index < 0 ? [..._set, item] : ([..._set]..[index] = item);
    _merge();
  }

  /// Removes the set item with [id], if there is one.
  void remove(String id) {
    _checkNotDisposed();
    _set = [
      for (final item in _set)
        if (item.id != id) item,
    ];
    _merge();
  }

  /// Replaces every set item with [items]. Pass only items you set: [items]
  /// also holds the derived items, and one written back here overrides the
  /// builder's later values for its id.
  void update(List<StatusItem> items) {
    _checkNotDisposed();
    if (listEquals(_set, items)) return;
    _set = List<StatusItem>.of(items);
    _merge();
  }

  /// Framework-internal: replaces the items [FleuryApp] derives from its
  /// status builder and extensions.
  @internal
  void updateDerived(List<StatusItem> items) {
    _checkNotDisposed();
    if (listEquals(_derived, items)) return;
    _derived = List<StatusItem>.of(items);
    _merge();
  }

  void _merge() {
    final setById = {for (final item in _set) item.id: item};
    final derivedIds = {for (final item in _derived) item.id};
    final merged = [
      for (final item in _derived) setById[item.id] ?? item,
      for (final item in _set)
        if (!derivedIds.contains(item.id)) item,
    ];
    if (listEquals(_items, merged)) return;
    _items = merged;
    notify();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('StatusController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

/// Renders the current app status items as a compact terminal status bar.
class AppStatusBar extends StatelessWidget {
  const AppStatusBar({
    super.key,
    this.label = 'Status',
    this.separator = '  ',
    this.emptyText,
  });

  final String label;
  final String separator;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    // FleuryApp shares its StatusController in a scope; reading it here
    // subscribes the bar, so it rebuilds as items change.
    final status = dependOnScope<StatusController>(context);
    if (status == null) {
      throw StateError('No FleuryApp status scope found in context.');
    }
    final items = status.items;
    return Semantics(
      role: SemanticRole.status,
      label: label,
      state: SemanticState({'statusCount': items.length}),
      child: Row(
        children: items.isEmpty
            ? [
                if (emptyText != null)
                  Text(emptyText!, style: const CellStyle(dim: true)),
              ]
            : [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) Text(separator, allowSelect: false),
                  _StatusItemView(item: items[i]),
                ],
              ],
      ),
    );
  }
}

final class _StatusItemView extends StatelessWidget {
  const _StatusItemView({required this.item});

  final StatusItem item;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      id: SemanticNodeId('status:${item.id}'),
      role: SemanticRole.status,
      label: item.label,
      value: item.value,
      actions: <SemanticAction>{
        if (item.action != null) SemanticAction.activate,
      },
      state: SemanticState({
        'statusId': item.id,
        'severity': item.severity.name,
        if (item.action != null) 'commandId': item.action!.value,
      }),
      onAction: item.action == null
          ? null
          : (action) async {
              if (action != SemanticAction.activate) return;
              final registry = CommandRegistryScope.maybeOf(context);
              if (registry == null) return;
              semanticOutcomeOf(
                await registry.invoke(item.action!, buildContext: context),
              );
            },
      child: Text(
        item.displayText,
        style: _styleFor(context, item.severity),
        softWrap: false,
        allowSelect: false,
      ),
    );
  }
}

CellStyle _styleFor(BuildContext context, StatusSeverity severity) {
  final colors = Theme.of(context).colorScheme;
  return switch (severity) {
    StatusSeverity.info => CellStyle(foreground: colors.info),
    StatusSeverity.success => CellStyle(foreground: colors.success),
    StatusSeverity.warning => CellStyle(foreground: colors.warning),
    StatusSeverity.error => CellStyle(foreground: colors.error),
  };
}
