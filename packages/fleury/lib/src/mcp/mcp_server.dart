// A Model Context Protocol (MCP) server that exposes a running Fleury app to an
// AI agent. It speaks JSON-RPC 2.0 over a newline-delimited stdio transport —
// the shape MCP hosts (Claude Desktop, Claude Code, …) launch and talk to.
//
// The mapping is direct, because Fleury already emits MCP's two shapes:
//
//   • a Resource  — `fleury://ui/tree`, the app's live semantic snapshot;
//   • Tools       — read the tree, query it, and invoke the SemanticActions /
//                   text input that the [FleuryAppBridge] carries to the app.
//
// Zero external dependencies: the JSON-RPC framing is a handful of maps over
// `dart:convert`, and every effect routes through the bridge.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../semantics/inspection.dart';
import '../semantics/semantics.dart';
import '../terminal/events.dart';
import 'app_bridge.dart';

/// MCP protocol revision this server implements. The handshake echoes the
/// client's requested revision when it sends one (our tool/resource surface is
/// revision-stable), falling back to this.
const String mcpProtocolVersion = '2025-06-18';

/// Server identity reported in the `initialize` handshake.
const String mcpServerName = 'fleury';
const String mcpServerVersion = '0.1.0';

/// JSON-RPC 2.0 error codes used by this server.
const int _parseError = -32700;
const int _invalidRequest = -32600;
const int _methodNotFound = -32601;

/// Reads newline-delimited JSON-RPC from [input], dispatches against [bridge],
/// and writes responses to [output] (flushed per message — stdio to a pipe is
/// block-buffered). Returns when [input] closes (the host disconnected).
Future<void> runMcpServer({
  required FleuryAppBridge bridge,
  required Stream<List<int>> input,
  required IOSink output,
}) async {
  final server = McpServer(
    bridge: bridge,
    send: (line) => output.write('$line\n'),
  );
  final lines = input
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  await for (final line in lines) {
    if (line.trim().isEmpty) continue;
    await server.handleLine(line);
    await output.flush();
  }
}

/// The transport-agnostic JSON-RPC core. Feed it raw request lines via
/// [handleLine]; it calls [send] with each response line. Split out from the
/// stdio runner so tests can drive it with in-memory streams.
final class McpServer {
  McpServer({required this.bridge, required this.send});

  final FleuryAppBridge bridge;
  final void Function(String jsonLine) send;

  static final Map<String, SemanticAction> _actionsByName = {
    for (final a in SemanticAction.values) a.name: a,
  };
  static final Map<String, KeyCode> _keysByName = {
    for (final k in KeyCode.values) k.name: k,
  };

