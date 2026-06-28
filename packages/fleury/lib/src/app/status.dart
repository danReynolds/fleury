import '../foundation/change_notifier.dart';
import '../rendering/cell.dart';
import '../semantics/semantics.dart';
import '../widgets/basic.dart';
import '../widgets/framework.dart';
import '../widgets/listenable_builder.dart';
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
class StatusController extends ChangeNotifier {
  StatusController({List<StatusItem> items = const <StatusItem>[]})
    : _items = List<StatusItem>.of(items);

  List<StatusItem> _items;
  bool _disposed = false;

  List<StatusItem> get items => List<StatusItem>.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  int get length => _items.length;

  void update(List<StatusItem> items) {
    _checkNotDisposed();
    if (_listEquals(_items, items)) return;
    _items = List<StatusItem>.of(items);
    notifyListeners();
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

bool _listEquals(List<StatusItem> a, List<StatusItem> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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
    final app = StatusHost.of(context);
    final status = app.status;
    return ListenableBuilder(
      listenable: status,
      builder: (context, _) {
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
      },
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
              await registry.invoke(item.action!, buildContext: context);
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

/// Private bridge implemented in app.dart to avoid making status.dart depend
/// on app.dart and creating an import cycle.
abstract interface class StatusHost {
  StatusController get status;

  static StatusHost of(BuildContext context) {
    final widget = context
        .dependOnInheritedWidgetOfExactType<StatusHostScope>()
        ?.lookup;
    if (widget == null) {
      throw StateError('No FleuryApp status scope found in context.');
    }
    return widget;
  }
}

class StatusHostScope extends InheritedWidget {
  const StatusHostScope({required this.lookup, required super.child});

  final StatusHost lookup;

  @override
  bool updateShouldNotify(StatusHostScope oldWidget) {
    return lookup != oldWidget.lookup;
  }
}
