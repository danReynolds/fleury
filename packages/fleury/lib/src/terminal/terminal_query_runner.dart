import 'dart:async';

import 'input_parser.dart';
import 'terminal_probe.dart';
import 'terminal_response.dart';

/// Serializes terminal queries over the same byte stream as application input.
///
/// The input parser frames terminal replies and sends them here while continuing
/// to deliver ordinary input. A Device Attributes reply terminates each
/// exchange. After a timeout, the response expectation remains installed for a
/// short quarantine so a late reply cannot become a phantom key press.
final class TerminalQueryRunner
    implements TerminalProbeTransport, TerminalResponseSink {
  TerminalQueryRunner({
    required InputParser parser,
    required TuiEventSink inputSink,
    required Future<void> Function(String bytes) write,
    this.lateResponseGrace = const Duration(milliseconds: 250),
    this.maxResponseBytes = 64 * 1024,
  }) : _parser = parser,
       _inputSink = inputSink,
       _write = write,
       assert(maxResponseBytes > 0);

  final InputParser _parser;
  final TuiEventSink _inputSink;
  final Future<void> Function(String bytes) _write;

  /// Maximum time a timed-out exchange continues recognizing its replies.
  final Duration lateResponseGrace;

  /// Round trip measured by the FIRST exchange the terminal actually answered:
  /// the interval between the request leaving for the terminal and its Device
  /// Attributes sentinel arriving back. Null until something answers, and
  /// never overwritten afterwards — one sample is enough to tell a local
  /// terminal from a link with a continent in it.
  ///
  /// Queue and quarantine waits are deliberately outside it: those are time
  /// this runner spent on itself, not time the link took. Startup negotiation
  /// scales its remaining probe deadlines off this value, which is what keeps
  /// a high-latency session (SSH, mosh, a container over a VPN) from timing
  /// every capability out into its conservative default.
  Duration? get measuredRoundTrip => _measuredRoundTrip;
  Duration? _measuredRoundTrip;

  /// Aggregate response bound for one exchange.
  final int maxResponseBytes;

  Future<void> _tail = Future<void>.value();
  _QueryExchange? _active;
  _QueryQuarantine? _quarantine;
  bool _disposed = false;

  @override
  Future<List<int>> request(String bytes, {required Duration timeout}) {
    final elapsed = Stopwatch()..start();
    final previous = _tail;
    final released = Completer<void>();
    final result = Completer<List<int>>();
    final queueTimer = Timer(timeout, () {
      if (!result.isCompleted) {
        result.completeError(
          TimeoutException(
            'Terminal query deadline elapsed before the exchange could start.',
            timeout,
          ),
        );
      }
    });
    _tail = released.future;
    unawaited(() async {
      try {
        // Wait for the actual preceding exchange even if this caller's own
        // deadline expires. Releasing the queue early would let a later query
        // overwrite the still-active parser expectation.
        await previous;
        if (result.isCompleted) return;
        queueTimer.cancel();
        final quarantine = _quarantine;
        if (quarantine != null) {
          final remaining = timeout - elapsed.elapsed;
          if (remaining <= Duration.zero) {
            throw TimeoutException('Terminal query deadline elapsed.', timeout);
          }
          await quarantine.done.future.timeout(
            remaining,
            onTimeout: () => throw TimeoutException(
              'Terminal query deadline elapsed before the exchange could start.',
              timeout,
            ),
          );
        }
        if (_disposed) {
          throw StateError('TerminalQueryRunner is disposed.');
        }
        final remaining = timeout - elapsed.elapsed;
        if (remaining <= Duration.zero) {
          throw TimeoutException('Terminal query deadline elapsed.', timeout);
        }
        final response = await _run(bytes, remaining);
        if (!result.isCompleted) result.complete(response);
      } on Object catch (error, stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      } finally {
        queueTimer.cancel();
        released.complete();
      }
    }());
    return result.future;
  }

  Future<List<int>> _run(String bytes, Duration timeout) {
    final exchange = _QueryExchange(
      expectation: _expectationFor(bytes),
      timeout: timeout,
    );
    _active = exchange;
    _parser.responseExpectation = exchange.expectation;
    exchange.timer = Timer(timeout, () => _timeout(exchange));
    // Do not await the transport before returning [done]: a blocked stdout
    // flush must remain inside the same deadline as a missing terminal reply.
    // Future.sync also captures a synchronous write failure. A failure still
    // owns a short quarantine because a prefix may already have reached the
    // terminal before the transport reported it.
    unawaited(
      Future<void>.sync(() => _write(bytes)).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          _fail(exchange, error, stack);
        },
      ),
    );
    return exchange.done.future;
  }

  @override
  void addTerminalResponse(TerminalResponse response) {
    final active = _active;
    if (active != null) {
      if (!_append(active.bytes, response.raw)) {
        _fail(
          active,
          StateError(
            'Terminal query response exceeded $maxResponseBytes bytes.',
          ),
        );
        return;
      }
      if (response.isDeviceAttributes) _complete(active);
      return;
    }

    final quarantine = _quarantine;
    if (quarantine != null && response.isDeviceAttributes) {
      _finishQuarantine(quarantine);
    }
  }

  void _complete(_QueryExchange exchange) {
    if (!identical(_active, exchange)) return;
    exchange.timer?.cancel();
    _measuredRoundTrip ??= exchange.clock.elapsed;
    _active = null;
    _releaseParser();
    exchange.done.complete(List<int>.unmodifiable(exchange.bytes));
  }

  void _timeout(_QueryExchange exchange) {
    if (!identical(_active, exchange)) return;
    _fail(
      exchange,
      TimeoutException('Terminal query timed out.', exchange.timeout),
    );
  }

  void _fail(_QueryExchange exchange, Object error, [StackTrace? stack]) {
    if (!identical(_active, exchange)) return;
    exchange.timer?.cancel();
    _active = null;
    exchange.done.completeError(error, stack);

    final quarantine = _QueryQuarantine(exchange.expectation);
    _quarantine = quarantine;
    // Keep the ambiguous response forms owned until the late-reply boundary.
    _parser.responseExpectation = quarantine.expectation;
    quarantine.timer = Timer(
      lateResponseGrace,
      () => _finishQuarantine(quarantine, discardIncompleteResponses: true),
    );
  }

  void _finishQuarantine(
    _QueryQuarantine quarantine, {
    bool discardIncompleteResponses = false,
  }) {
    if (!identical(_quarantine, quarantine)) return;
    quarantine.timer?.cancel();
    _quarantine = null;
    _releaseParser(discardIncompleteResponses: discardIncompleteResponses);
    quarantine.done.complete();
  }

  bool _append(List<int> target, List<int> bytes) {
    final remaining = maxResponseBytes - target.length;
    if (remaining < bytes.length) return false;
    target.addAll(bytes);
    return true;
  }

  void _releaseParser({bool discardIncompleteResponses = false}) {
    if (!discardIncompleteResponses) {
      // This may run re-entrantly from InputParser.feed. Changing the
      // expectation is safe and makes bytes after the DA sentinel ordinary
      // input; the state-mutating flush remains deferred below.
      _parser.responseExpectation = TerminalResponseExpectation.none;
    }
    // A response completion can occur inside InputParser.feed. Deferring the
    // flush avoids re-entering that state machine and releases a pending real
    // Escape as soon as parsing the current byte batch has returned.
    scheduleMicrotask(() {
      if (discardIncompleteResponses) {
        _parser.endResponseExpectation(
          _inputSink,
          discardIncompleteResponses: true,
        );
      } else {
        _parser.flush(_inputSink);
      }
    });
  }

  /// Cancels active timers and prevents future queries.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final active = _active;
    if (active != null) {
      active.timer?.cancel();
      _active = null;
      active.done.completeError(
        StateError('TerminalQueryRunner was disposed during a query.'),
      );
    }
    final quarantine = _quarantine;
    if (quarantine != null) {
      quarantine.timer?.cancel();
      _quarantine = null;
      quarantine.done.complete();
    }
    _releaseParser(discardIncompleteResponses: true);
  }
}