  /// Parses and dispatches a single JSON-RPC line.
  Future<void> handleLine(String line) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      _sendMessage(_errorMessage(null, _parseError, 'Invalid JSON'));
      return;
    }
    if (decoded is! Map) {
      _sendMessage(
        _errorMessage(null, _invalidRequest, 'Request must be a JSON object'),
      );
      return;
    }
    final id = decoded['id'];
    final method = decoded['method'];
    if (method is! String) {
      // A response or a malformed frame — nothing for a server to act on.
      if (id != null) {
        _sendMessage(_errorMessage(id, _invalidRequest, 'Missing method'));
      }
      return;
    }
    final params = decoded['params'] is Map
        ? (decoded['params'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final isNotification = !decoded.containsKey('id');

    // Notifications (no id) are fire-and-forget; never reply to them.
    if (isNotification) {
      return; // initialized / cancelled / progress — nothing to do.
    }

    switch (method) {
      case 'initialize':
        _sendMessage(_resultMessage(id, _initializeResult(params)));
      case 'ping':
        _sendMessage(_resultMessage(id, const <String, Object?>{}));
      case 'tools/list':
        _sendMessage(_resultMessage(id, <String, Object?>{'tools': _toolDefs}));
      case 'tools/call':
        _sendMessage(_resultMessage(id, await _callTool(params)));
      case 'resources/list':
        _sendMessage(
          _resultMessage(id, <String, Object?>{'resources': _resourceDefs}),
        );
      case 'resources/templates/list':
        _sendMessage(
          _resultMessage(id, const <String, Object?>{'resourceTemplates': []}),
        );
      case 'resources/read':
        _sendMessage(_resultMessage(id, await _readResource(params)));
      default:
        _sendMessage(
          _errorMessage(id, _methodNotFound, 'Unknown method: $method'),
        );
    }
  }

  // ---- initialize ----------------------------------------------------------

  Map<String, Object?> _initializeResult(Map<String, Object?> params) {
    final requested = params['protocolVersion'];
    return <String, Object?>{
      'protocolVersion': requested is String && requested.isNotEmpty
          ? requested
          : mcpProtocolVersion,
      'capabilities': <String, Object?>{
        'tools': <String, Object?>{},
        'resources': <String, Object?>{},
      },
      'serverInfo': <String, Object?>{
        'name': mcpServerName,
        'version': mcpServerVersion,
      },
      'instructions':
          'This server drives a running Fleury terminal-UI app through its '
          'semantic tree. Call get_ui to read the UI as roles/labels/values '
          'with the actions each node supports, then invoke_action / type_text '
          '/ press_key to operate it. Re-read get_ui after each action to see '
          'what changed. Never guess keystrokes — prefer the advertised '
          'SemanticActions.',
    };
  }

  // ---- resources -----------------------------------------------------------

  static const String _treeUri = 'fleury://ui/tree';

  static const List<Map<String, Object?>> _resourceDefs = <Map<String, Object?>>[
    <String, Object?>{
      'uri': _treeUri,
      'name': 'UI semantic tree',
      'description':
          "The running app's current accessible semantic tree (schema v1): "
          'every node\'s role, label, value, state, and supported actions. '
          'The same artifact get_ui returns.',
      'mimeType': 'application/json',
    },
  ];

  Future<Map<String, Object?>> _readResource(Map<String, Object?> params) async {
    final uri = params['uri'];
    if (uri != _treeUri) {
      throw StateError('Unknown resource: $uri');
    }
    final snapshot = await _currentSnapshot();
    final text = snapshot == null
        ? '{}'
        : jsonEncode(snapshot.toJson());
    return <String, Object?>{
      'contents': <Object?>[
        <String, Object?>{
          'uri': _treeUri,
          'mimeType': 'application/json',
          'text': text,
        },
      ],
    };
  }

  // ---- tools ---------------------------------------------------------------

  static final List<Map<String, Object?>> _toolDefs = <Map<String, Object?>>[
    <String, Object?>{
      'name': 'get_ui',
      'description':
          "Read the running app's current UI as a semantic tree — every node's "
          'role, label, value, state (focused/selected/checked/…), and the '
          'actions it supports. Call this first, and after each action, to see '
          'the current state. No screen-scraping: the ids and actions here are '
          'what you drive the UI with.',
      'inputSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      },
    },
    <String, Object?>{
      'name': 'find_nodes',
      'description':
          'Find UI nodes matching a query — handy on a large tree. Filter by '
          'role (e.g. "button", "tableRow", "textField"), label substring, an '
          'action the node supports, or focus/selection state. Returns each '
          "match's id (use it with invoke_action), role, label, value, and "
          'available actions.',
      'inputSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'role': <String, Object?>{
            'type': 'string',
            'description': 'Exact role name to match.',
          },
          'label': <String, Object?>{
            'type': 'string',
            'description': 'Case-insensitive substring of the node label.',
          },
          'action': <String, Object?>{
            'type': 'string',
            'description': 'Only nodes that advertise this SemanticAction.',
          },
          'focused': <String, Object?>{'type': 'boolean'},
          'selected': <String, Object?>{'type': 'boolean'},
        },
      },
    },
    <String, Object?>{
      'name': 'invoke_action',
      'description':
          'Invoke a SemanticAction on a node (by id, from get_ui/find_nodes). '
          'This is how you operate the UI — activate a button, select a row, '
          'submit a form, increment a slider — instead of guessing keystrokes. '
          'The node must advertise the action. Returns the UI after it settles. '
          'Actions: $_actionNames.',
      'inputSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'id': <String, Object?>{
            'type': 'string',
            'description': 'Node id from get_ui / find_nodes.',
          },
          'action': <String, Object?>{
            'type': 'string',
            'description': 'The SemanticAction to invoke.',
            'enum': <Object?>[for (final a in SemanticAction.values) a.name],
          },
        },
        'required': <Object?>['id', 'action'],
      },
    },
    <String, Object?>{
      'name': 'type_text',
      'description':
          'Type text into the currently focused input. Focus an input first — '
          "invoke_action with 'focus' (or 'activate') on a textField/textArea "
          'node — then call this. Returns the UI after it settles.',
      'inputSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'text': <String, Object?>{
            'type': 'string',
            'description': 'The text to type.',
          },
        },
        'required': <Object?>['text'],
      },
    },
    <String, Object?>{
      'name': 'press_key',
      'description':
          'Press a key. Use a named key (enter, tab, escape, backspace, '
          'arrowUp, arrowDown, arrowLeft, arrowRight, home, end, pageUp, '
          'pageDown, delete, f1–f12) or a single literal character. Optional '
          "modifiers: ctrl, alt, shift. Prefer invoke_action when an "
          'equivalent SemanticAction exists. Returns the UI after it settles.',
      'inputSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'key': <String, Object?>{
            'type': 'string',
            'description': 'A named key (e.g. "enter") or a single character.',
          },
          'modifiers': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{
              'type': 'string',
              'enum': <Object?>['ctrl', 'alt', 'shift'],
            },
          },
        },
        'required': <Object?>['key'],
      },
    },
  ];

  static String get _actionNames =>
      SemanticAction.values.map((a) => a.name).join(', ');

  Future<Map<String, Object?>> _callTool(Map<String, Object?> params) async {
    final name = params['name'];
    final args = params['arguments'] is Map
        ? (params['arguments'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    if (name is! String) {
      return _toolError('tools/call is missing a tool name.');
    }
    if (!bridge.isRunning) {
      return _toolError('The Fleury app has exited; no UI to drive.');
    }
    try {
      switch (name) {
        case 'get_ui':
          return await _toolGetUi();
        case 'find_nodes':
          return await _toolFindNodes(args);
        case 'invoke_action':
          return await _toolInvokeAction(args);
        case 'type_text':
          return await _toolTypeText(args);
        case 'press_key':
          return await _toolPressKey(args);
        default:
          return _toolError('Unknown tool: $name');
      }
    } on _ToolFailure catch (failure) {
      return _toolError(failure.message);
    }
  }

  Future<Map<String, Object?>> _toolGetUi() async {
    final snapshot = await _requireSnapshot();
    return _toolJson(_describeTree(snapshot));
  }

  Future<Map<String, Object?>> _toolFindNodes(Map<String, Object?> args) async {
    final snapshot = await _requireSnapshot();
    final role = _optString(args['role']);
    final label = _optString(args['label'])?.toLowerCase();
    final action = _optString(args['action']);
    final focused = args['focused'] is bool ? args['focused'] as bool : null;
    final selected = args['selected'] is bool ? args['selected'] as bool : null;

    final matches = <SemanticInspectionNode>[];
    for (final node in snapshot.nodes) {
      if (role != null && node.role != role) continue;
      if (label != null &&
          !(node.label ?? '').toLowerCase().contains(label)) {
        continue;
      }
      if (action != null && !node.actions.contains(action)) continue;
      if (focused != null && node.focused != focused) continue;
      if (selected != null && node.selected != selected) continue;
      matches.add(node);
    }

    const cap = 50;
    final truncated = matches.length > cap;
    return _toolJson(<String, Object?>{
      'matchCount': matches.length,
      if (truncated) 'truncated': true,
      if (truncated) 'shown': cap,
      'nodes': <Object?>[
        for (final node in matches.take(cap)) _flatNode(node),
      ],
    });
  }

  Future<Map<String, Object?>> _toolInvokeAction(
    Map<String, Object?> args,
  ) async {
    final id = _optString(args['id']);
    final actionName = _optString(args['action']);
    if (id == null || id.isEmpty) {
      throw const _ToolFailure('invoke_action requires a node "id".');
    }
    if (actionName == null || actionName.isEmpty) {
      throw const _ToolFailure('invoke_action requires an "action".');
    }
    final action = _actionsByName[actionName];
    if (action == null) {
      throw _ToolFailure(
        'Unknown action "$actionName". Valid actions: $_actionNames.',
      );
    }
    final snapshot = await _requireSnapshot();
    final node = snapshot.nodeById(id);
    if (node == null) {
      throw _ToolFailure(
        'No node with id "$id" in the current UI. Call get_ui or find_nodes '
        'for current ids (they are snapshot-local and change as the UI '
        'rebuilds).',
      );
    }
    if (!node.actions.contains(actionName)) {
      throw _ToolFailure(
        'Node "$id" (${node.role}${node.label == null ? '' : ' "${node.label}"'}) '
        'does not advertise "$actionName". It supports: '
        '${node.actions.isEmpty ? '(none)' : node.actions.join(', ')}.',
      );
    }

    final before = bridge.revision;
    bridge.invokeAction(SemanticNodeId(id), action);
    final after = await bridge.settle(sinceRevision: before);
    return _toolJson(<String, Object?>{
      'invoked': <String, Object?>{'id': id, 'action': actionName},
      'changed': after != null && bridge.revision != before,
      'ui': after == null ? null : _describeTree(after),
    });
  }

  Future<Map<String, Object?>> _toolTypeText(Map<String, Object?> args) async {
    final text = _optString(args['text']);
    if (text == null) {
      throw const _ToolFailure('type_text requires "text".');
    }
    final before = bridge.revision;
    bridge.typeText(text);
    final after = await bridge.settle(sinceRevision: before);
    return _toolJson(<String, Object?>{
      'typed': text,
      'changed': after != null && bridge.revision != before,
      'ui': after == null ? null : _describeTree(after),
    });
  }

  Future<Map<String, Object?>> _toolPressKey(Map<String, Object?> args) async {
    final key = _optString(args['key']);
    if (key == null || key.isEmpty) {
      throw const _ToolFailure('press_key requires "key".');
    }
    final modifiers = <KeyModifier>{};
    final rawMods = args['modifiers'];
    if (rawMods is List) {
      for (final m in rawMods) {
        switch (m) {
          case 'ctrl':
            modifiers.add(KeyModifier.ctrl);
          case 'alt':
            modifiers.add(KeyModifier.alt);
          case 'shift':
            modifiers.add(KeyModifier.shift);
        }
      }
    }

    final keyCode = _keysByName[key];
    final char = keyCode == null ? key : null;
    if (keyCode == null && key.runes.length != 1) {
      throw _ToolFailure(
        'Unrecognized key "$key". Use a named key '
        '(${_keysByName.keys.join(', ')}) or a single character.',
      );
    }

    final before = bridge.revision;
    bridge.pressKey(keyCode: keyCode, char: char, modifiers: modifiers);
    final after = await bridge.settle(sinceRevision: before);
    return _toolJson(<String, Object?>{
      'pressed': <String, Object?>{
        'key': key,
        if (modifiers.isNotEmpty)
          'modifiers': <Object?>[for (final m in modifiers) m.name],
      },
      'changed': after != null && bridge.revision != before,
      'ui': after == null ? null : _describeTree(after),
    });
  }

  // ---- snapshot helpers ----------------------------------------------------

  /// The latest snapshot, waiting briefly for the app's first frame if it
  /// hasn't rendered yet.
  Future<SemanticInspectionSnapshot?> _currentSnapshot() async {
    if (bridge.snapshot != null) return bridge.snapshot;
    try {
      await bridge.ready.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      return null;
    } on StateError {
      return null; // app exited before rendering
    }
    return bridge.snapshot;
  }

  Future<SemanticInspectionSnapshot> _requireSnapshot() async {
    final snapshot = await _currentSnapshot();
    if (snapshot == null) {
      throw const _ToolFailure(
        'The app has not rendered a UI yet (no semantic frame received).',
      );
    }
    return snapshot;
  }

  /// A compact, agent-oriented view of the whole tree: the summary counts plus
  /// the full nested node JSON (ids, roles, values, state, actions).
  Map<String, Object?> _describeTree(SemanticInspectionSnapshot snapshot) {
    return <String, Object?>{
      'nodeCount': snapshot.nodeCount,
      'focusedNodeId': snapshot.focusedNodeId,
      'roleCounts': snapshot.roleCounts,
      'root': snapshot.root.toJson(),
    };
  }

  /// A node flattened for find_nodes results — its own fields, no children.
  Map<String, Object?> _flatNode(SemanticInspectionNode node) {
    final json = Map<String, Object?>.of(node.toJson())..remove('children');
    json['childCount'] = node.children.length;
    return json;
  }

  // ---- JSON-RPC framing ----------------------------------------------------

  void _sendMessage(Map<String, Object?> message) => send(jsonEncode(message));

  Map<String, Object?> _resultMessage(Object? id, Object? result) =>
      <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result};

  Map<String, Object?> _errorMessage(Object? id, int code, String message) =>
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{'code': code, 'message': message},
      };

  /// A successful tool result whose single text block is [value] as JSON.
  Map<String, Object?> _toolJson(Object? value) => <String, Object?>{
    'content': <Object?>[
      <String, Object?>{'type': 'text', 'text': jsonEncode(value)},
    ],
    'isError': false,
  };

  /// A tool-domain failure surfaced to the model (not a JSON-RPC error), so it
  /// can read the reason and adjust.
  Map<String, Object?> _toolError(String message) => <String, Object?>{
    'content': <Object?>[
      <String, Object?>{'type': 'text', 'text': message},
    ],
    'isError': true,
  };

  static String? _optString(Object? value) =>
      value is String ? value : null;
}

/// A recoverable tool-domain failure (bad args, missing node, …). Caught in
/// [McpServer._callTool] and returned as an isError result.
final class _ToolFailure implements Exception {
  const _ToolFailure(this.message);
  final String message;
}
