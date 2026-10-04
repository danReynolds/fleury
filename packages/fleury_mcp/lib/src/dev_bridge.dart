import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury_dev_io.dart';
import 'package:fleury/fleury_host.dart';

import 'app_bridge.dart';

/// Attaches without acquiring terminal or app lifetime ownership.
final class FleuryDevBridge implements FleuryAppConnection {
  FleuryDevBridge._(this._client);
  final DevSessionClient _client;
  final _done = Completer<void>();
  SemanticInspectionSnapshot? _snapshot;
  String _epoch = '';
  String? _encoded;
  int _revision = 0;
  int _generation = 0;
  int _inspectionSequence = 0;
  CellSize _viewport = const CellSize(80, 24);
  bool _closed = false;
  bool _accumulate = false;
  bool _changed = false;
  Future<Map<String, Object?>>? _refreshing;

  static Future<FleuryDevBridge> attach({
    required String projectDirectory,
    String? sessionId,
  }) async {
    final DevSessionClient client;
    try {
      client = await DevSessionClient.connect(
        projectDirectory: projectDirectory,
        sessionId: sessionId,
      );
    } catch (error) {
      throw FleuryAppBridgeException(error.toString());
    }
    final bridge = FleuryDevBridge._(client);
    try {
      await bridge.refresh();
      return bridge;
    } catch (_) {
      await bridge.close();
      rethrow;
    }
  }

  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (_closed) {
      throw const FleuryAppBridgeException('Development attachment is closed.');
    }
    try {
      return await _client.request(method, params);
    } catch (error) {
      if (error is SocketException || error is HttpException) await close();
      throw FleuryAppBridgeException(error.toString());
    }
  }

  void _accept(Map<String, Object?> inspection) {
    final epoch = inspection['epoch'] as String;
    final generation = inspection['generation'] as int;
    final sequence = inspection['inspectionSequence'] as int;
    if (generation < _generation ||
        (generation == _generation && sequence <= _inspectionSequence)) {
      throw const FleuryAppBridgeException(
        'Inspection was superseded. Read the current app again.',
      );
    }
    _generation = generation;
    _inspectionSequence = sequence;
    final ui = (inspection['ui'] as Map).cast<String, Object?>();
    // Carry the observed epoch inside each node's private dispatch token.
    // A concurrent inspection cannot launder an old action into a new app.
    void stamp(Map<Object?, Object?> node) {
      node['actionTargetToken'] = jsonEncode([
        epoch,
        node['actionTargetToken'],
      ]);
      for (final child in node['children'] as List? ?? const []) {
        stamp(child as Map);
      }
    }

    stamp(ui['root'] as Map);
    final encoded = jsonEncode(ui);
    if (_encoded != encoded || _epoch != epoch) {
      _revision++;
      if (_accumulate) _changed = true;
      _snapshot = SemanticInspectionSnapshot.fromJson(ui);
      _encoded = encoded;
    }
    _epoch = epoch;
    inspection['semanticRevision'] = _revision;
    final size = inspection['viewport'] as Map;
    _viewport = CellSize(size['cols'] as int, size['rows'] as int);
  }

  Future<Map<String, Object?>> inspect([
    Map<String, Object?> params = const {},
  ]) async {
    final data = await request('inspect', params);
    _accept(data);
    return data;
  }

  Future<Map<String, Object?>> control(String method) async {
    final data = await request(method);
    final inspection = (data['inspection'] as Map).cast<String, Object?>();
    _accept(inspection);
    return data;
  }

  @override
  Future<void> refresh() async {
    final running = _refreshing;
    if (running != null) {
      await running;
      return;
    }
    final future = inspect(const {'cells': false});
    _refreshing = future;
    try {
      await future;
    } finally {
      _refreshing = null;
    }
  }

  Future<SemanticActionInvocationStatus?> _action(
    SemanticNodeId id,
    SemanticAction action,
    Object? value,
    String? token,
  ) async {
    if (token == null) {
      throw const FleuryAppBridgeException(
        'Inspect this control before acting.',
      );
    }
    final observed = jsonDecode(token) as List;
    final result = await request('action', {
      'id': id.value,
      'action': action.name,
      'value': value,
      'epoch': observed[0],
      'targetToken': observed[1],
    });
    if (result['status'] == 'pending') {
      throw FleurySemanticActionTimeoutException(id, action);
    }
    return SemanticActionInvocationStatus.values.byName(
      result['status'] as String,
    );
  }

  @override
  Future<SemanticActionInvocationStatus?> invokeAction(
    SemanticNodeId id,
    SemanticAction action, {
    String? targetToken,
  }) => _action(id, action, null, targetToken);
  @override
  Future<SemanticActionInvocationStatus?> setValue(
    SemanticNodeId id,
    Object? value, {
    String? targetToken,
  }) => _action(id, SemanticAction.setValue, value, targetToken);
  @override
  Future<List<Object?>?> queryDebug(String kind, {int limit = 50}) async =>
      (await request('debug', {'kind': kind, 'limit': limit}))['records']
          as List;

  @override
  Future<SemanticInspectionSnapshot?> settle({
    int? sinceRevision,
    Duration quiet = const Duration(milliseconds: 60),
    Duration timeout = const Duration(seconds: 2),
    Duration settleCap = const Duration(milliseconds: 500),
  }) async {
    final clock = Stopwatch()..start();
    var lastChanged = Duration.zero;
    var previous = revision;
    while (isRunning && clock.elapsed < timeout) {
      await refresh();
      if (revision != previous) {
        previous = revision;
        lastChanged = clock.elapsed;
      }
      if ((sinceRevision == null || revision != sinceRevision) &&
          (clock.elapsed - lastChanged >= quiet ||
              clock.elapsed >= settleCap)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    return snapshot;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close();
    _done.complete();
  }

  @override
  CellSize get viewport => _viewport;
  @override
  SemanticInspectionSnapshot? get snapshot => _snapshot;
  @override
  int get revision => _revision;
  @override
  String get sessionEpoch => _epoch;
  @override
  bool get isRunning => !_closed;
  @override
  bool get renderTimedOut => false;
  @override
  String? get protocolError => null;
  @override
  Future<void> get ready => Future.value();
  @override
  Future<void> get done => _done.future;
  @override
  set accumulateDeltas(bool value) {
    _accumulate = value;
    _changed = false;
  }

  @override
  SemanticTreeDelta takeDelta() {
    final changed = _changed;
    _changed = false;
    return SemanticTreeDelta(
      changedIds: changed
          ? [
              for (final node in snapshot?.nodes ?? <SemanticInspectionNode>[])
                node.id,
            ]
          : [],
      removedIds: const [],
      full: changed,
    );
  }

  @override
  void typeText(String text) => throw const FleuryAppBridgeException(
    'Use set_value on a native dev session.',
  );
  @override
  void pressKey(KeyCode code, {Set<KeyModifier> modifiers = const {}}) =>
      throw const FleuryAppBridgeException(
        'Use semantic actions on a native dev session.',
      );
  @override
  void resize(CellSize size) => throw const FleuryAppBridgeException(
    'Resize the actual terminal for this native session.',
  );
}