TerminalResponseExpectation _expectationFor(String request) {
  return TerminalResponseExpectation(
    privateCsiPrefix: true,
    cursorPosition: request.contains('\x1b[6n'),
    modeReport: request.contains(r'$p'),
    windowOperation: _containsWindowQuery(request),
    operatingSystemCommand: request.contains('\x1b]'),
    deviceControlString: request.contains('\x1bP'),
    applicationProgramCommand: request.contains('\x1b_'),
  );
}

bool _containsWindowQuery(String request) {
  for (final match in RegExp(r'\x1B\[([0-9;]*)t').allMatches(request)) {
    final parameters = match.group(1);
    if (parameters != null && parameters.isNotEmpty) return true;
  }
  return false;
}

final class _QueryExchange {
  _QueryExchange({required this.expectation, required this.timeout});

  final TerminalResponseExpectation expectation;
  final Duration timeout;

  /// Started at construction — which [TerminalQueryRunner._run] does
  /// immediately before arming the deadline and handing the bytes to the
  /// transport, so this measures the terminal's round trip and nothing else.
  final Stopwatch clock = Stopwatch()..start();
  final List<int> bytes = <int>[];
  final Completer<List<int>> done = Completer<List<int>>();
  Timer? timer;
}

final class _QueryQuarantine {
  _QueryQuarantine(this.expectation);

  final TerminalResponseExpectation expectation;
  final Completer<void> done = Completer<void>();
  Timer? timer;
}
