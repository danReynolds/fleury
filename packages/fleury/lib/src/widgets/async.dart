import 'dart:async';

import 'framework.dart';

/// Lifecycle of an async connection feeding an [AsyncSnapshot].
enum ConnectionState {
  /// No [Future]/[Stream] is connected.
  none,

  /// Connected, awaiting the first interaction (e.g. an unresolved future).
  waiting,

  /// Connected and active (a stream that has emitted but isn't done).
  active,

  /// The connection terminated (future completed, or stream closed).
  done,
}

/// An immutable snapshot of the most recent interaction with an async
/// source. Mirrors Flutter's `AsyncSnapshot`.
class AsyncSnapshot<T> {
  const AsyncSnapshot._(
    this.connectionState,
    this.data,
    this.error,
    this.stackTrace,
  );

  /// No data, not connected.
  const AsyncSnapshot.nothing()
    : this._(ConnectionState.none, null, null, null);

  /// Connected, no value yet.
  const AsyncSnapshot.waiting()
    : this._(ConnectionState.waiting, null, null, null);

  /// Carries [data] in the given [state].
  const AsyncSnapshot.withData(ConnectionState state, T data)
    : this._(state, data, null, null);

  /// Carries an [error] (and optional [stackTrace]) in the given [state].
  const AsyncSnapshot.withError(
    ConnectionState state,
    Object error, [
    StackTrace? stackTrace,
  ]) : this._(state, null, error, stackTrace);

  final ConnectionState connectionState;

  /// The latest value, or null if none / errored.
  final T? data;

  /// The latest error, or null.
  final Object? error;
  final StackTrace? stackTrace;

  bool get hasData => data != null;
  bool get hasError => error != null;

  /// The value, asserting one is present. Use after checking [hasData].
  T get requireData {
    if (data == null) {
      throw StateError('AsyncSnapshot has no data (state: $connectionState).');
    }
    return data as T;
  }

  /// A copy in [state] keeping the current data/error.
  AsyncSnapshot<T> inState(ConnectionState state) =>
      AsyncSnapshot<T>._(state, data, error, stackTrace);

  @override
  bool operator ==(Object other) =>
      other is AsyncSnapshot<T> &&
      other.connectionState == connectionState &&
      other.data == data &&
      other.error == error;

  @override
  int get hashCode => Object.hash(connectionState, data, error);

  @override
  String toString() =>
      'AsyncSnapshot($connectionState, data: $data, error: $error)';
}

typedef AsyncWidgetBuilder<T> =
    Widget Function(BuildContext context, AsyncSnapshot<T> snapshot);

/// Rebuilds with the latest [AsyncSnapshot] of [future].
///
/// Create the future once (in `initState` or a field) and pass the same
/// instance — building it inline (`future: fetch()`) re-runs it on every
/// rebuild, the classic FutureBuilder mistake. This widget re-subscribes
/// only when the future *identity* changes, so a stable future is safe.
class FutureBuilder<T> extends StatefulWidget {
  const FutureBuilder({
    super.key,
    required this.future,
    this.initialData,
    required this.builder,
  });

  final Future<T>? future;
  final T? initialData;
  final AsyncWidgetBuilder<T> builder;

  @override
  State<FutureBuilder<T>> createState() => _FutureBuilderState<T>();
}

class _FutureBuilderState<T> extends State<FutureBuilder<T>> {
  // Identity token for the active subscription; bumped on resubscribe and
  // dispose so a stale future's callback is ignored.
  Object? _activeId;
  late AsyncSnapshot<T> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialData == null
        ? AsyncSnapshot<T>.nothing()
        : AsyncSnapshot<T>.withData(
            ConnectionState.none,
            widget.initialData as T,
          );
    _subscribe();
  }

  @override
  void didUpdateWidget(FutureBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.future != widget.future) {
      _activeId = null; // drop the old future's pending callback
      _snapshot = _snapshot.inState(ConnectionState.none);
      _subscribe();
    }
  }

  void _subscribe() {
    final future = widget.future;
    if (future == null) return;
    final id = Object();
    _activeId = id;
    future.then<void>(
      (data) {
        if (!mounted || !identical(_activeId, id)) return;
        setState(() {
          _snapshot = AsyncSnapshot<T>.withData(ConnectionState.done, data);
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || !identical(_activeId, id)) return;
        setState(() {
          _snapshot = AsyncSnapshot<T>.withError(
            ConnectionState.done,
            error,
            stackTrace,
          );
        });
      },
    );
    _snapshot = _snapshot.inState(ConnectionState.waiting);
  }

  @override
  void dispose() {
    _activeId = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _snapshot);
}

/// Rebuilds with the latest [AsyncSnapshot] of [stream] — each event,
/// error, and close. Cancels its subscription on dispose and re-subscribes
/// only when the stream identity changes.
class StreamBuilder<T> extends StatefulWidget {
  const StreamBuilder({
    super.key,
    required this.stream,
    this.initialData,
    required this.builder,
  });

  final Stream<T>? stream;
  final T? initialData;
  final AsyncWidgetBuilder<T> builder;

  @override
  State<StreamBuilder<T>> createState() => _StreamBuilderState<T>();
}

class _StreamBuilderState<T> extends State<StreamBuilder<T>> {
  StreamSubscription<T>? _subscription;
  late AsyncSnapshot<T> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialData == null
        ? AsyncSnapshot<T>.nothing()
        : AsyncSnapshot<T>.withData(
            ConnectionState.none,
            widget.initialData as T,
          );
    _subscribe();
  }

  @override
  void didUpdateWidget(StreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream) {
      _unsubscribe();
      _snapshot = _snapshot.inState(ConnectionState.none);
      _subscribe();
    }
  }

  void _subscribe() {
    final stream = widget.stream;
    if (stream == null) return;
    _subscription = stream.listen(
      (data) => setState(() {
        _snapshot = AsyncSnapshot<T>.withData(ConnectionState.active, data);
      }),
      onError: (Object error, StackTrace stackTrace) => setState(() {
        _snapshot = AsyncSnapshot<T>.withError(
          ConnectionState.active,
          error,
          stackTrace,
        );
      }),
      onDone: () => setState(() {
        _snapshot = _snapshot.inState(ConnectionState.done);
      }),
    );
    _snapshot = _snapshot.inState(ConnectionState.waiting);
  }

  void _unsubscribe() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _snapshot);
}
