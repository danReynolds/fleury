import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import '../foundation/geometry.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../semantics/inspection.dart';
import '../semantics/semantics.dart';
import '../widgets/framework.dart';
import 'dev_session.dart';

DevAgentRuntime? _active;
bool _registered = false;

/// On-demand inspection at the frame boundary; never reads a half-built tree.
/// The extension is registered only by an explicitly opted-in native dev app.
final class DevAgentRuntime {
  DevAgentRuntime({
    required this.readRoot,
    required this.scheduleFrame,
    required this.readDebug,
    required this.reportError,
  }) {
    _active = this;
    if (!_registered) {
      developer.registerExtension('ext.fleury.agent', (_, parameters) async {
        final active = _active;
        if (active == null) {
          return developer.ServiceExtensionResponse.result(
            jsonEncode({'error': 'App is closing.'}),
          );
        }
        // Extensions outlive runApp. Re-enter this session's capture/error zone
        // so action handlers log and fail exactly like human-triggered actions.
        return active._zone.run(() async {
          try {
            final result = await active.request(
              parameters['method']!,
              (jsonDecode(parameters['params']!) as Map)
                  .cast<String, Object?>(),
            );
            return developer.ServiceExtensionResponse.result(
              jsonEncode(result),
            );
          } catch (error) {
            return developer.ServiceExtensionResponse.result(
              jsonEncode({'error': error.toString()}),
            );
          }
        });
      });
      _registered = true;
    }
  }

  final Zone _zone = Zone.current;
  final Element? Function() readRoot;
  final void Function() scheduleFrame;
  final List<Object?> Function(String, int) readDebug;
  final void Function(Object, StackTrace) reportError;
  final String epoch = DateTime.now().microsecondsSinceEpoch.toString();
  final _pending =
      <
        ({Map<String, Object?> params, Completer<Map<String, Object?>> result})
      >[];
  final _actions = <(String, String)>{};
  CellBuffer? _lastFrame;
  int _frameRevision = 0;
  int _inspectionSequence = 0;
  bool _disposed = false;

  void onFrame(CellBuffer? frame) {
    if (_disposed) return;
    if (frame != null) {
      _lastFrame = frame;
      _frameRevision++;
    }
    final buffer = _lastFrame;
    final root = readRoot();
    if (_pending.isEmpty || buffer == null || root == null) return;
    final pending = _pending.toList();
    _pending.clear();
    // No awaits: cells, semantics, and layout refer to this one frame boundary.
    final SemanticTree tree;
    try {
      tree = SemanticTree.fromElement(root);
    } catch (error, stack) {
      for (final query in pending) {
        query.result.completeError(error, stack);
      }
      return;
    }
    for (final query in pending) {
      try {
        query.result.complete(_inspect(buffer, tree, query.params));
      } catch (error, stack) {
        query.result.completeError(error, stack);
      }
    }
  }

  Future<Map<String, Object?>> request(
    String method,
    Map<String, Object?> params,
  ) async {
    if (_disposed) throw const DevSessionException('App is closing.');
    if (method == 'inspect') {
      if (_pending.length >= 16) {
        throw const DevSessionException('Too many inspections.');
      }
      final result = Completer<Map<String, Object?>>();
      final query = (params: params, result: result);
      _pending.add(query);
      scheduleFrame();
      try {
        return await result.future.timeout(const Duration(seconds: 5));
      } finally {
        _pending.remove(query);
      }
    }
    if (method == 'debug') {
      return {
        'records': readDebug(
          params['kind'] as String,
          (params['limit'] as int? ?? 50).clamp(0, 500),
        ),
      };
    }
    if (method != 'action') {
      throw const DevSessionException('Unknown app operation.');
    }
    if (params['epoch'] != epoch) {
      throw const DevSessionException('Stale app generation. Inspect again.');
    }
    final root = readRoot();
    if (root == null) throw const DevSessionException('App is not ready.');
    final id = params['id'] as String;
    final actionName = params['action'] as String;
    final action = SemanticAction.values.byName(actionName);
    final tree = SemanticTree.fromElement(root);
    final node = tree.nodeById(SemanticNodeId(id));
    if (node == null) return {'status': 'notFound'};
    if (node.actionTargetToken != params['targetToken']) {
      throw const DevSessionException(
        'Stale control reference. Inspect again.',
      );
    }
    final key = (id, actionName);
    if (_actions.contains(key) || _actions.length >= 16) {
      throw const DevSessionException(
        'Action is still pending; do not retry it.',
      );
    }
    _actions.add(key);
    // Retain the busy slot after a timeout until the handler actually finishes.
    final result = () async {
      try {
        final result = await invokeSemanticActionFromElement(
          tree: tree,
          id: SemanticNodeId(id),
          action: action,
          value: params['value'],
        );
        if (result.error != null) {
          reportError(result.error!, result.stackTrace ?? StackTrace.current);
        }
        if (!_disposed) scheduleFrame();
        return <String, Object?>{'status': result.status.name};
      } finally {
        _actions.remove(key);
      }
    }();
    return result.timeout(
      const Duration(seconds: 10),
      onTimeout: () => {'status': 'pending'},
    );
  }

