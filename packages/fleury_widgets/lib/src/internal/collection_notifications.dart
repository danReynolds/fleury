import 'package:fleury/fleury_core.dart';

/// Forwards every list notification through a collection controller while
/// keeping completed layout metrics out of the collection's build dependency.
/// Explicit controller notifications still refresh content. Kept here so every
/// collection shares the same forwarding and reentrant-notification behavior.
class CollectionNotifications extends Notifier {
  CollectionNotifications(
    this._list, {
    required void Function() dispatch,
    required void Function() publish,
  }) : _dispatch = dispatch,
       _publish = publish,
       _listViewChanges = _list.viewChanges {
    _listViewChanges.addListener(_notifyViewChanges);
    _list.addListener(_forward);
  }

  final ListController _list;
  final Listenable _listViewChanges;
  final void Function() _dispatch;
  final void Function() _publish;
  Listenable get viewChanges => this;

  void _notifyViewChanges() => super.notify();
  bool _forwarding = false;
  bool _disposed = false;

  void _forward() {
    _forwarding = true;
    try {
      // Preserve overrides of the public controller's notify method.
      _dispatch();
    } finally {
      _forwarding = false;
    }
  }

  void publish() {
    final forwarded = _forwarding;
    // Consume before callbacks: a listener's nested explicit refresh is a
    // content change, even when the outer notification reports metrics.
    _forwarding = false;
    if (!forwarded) {
      _notifyViewChanges();
      if (_disposed) return;
    }
    _publish();
  }

  @override
  void dispose() {
    _disposed = true;
    _listViewChanges.removeListener(_notifyViewChanges);
    _list.removeListener(_forward);
    super.dispose();
  }
}
