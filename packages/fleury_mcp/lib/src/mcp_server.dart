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

import 'package:characters/characters.dart';
import 'package:fleury/fleury_core.dart';

import 'app_bridge.dart';
import 'value_schema.dart';

/// MCP protocol revision this server prefers. The handshake echoes the client's
/// requested revision when it is one we support, falling back to this.
const String mcpProtocolVersion = '2025-06-18';

/// Server identity reported in the `initialize` handshake.
const String mcpServerName = 'fleury';
const String mcpServerVersion = '0.1.0';

/// JSON-RPC 2.0 error codes used by this server.
const int _parseError = -32700;
const int _invalidRequest = -32600;
const int _methodNotFound = -32601;
const int _internalError = -32603;

/// MCP-defined: a `resources/read` for a URI this server doesn't expose.
const int _resourceNotFound = -32002;

/// Reads newline-delimited JSON-RPC from [input], dispatches against [bridge],
/// and writes responses to [output]. Returns when [input] closes (the host
/// disconnected) or a write fails (the host's pipe broke).
///
/// Requests are handled concurrently — a slow `tools/call` (which can block in
/// `settle()`) must not delay a following `ping`/cancellation — and responses,
/// matched by id, may complete out of order. Writes are serialized through a
/// single chain so concurrent responses can't interleave a partial line, and a
/// broken-pipe write ends the loop cleanly rather than escaping unhandled.
Future<void> runMcpServer({
  required FleuryAppBridge bridge,
  required Stream<List<int>> input,
  required IOSink output,
}) async {
  final done = Completer<void>();
  var writeFailed = false;
  Future<void> writeChain = Future<void>.value();
  void send(String line) {
    if (writeFailed) return;
    writeChain = writeChain
        .then((_) async {
          output.write('$line\n');
          await output.flush();
        })
        .catchError((Object _) {
          // The host closed the pipe; stop writing and end the loop so the
          // caller can tear the session (and the app subprocess) down.
          writeFailed = true;
          if (!done.isCompleted) done.complete();
        });
  }

  final server = McpServer(bridge: bridge, send: send);
  final lines = input
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  final pending = <Future<void>>[];

  late final StreamSubscription<String> sub;
  sub = lines.listen(
    (line) {
      if (line.trim().isEmpty) return;
      final handled = server.handleLine(line).catchError((Object _) {});
      pending.add(handled);
      handled.whenComplete(() => pending.remove(handled));
    },
    onError: (Object _, StackTrace _) {
      if (!done.isCompleted) done.complete();
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
    cancelOnError: false,
  );

  await done.future;
  await sub.cancel();
  // On a clean shutdown (the host closed stdin), let in-flight handlers finish
  // so their responses flush — bounded, so a wedged tool call can't hang
  // teardown. On a write failure the pipe is already broken, so skip it.
  if (!writeFailed && pending.isNotEmpty) {
    await Future.wait(pending.toList()).timeout(
      const Duration(seconds: 3),
      onTimeout: () => const <void>[],
    );
  }
  await writeChain.catchError((Object _) {});
}

/// The transport-agnostic JSON-RPC core. Feed it raw request lines via
/// [handleLine]; it calls [send] with each response line. Split out from the
/// stdio runner so tests can drive it with in-memory streams.
final class McpServer {
  McpServer({required this.bridge, required this.send});

  final FleuryAppBridge bridge;
  final void Function(String jsonLine) send;

  /// The snapshot most recently handed to the agent (via get_ui / find_nodes /
  /// the resource) — the frame whose ids the agent is holding. invoke_action
  /// compares against it to detect a stale *positional* reference (see
  /// [isPositionalSemanticId] / [_fingerprint]).
  SemanticInspectionSnapshot? _lastServed;

  /// Resource URIs the client has resources/subscribe'd to. While non-empty, a
  /// single push loop coalesces frames and emits notifications/resources/updated.
  final Set<String> _subscriptions = <String>{};

  /// The running push loop's future (null when none). A future handle rather than
  /// a bool so the loop's completion can re-check for a subscription that arrived
  /// during its teardown and restart — no lost re-subscribe.
  Future<void>? _pushLoopFuture;

  /// Serializes mutating tool calls (invoke_action/set_value/type_text/
  /// press_key/resize) so two in-flight mutations can't interleave their
  /// revision/settle bookkeeping — one's frame satisfying the other's
  /// `sinceRevision`, so it returns the wrong "after" snapshot. Reads
  /// (get_ui/find_nodes/ping) and `wait_for_change` stay concurrent: the latter
  /// MUST be able to observe a mutation happening alongside it.
  ///
  /// `null` means idle, in which case the body runs *synchronously* (it is not
  /// deferred behind a microtask), so the common single-call path keeps capturing
  /// `before = bridge.revision` before the next frame lands.
  Future<void>? _mutationTail;

  Future<T> _serializeMutation<T>(Future<T> Function() body) {
    final prior = _mutationTail;
    if (prior == null) {
      final result = body();
      final mine = result.then<void>((_) {}, onError: (Object _) {});
      _mutationTail = mine;
      mine.whenComplete(() {
        if (identical(_mutationTail, mine)) _mutationTail = null;
      });
      return result;
    }
    final completer = Completer<T>();
    final mine = prior.then((_) async {
      try {
        completer.complete(await body());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    _mutationTail = mine;
    mine.whenComplete(() {
      if (identical(_mutationTail, mine)) _mutationTail = null;
    });
    return completer.future;
  }

  static const Set<String> _supportedProtocolVersions = <String>{
    '2025-06-18',
    '2025-03-26',
    '2024-11-05',
  };

  static final Map<String, SemanticAction> _actionsByName = {
    for (final a in SemanticAction.values) a.name: a,
  };
  static final Map<String, KeyCode> _keysByName = {
    for (final k in KeyCode.values) k.name: k,
  };
  static final Set<String> _roleNames = {
    for (final r in SemanticRole.values) r.name,
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
    // A message with no `id` key is a notification — never respond to it (even
    // if it's malformed). A request carries an `id`, which may legitimately be
    // null and must still be echoed in the response.
    if (!decoded.containsKey('id')) return;

    final id = decoded['id'];
    final method = decoded['method'];
    if (method is! String) {
      _sendMessage(_errorMessage(id, _invalidRequest, 'Missing or invalid method'));
      return;
    }
    final params = decoded['params'] is Map
        ? (decoded['params'] as Map).cast<String, Object?>()
        : const <String, Object?>{};

    // Every request must get a response. A handler throw (e.g. an unknown
    // resource URI, or a transport hiccup mid-read) becomes a JSON-RPC error
    // rather than a swallowed, response-less line that would hang the client.
    // tools/call is already internally guarded; this covers the rest.
    try {
      switch (method) {
        case 'initialize':
          _sendMessage(_resultMessage(id, _initializeResult(params)));
        case 'ping':
          _sendMessage(_resultMessage(id, const <String, Object?>{}));
        case 'tools/list':
          _sendMessage(
            _resultMessage(id, <String, Object?>{'tools': _toolDefs}),
          );
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
        case 'resources/subscribe':
          _sendMessage(_resultMessage(id, _subscribeResource(params)));
        case 'resources/unsubscribe':
          _sendMessage(_resultMessage(id, _unsubscribeResource(params)));
        default:
          _sendMessage(
            _errorMessage(id, _methodNotFound, 'Unknown method: $method'),
          );
      }
    } on _RpcError catch (e) {
      _sendMessage(_errorMessage(id, e.code, e.message));
    } catch (error) {
      _sendMessage(
        _errorMessage(id, _internalError, 'Internal error handling $method: $error'),
      );
    }
  }

  // ---- initialize ----------------------------------------------------------

  Map<String, Object?> _initializeResult(Map<String, Object?> params) {
    final requested = params['protocolVersion'];
    final version = requested is String &&
            _supportedProtocolVersions.contains(requested)
        ? requested
        : mcpProtocolVersion;
    return <String, Object?>{
      'protocolVersion': version,
      'capabilities': <String, Object?>{
        'tools': <String, Object?>{},
        // `subscribe`: clients may resources/subscribe to fleury://ui/tree and
        // receive notifications/resources/updated when the UI settles.
        // `listChanged` is omitted — the resource list is static (one resource).
        'resources': <String, Object?>{'subscribe': true},
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
          'SemanticActions. To react to UI changes the app makes on its own, '
          'resources/subscribe to fleury://ui/tree: you will get a '
          'notifications/resources/updated (with the changed/removed node ids) '
          'each time the UI settles, instead of polling.',
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
      throw _RpcError(_resourceNotFound, 'Unknown resource: $uri');
    }
    final snapshot = await _currentSnapshot();
    if (snapshot != null) _lastServed = snapshot;
    final text = snapshot == null ? '{}' : jsonEncode(_cappedUi(snapshot));
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

  // ---- resource subscription (coalesced delta push) ------------------------

  Map<String, Object?> _subscribeResource(Map<String, Object?> params) {
    final uri = params['uri'];
    if (uri != _treeUri) {
      throw _RpcError(_resourceNotFound, 'Unknown resource: $uri');
    }
    _subscriptions.add(uri as String);
    _startPushLoop();
    return const <String, Object?>{};
  }

  Map<String, Object?> _unsubscribeResource(Map<String, Object?> params) {
    _subscriptions.remove(params['uri']);
    // The push loop observes the now-empty set and exits on its next turn.
    return const <String, Object?>{};
  }

  /// Ensures the single coalescing push loop is running. Guarded by a future
  /// handle: when the loop ends, its `whenComplete` re-checks for a subscription
  /// that may have arrived during teardown and restarts — closing the gap where a
  /// re-subscribe between the loop's exit and the handle clearing is dropped.
  void _startPushLoop() {
    if (_pushLoopFuture != null) return;
    bridge.takeDelta(); // reset baseline: only push changes from now on.
    final future = _pushLoop();
    _pushLoopFuture = future;
    unawaited(
      future.whenComplete(() {
        if (!identical(_pushLoopFuture, future)) return;
        _pushLoopFuture = null;
        if (_subscriptions.isNotEmpty && bridge.isRunning) _startPushLoop();
      }),
    );
  }

  /// Emits one coalesced `notifications/resources/updated` per *settled* burst
  /// while a subscriber exists. Reusing [FleuryAppBridge.settle] supplies the
  /// coalescing: a continuously-animating app yields one delta per settle window
  /// (≈ settleCap) instead of a per-frame notification storm, and a quiet app
  /// emits as soon as its burst settles. The long settle timeout lets an idle
  /// subscription sleep on the next frame rather than re-polling every ~2 s.
  Future<void> _pushLoop() async {
    var since = bridge.revision;
    while (_subscriptions.isNotEmpty && bridge.isRunning) {
      try {
        await bridge.settle(
          sinceRevision: since,
          timeout: const Duration(minutes: 5),
        );
      } catch (_) {
        break;
      }
      if (_subscriptions.isEmpty || !bridge.isRunning) break;
      if (bridge.revision == since) continue; // woke with no change — re-arm.
      since = bridge.revision;
      final delta = bridge.takeDelta();
      if (delta.isEmpty) continue;
      try {
        _emitResourceUpdated(delta);
      } catch (_) {
        break; // transport is broken (an injected send threw); stop pushing.
      }
    }
  }

  void _emitResourceUpdated(SemanticTreeDelta delta) {
    // Standard clients act on `uri` (re-read the resource); Fleury-aware clients
    // use the delta to react to only what changed. On a full resync we flag
    // `full` and omit the (whole-tree) id lists.
    _sendMessage(<String, Object?>{
      'jsonrpc': '2.0',
      'method': 'notifications/resources/updated',
      'params': delta.full
          ? <String, Object?>{'uri': _treeUri, 'full': true}
          : <String, Object?>{
              'uri': _treeUri,
              'changedIds': delta.changedIds,
              'removedIds': delta.removedIds,
            },
    });
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
          'role (e.g. "button", "tableRow", "textField"), a case-insensitive '
          'substring of the label, an action the node supports, or '
          'focus/selection state. Returns each match\'s id (use it with '
          'invoke_action), role, label, value, and available actions.',
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
      'name': 'set_value',
      'description':
          'Set a value in one call instead of focus-then-keystrokes. The node '
          'must advertise the `setValue` action. Works on: textField/textArea '
          '(the text), checkbox/toggle (true/false — idempotent, unlike '
          'activate), spinButton/slider (a number), select (an option label or '
          'value, without opening it), datePicker (an ISO date YYYY-MM-DD), and '
          'a table (a 0-based row INDEX — jumps a windowed grid so an '
          'off-screen row scrolls into view, then read it from get_ui). Each '
          'settable node carries a `valueSchema` in get_ui (accepted type + '
          'range/options): pass an in-domain value — an out-of-domain one is '
          'rejected by contract (naming the domain), not silently clamped. The '
          'value is a JSON scalar, coerced for the widget. Returns the UI after '
          'it settles.',
      'inputSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'id': <String, Object?>{
            'type': 'string',
            'description': 'Node id from get_ui / find_nodes.',
          },
          'value': <String, Object?>{
            'type': <String>['string', 'number', 'integer', 'boolean'],
            'description':
                'The value to set; its meaning depends on the node (see the '
                'tool description) — e.g. a row index for a table.',
          },
        },
        'required': <Object?>['id', 'value'],
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
          'Press a key. A named key (enter, tab, escape, backspace, arrowUp, '
          'arrowDown, arrowLeft, arrowRight, home, end, pageUp, pageDown, '
          'delete, f1–f12) drives navigation/activation. A literal character '
          'with no modifiers is typed into the focused input (same as '
          'type_text). Add modifiers (ctrl, alt, shift) to send a chord. Prefer '
          'invoke_action when an equivalent SemanticAction exists. Returns the '
          'UI after it settles.',
      'inputSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'key': <String, Object?>{
            'type': 'string',
            'description': 'A named key (e.g. "enter") or a literal character.',
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
    <String, Object?>{
      'name': 'resize',
      'description':
          "Resize the app's viewport (the terminal grid it lays out against). "
          'The semantic tree only contains what is currently laid out, so grow '
          'the grid to surface more rows of a windowed widget — a long table or '
          'log — that the default 80×24 clips. Returns the UI after it reflows.',
      'inputSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'cols': <String, Object?>{
            'type': 'integer',
            'description': 'Columns (width), at least 1.',
          },
          'rows': <String, Object?>{
            'type': 'integer',
            'description': 'Rows (height), at least 1.',
          },
        },
        'required': <Object?>['cols', 'rows'],
      },
    },
    <String, Object?>{
      'name': 'wait_for_change',
      'description':
          'Block until the UI changes on its own — a ticking dashboard, a '
          'streaming response, a background task finishing — then return the '
          'new tree. Use this to observe asynchronous updates instead of '
          'polling get_ui. Returns as soon as the semantics change, or after '
          'timeout_ms with changed:false if nothing happened.',
      'inputSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'timeout_ms': <String, Object?>{
            'type': 'integer',
            'description':
                'Maximum wait in milliseconds (default 15000, clamped to '
                '100–60000).',
          },
        },
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
          return await _serializeMutation(() => _toolInvokeAction(args));
        case 'set_value':
          return await _serializeMutation(() => _toolSetValue(args));
        case 'type_text':
          return await _serializeMutation(() => _toolTypeText(args));
        case 'press_key':
          return await _serializeMutation(() => _toolPressKey(args));
        case 'resize':
          return await _serializeMutation(() => _toolResize(args));
        case 'wait_for_change':
          return await _toolWaitForChange(args);
        default:
          return _toolError('Unknown tool: $name');
      }
    } on _ToolFailure catch (failure) {
      return _toolError(failure.message);
    } catch (error) {
      // Any other failure (e.g. a transport error mid-action) is surfaced to
      // the model as a tool error, never thrown back through the read loop.
      return _toolError('Internal error handling $name: $error');
    }
  }

  /// Node ceiling for the full-tree `get_ui` / resource payload. Generous for a
  /// real TUI screen (most are well under), but bounds a pathological tree (e.g.
  /// a grid resized huge) so it can't blow the agent's context. Over it, deep
  /// subtrees are dropped with `childrenTruncated` and the agent uses
  /// `find_nodes` to drill in.
  static const int _getUiNodeCap = 800;

  /// Upper bound on a single `type_text` / `set_value` string. Generous (a long
  /// TextArea body fits) but bounds a pathological payload below the wire's
  /// frame cap, with a clear error instead of a silent giant frame.
  static const int _maxInputChars = 200000;

  /// The capped UI JSON with a normalized `valueSchema` injected on every
  /// settable node (WS-9), so an agent reads each node's accepted input type +
  /// constraints alongside it. Shared by get_ui, the resource read, and the
  /// post-action `ui` block.
  Map<String, Object?> _cappedUi(SemanticInspectionSnapshot snapshot) =>
      snapshot.toJsonCapped(
        maxNodes: _getUiNodeCap,
        augment: (node) {
          final schema = deriveValueSchema(node);
          return schema == null
              ? null
              : <String, Object?>{'valueSchema': schema};
        },
      );

  Future<Map<String, Object?>> _toolGetUi() async {
    final snapshot = await _requireSnapshot();
    _lastServed = snapshot;
    return _toolJson(_cappedUi(snapshot));
  }

  Future<Map<String, Object?>> _toolFindNodes(Map<String, Object?> args) async {
    // Validate the enum-valued filters up front: a typo'd role/action would
    // otherwise silently match nothing, and the agent could wrongly conclude
    // "no such nodes" rather than "I mistyped the name".
    final role = _optString(args['role']);
    if (role != null && !_roleNames.contains(role)) {
      throw _ToolFailure(
        'Unknown role "$role". Role names are camelCase (e.g. button, tableRow, '
        'textField); omit role or call get_ui to see the roles in this UI.',
      );
    }
    final action = _optString(args['action']);
    if (action != null && !_actionsByName.containsKey(action)) {
      throw _ToolFailure(
        'Unknown action "$action". Valid actions: $_actionNames.',
      );
    }
    final snapshot = await _requireSnapshot();
    _lastServed = snapshot;
    final matches = snapshot
        .where(
          role: role,
          labelContains: _optString(args['label']),
          action: action,
          focused: args['focused'] is bool ? args['focused'] as bool : null,
          selected: args['selected'] is bool ? args['selected'] as bool : null,
        )
        .toList(growable: false);

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
    await _resolveActionableNode(id, actionName);

    final before = bridge.revision;
    bridge.invokeAction(SemanticNodeId(id), action);
    final after = await bridge.settle(sinceRevision: before);
    final changed = bridge.revision != before;
    return _toolJson(<String, Object?>{
      'invoked': <String, Object?>{'id': id, 'action': actionName},
      'changed': changed,
      if (!changed)
        'note':
            'No semantic change observed. If "$id" was an auto-generated id '
            '(element-…) it is snapshot-local and may be stale — re-read get_ui '
            'and retry.',
      'ui': _uiResult(after),
    });
  }

  /// Resolves [id] to the single live node that advertises [requiredAction],
  /// running the checks invoke_action and set_value share: not-found, ambiguity,
  /// advertise, and the positional stale-reference guard. Throws [_ToolFailure]
  /// on any of them.
  Future<SemanticInspectionNode> _resolveActionableNode(
    String id,
    String requiredAction,
  ) async {
    // Capture the agent-held baseline up front: a concurrent get_ui/find_nodes
    // can reassign _lastServed across the awaits below, which would compare the
    // stale-reference guard against a frame the agent never saw.
    final lastServed = _lastServed;
    final snapshot = await _requireSnapshot();
    final matches = snapshot.where(id: id).toList(growable: false);
    if (matches.isEmpty) {
      throw _ToolFailure(
        'No node with id "$id" in the current UI. Call get_ui or find_nodes for '
        'current ids (auto-generated ids are snapshot-local and change as the UI '
        'rebuilds).',
      );
    }
    if (matches.length > 1) {
      throw _ToolFailure(
        'id "$id" is ambiguous — ${matches.length} nodes share it. Target a node '
        'with an app-assigned stable Semantics(id:), or use find_nodes to '
        'disambiguate by role/label.',
      );
    }
    final node = matches.single;
    if (!node.actions.contains(requiredAction)) {
      throw _ToolFailure(
        'Node "$id" (${_describeNode(node)}) does not advertise '
        '"$requiredAction". It supports: '
        '${node.actions.isEmpty ? '(none)' : node.actions.join(', ')}.',
      );
    }

    // Stale-reference guard. A positional/auto id (`element-…`) can come to
    // denote a *different* logical node after the tree shifts (an unkeyed list
    // recycles element slots). If the node now at this id no longer matches what
    // the agent last read, fail safely instead of driving the wrong node — the
    // silent mis-target the code review flagged. Stable ids (explicit, key:…,
    // contributor-assigned) track their logical node, so they're exempt: a
    // legitimate label change on a stable id must not falsely fire.
    if (isPositionalSemanticId(id)) {
      final observed = lastServed?.nodeById(id);
      if (observed != null && _fingerprint(observed) != _fingerprint(node)) {
        throw _ToolFailure(
          'Stale reference: id "$id" now denotes a different node '
          '(${_describeNode(observed)} → ${_describeNode(node)}). The UI changed '
          'since you read it — re-read get_ui and retry. (Auto-generated ids are '
          'positional; prefer an app-assigned Semantics(id:).)',
        );
      }
    }
    return node;
  }

  Future<Map<String, Object?>> _toolSetValue(Map<String, Object?> args) async {
    final id = _optString(args['id']);
    if (id == null || id.isEmpty) {
      throw const _ToolFailure('set_value requires a node "id".');
    }
    if (!args.containsKey('value')) {
      throw const _ToolFailure(
        'set_value requires a "value" (string, number, or boolean).',
      );
    }
    final value = args['value'];
    if (value is String && value.length > _maxInputChars) {
      throw _ToolFailure(
        'set_value "value" is too long (${value.length} chars; max '
        '$_maxInputChars).',
      );
    }
    final node = await _resolveActionableNode(id, SemanticAction.setValue.name);

    // Validate against the node's typed affordance BEFORE dispatch (WS-9): an
    // out-of-domain value would otherwise be silently clamped/ignored by the
    // widget. Fail by contract, naming the accepted domain so the agent can fix
    // it without trial-and-error.
    final schema = deriveValueSchema(node);
    if (schema != null) {
      final reason = validateValueForSchema(schema, value);
      if (reason != null) {
        throw _ToolFailure(
          'set_value rejected for ${_describeNode(node)}: $reason. '
          'Accepted input — valueSchema: ${jsonEncode(schema)}.',
        );
      }
    }

    final before = bridge.revision;
    bridge.setValue(SemanticNodeId(id), value);
    final after = await bridge.settle(sinceRevision: before);
    return _toolJson(<String, Object?>{
      'set': <String, Object?>{'id': id, 'value': value},
      'changed': bridge.revision != before,
      'ui': _uiResult(after),
    });
  }

  /// A stable proxy for "is this the same logical node", compared between the
  /// frame the agent last read and the live node now at a positional id.
  ///
  /// Includes only fields that stay fixed while a node merely *updates in place*
  /// — role, label, and the sorted action set — so a positional id that has come
  /// to denote a different node is caught without false-flagging a node that is
  /// just changing. It deliberately excludes:
  ///   • `value` / mutable state — a node whose value ticks between the agent's
  ///     read and its action would false-flag every time, livelocking an agent on
  ///     a live UI (the broad false-positive the global structure generation
  ///     suffered, in miniature);
  ///   • `children.length` — which *looks* invariant but is NOT for a
  ///     virtualized/windowed container (a `DataTable`, log, or long list): its
  ///     visible-child count changes every frame as rows stream in or the window
  ///     reflows, so including it would livelock an agent acting on exactly the
  ///     containers it most often targets.
  /// (`actions` changing is safe by contrast: it shifts only on a discrete state
  /// transition — a one-time re-read, not every frame — so it can't livelock; and
  /// a *dropped* target action is already caught earlier by the advertise check.)
  ///
  /// Two nodes identical across role+label+actions but differing only in value
  /// are interchangeable here — a positional swap between them is the accepted
  /// residual gap; durably targeting a specific one needs a stable
  /// `Semantics(id:)`.
  static String _fingerprint(SemanticInspectionNode node) {
    final actions = node.actions.toList()..sort();
    return <String>[
      node.role,
      node.label ?? '',
      actions.join(','),
    ].join('\u0000');
  }

  static String _describeNode(SemanticInspectionNode node) =>
      node.label == null ? node.role : '${node.role} "${node.label}"';

  Future<Map<String, Object?>> _toolTypeText(Map<String, Object?> args) async {
    final text = _optString(args['text']);
    if (text == null) {
      throw const _ToolFailure('type_text requires "text".');
    }
    if (text.length > _maxInputChars) {
      throw _ToolFailure(
        'type_text "text" is too long (${text.length} chars; max '
        '$_maxInputChars). Send it in smaller chunks.',
      );
    }
    if (text.isEmpty) {
      return _toolJson(<String, Object?>{
        'typed': '',
        'changed': false,
        'note': 'Empty text ignored.',
      });
    }
    final before = bridge.revision;
    bridge.typeText(text);
    final after = await bridge.settle(sinceRevision: before);
    return _toolJson(<String, Object?>{
      'typed': text,
      'changed': bridge.revision != before,
      'ui': _uiResult(after),
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
    final before = bridge.revision;
    if (keyCode != null) {
      bridge.pressKey(keyCode: keyCode, modifiers: modifiers);
    } else if (modifiers.isNotEmpty) {
      // A literal character held with modifiers — a chord (e.g. ctrl+a).
      bridge.pressKey(char: key, modifiers: modifiers);
    } else if (key.characters.length == 1) {
      // A bare printable character (one grapheme cluster — counts an emoji or
      // accented letter as one): a plain KeyEvent(char:) does NOT insert text
      // (only a TextInputEvent does), so type it — that's what "press the 'a'
      // key" into a focused field means.
      bridge.typeText(key);
    } else {
      // A multi-character value that is neither a known key name nor a chord is
      // almost certainly a mistyped key (e.g. "esc"/"return" for
      // "escape"/"enter"). Reject it rather than silently typing the literal
      // word — use type_text for literal text input.
      throw _ToolFailure(
        'press_key got unknown key "$key". Use a known key name '
        '(e.g. escape, enter, tab, arrowUp) or type_text for literal text.',
      );
    }
    final after = await bridge.settle(sinceRevision: before);
    return _toolJson(<String, Object?>{
      'pressed': <String, Object?>{
        'key': key,
        if (modifiers.isNotEmpty)
          'modifiers': <Object?>[for (final m in modifiers) m.name],
      },
      'changed': bridge.revision != before,
      'ui': _uiResult(after),
    });
  }

  Future<Map<String, Object?>> _toolResize(Map<String, Object?> args) async {
    final cols = _optInt(args['cols']);
    final rows = _optInt(args['rows']);
    if (cols == null || cols < 1 || rows == null || rows < 1) {
      throw const _ToolFailure(
        'resize requires positive integer "cols" and "rows".',
      );
    }
    final before = bridge.revision;
    bridge.resize(CellSize(cols, rows));
    final after = await bridge.settle(sinceRevision: before);
    return _toolJson(<String, Object?>{
      'resized': <String, Object?>{'cols': cols, 'rows': rows},
      'changed': bridge.revision != before,
      'ui': _uiResult(after),
    });
  }

  Future<Map<String, Object?>> _toolWaitForChange(
    Map<String, Object?> args,
  ) async {
    final timeoutMs = (_optInt(args['timeout_ms']) ?? 15000).clamp(100, 60000);
    await _requireSnapshot(); // ensure the app has rendered at least once.
    final before = bridge.revision;
    final after = await bridge.settle(
      sinceRevision: before,
      timeout: Duration(milliseconds: timeoutMs),
    );
    final changed = bridge.revision != before;
    // On a timeout the tree is unchanged from the agent's last read, so echoing
    // it back is pure wasted tokens — return just the verdict.
    return _toolJson(<String, Object?>{
      'changed': changed,
      if (!changed)
        'note': 'No change within ${timeoutMs}ms; the UI is as you last read it.'
      else
        'ui': _uiResult(after),
    });
  }

  // ---- snapshot helpers ----------------------------------------------------

  /// The latest snapshot, waiting briefly for the app's first frame if it
  /// hasn't rendered yet. Returns null if the app never rendered (the bridge's
  /// first-frame watchdog fired) or the wait times out.
  Future<SemanticInspectionSnapshot?> _currentSnapshot() async {
    if (bridge.snapshot != null) return bridge.snapshot;
    if (bridge.renderTimedOut) return null;
    try {
      await bridge.ready.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      return null;
    }
    return bridge.snapshot;
  }

  Future<SemanticInspectionSnapshot> _requireSnapshot() async {
    final snapshot = await _currentSnapshot();
    if (snapshot == null) {
      throw _ToolFailure(
        bridge.renderTimedOut
            ? 'The app connected but never rendered a UI (no semantic frame '
                  'within the first-frame timeout). Does it call runTui(...)?'
            : 'The app has not rendered a UI yet (no semantic frame received).',
      );
    }
    return snapshot;
  }

  /// Serializes the post-action tree the SAME way get_ui does — node-capped and
  /// token-trimmed — so an action on a large screen can't return the full
  /// uncapped tree and blow the agent's context. It also records the tree as the
  /// one the agent has now seen, so the positional stale-reference guard
  /// compares the agent's NEXT id against this fresh tree, not the stale one from
  /// the last get_ui (which would false-positive after the action mutated a
  /// node's label). Returns null when the app produced no snapshot.
  Object? _uiResult(SemanticInspectionSnapshot? after) {
    if (after == null) return null;
    _lastServed = after;
    return _cappedUi(after);
  }

  /// A node flattened for find_nodes results — its own fields, no children
  /// (built directly, so a deep match doesn't serialize its whole subtree).
  Map<String, Object?> _flatNode(SemanticInspectionNode node) => <String, Object?>{
    // Shares the node's own scalar serializer with get_ui so the two can't drift
    // (a new semantic field shows up in both). find_nodes lists matches flat, so
    // it appends a childCount instead of nesting children.
    ...node.toScalarJson(),
    'childCount': node.children.length,
  };

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

  /// A successful tool result. The JSON [value] is returned as a text block (the
  /// model-facing channel, and the back-compat path for pre-2025-06-18 clients)
  /// and, when it's an object, also as `structuredContent` for clients that
  /// consume tool output programmatically (MCP 2025-06-18). Both carry the same
  /// data; a spec-compliant client feeds the text to the model and uses
  /// structuredContent for app logic, so this doesn't double the model's tokens.
  Map<String, Object?> _toolJson(Object? value) => <String, Object?>{
    'content': <Object?>[
      <String, Object?>{'type': 'text', 'text': jsonEncode(value)},
    ],
    if (value is Map<String, Object?>) 'structuredContent': value,
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

  static String? _optString(Object? value) => value is String ? value : null;

  // Accepts a JSON integer, or a whole-valued double (some clients encode
  // integer arguments as `80.0`); rejects fractional or non-numeric values.
  static int? _optInt(Object? value) {
    if (value is int) return value;
    if (value is double && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return null;
  }
}

/// A JSON-RPC-level failure (bad URI, malformed request) that [handleLine]
/// turns into an error *response* with [code]. Distinct from [_ToolFailure],
/// which is an in-band `isError` tool result the model reads and reacts to.
final class _RpcError implements Exception {
  const _RpcError(this.code, this.message);
  final int code;
  final String message;
}

/// A recoverable tool-domain failure (bad args, missing node, …). Caught in
/// [McpServer._callTool] and returned as an isError result.
final class _ToolFailure implements Exception {
  const _ToolFailure(this.message);
  final String message;
}