  Map<String, Object?> _inspect(
    CellBuffer buffer,
    SemanticTree tree,
    Map<String, Object?> params,
  ) {
    final region =
        (params['region'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    int coordinate(String key, int fallback) {
      final value = region[key] ?? fallback;
      if (value is! int || value < 0) {
        throw DevSessionException('Invalid region.$key.');
      }
      return value;
    }

    final left = coordinate('left', 0).clamp(0, buffer.size.cols);
    final top = coordinate('top', 0).clamp(0, buffer.size.rows);
    final cols = coordinate(
      'cols',
      buffer.size.cols,
    ).clamp(0, buffer.size.cols - left).clamp(0, 200);
    final rows = coordinate(
      'rows',
      buffer.size.rows,
    ).clamp(0, buffer.size.rows - top).clamp(0, 100);
    final styles = <CellStyle, int>{};
    final cells = <Object?>[];
    final text = <String>[];
    if (params['cells'] != false) {
      for (var row = top; row < top + rows; row++) {
        final line = <List<Object?>>[];
        final plain = StringBuffer();
        Cell? previous;
        for (var col = left; col < left + cols; col++) {
          final cell = buffer.atColRow(col, row);
          final style = styles.putIfAbsent(cell.style, () => styles.length);
          if (previous == cell && line.isNotEmpty) {
            line.last[0] = (line.last[0] as int) + 1;
          } else {
            line.add([1, cell.grapheme, cell.role.name, style]);
          }
          previous = cell;
          plain.write(
            cell.grapheme ?? (cell.role == CellRole.continuation ? '' : ' '),
          );
        }
        cells.add(line);
        text.add(plain.toString());
      }
    }
    final nodeId = params['node'] as String?;
    final ancestry = <Object?>[];
    var ancestryTruncated = false;
    if (nodeId != null) {
      var element = tree.elementById(SemanticNodeId(nodeId));
      if (element == null) throw DevSessionException('No unique node $nodeId.');
      while (element != null && ancestry.length < 80) {
        final render = element.findRenderObject();
        final geometry = render?.screenGeometry();
        final constraints = render != null && render.hasLayout
            ? render.constraints
            : null;
        ancestry.add({
          'widget': element.widget.runtimeType.toString(),
          if (element.widget.key != null) 'key': element.widget.key.toString(),
          if (render != null) 'renderObject': render.runtimeType.toString(),
          if (constraints != null)
            'constraints': {
              'minCols': constraints.minCols,
              'maxCols': constraints.maxCols,
              'minRows': constraints.minRows,
              'maxRows': constraints.maxRows,
            },
          if (render != null && render.hasLayout)
            'size': {'cols': render.size.cols, 'rows': render.size.rows},
          'bounds': _rect(geometry?.bounds),
          'clip': _rect(geometry?.clip),
          'visible': _rect(geometry?.visible),
        });
        element = element.elementParent;
      }
      ancestryTruncated = element != null;
    }
    return {
      'epoch': epoch,
      'frameRevision': _frameRevision,
      'inspectionSequence': ++_inspectionSequence,
      'viewport': {'cols': buffer.size.cols, 'rows': buffer.size.rows},
      'ui': tree.toInspectionSnapshot().toJsonCapped(
        maxNodes: 10000,
        augment: (node) => {'actionTargetToken': node.actionTargetToken},
      ),
      if (params['cells'] != false)
        'render': {
          'region': {'left': left, 'top': top, 'cols': cols, 'rows': rows},
          'cropped':
              left != 0 ||
              top != 0 ||
              cols != buffer.size.cols ||
              rows != buffer.size.rows,
          'text': text,
          'cells': cells,
          'cellFormat': ['repeat', 'grapheme', 'role', 'styleIndex'],
          'styles': [for (final style in styles.keys) _style(style)],
          'note':
              'Logical cell paint before terminal color quantization. Overlay cells mark images; image pixels are not included.',
        },
      if (nodeId != null) 'ancestry': ancestry,
      if (nodeId != null) 'ancestryTruncated': ancestryTruncated,
    };
  }

  void dispose() {
    _disposed = true;
    if (identical(_active, this)) _active = null;
    for (final query in _pending) {
      query.result.completeError(const DevSessionException('App is closing.'));
    }
    _pending.clear();
    _lastFrame = null;
  }
}

Map<String, int>? _rect(CellRect? rect) => rect == null
    ? null
    : {
        'left': rect.left,
        'top': rect.top,
        'cols': rect.size.cols,
        'rows': rect.size.rows,
      };

Object? _color(Color? color) => switch (color) {
  AnsiColor(:final index) => {'ansi': index},
  IndexedColor(:final index) => {'indexed': index},
  RgbColor(:final r, :final g, :final b) => {
    'rgb': [r, g, b],
  },
  null => null,
};

Map<String, Object?> _style(CellStyle s) => {
  'foreground': _color(s.foreground),
  'background': _color(s.background),
  'bold': s.bold,
  'dim': s.dim,
  'italic': s.italic,
  'underline': s.underline,
  'inverse': s.inverse,
  'strikethrough': s.strikethrough,
  'linkUri': s.linkUri,
};
