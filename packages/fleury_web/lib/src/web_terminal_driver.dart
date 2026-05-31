import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:fleury/fleury_core.dart';

/// The xterm.js `Terminal` the host page created and stashed on the global
/// object as `fleuryTerminal`.
@JS('fleuryTerminal')
external _XtermTerminal get _terminal;

extension type _XtermTerminal._(JSObject _) implements JSObject {
  external void write(String data);
  external _Disposable onData(JSFunction handler);
  external _Disposable onResize(JSFunction handler);
  external int get cols;
  external int get rows;
}

extension type _Disposable._(JSObject _) implements JSObject {
  external void dispose();
}

extension type _ResizeDims._(JSObject _) implements JSObject {
  external int get cols;
  external int get rows;
}

/// A [TerminalDriver] backed by an xterm.js terminal in the browser.
///
/// Output goes to `term.write`; keystrokes from `term.onData` are fed through
/// the framework's [InputParser] (so the same VT/CSI parsing as native
/// applies) and surface as [TuiEvent]s; `term.onResize` drives [ResizeEvent].
///
/// Browser-only by nature — like the POSIX driver needs a real TTY, this
/// needs a real xterm.js instance, so it's exercised in a browser rather than
/// the VM test suite. The byte-level work it delegates to [InputParser] is
/// heavily covered there.
class WebTerminalDriver implements TerminalDriver {
  WebTerminalDriver();

  final InputParser _parser = InputParser();
  final StreamController<TuiEvent> _events =
      StreamController<TuiEvent>.broadcast();
  late final _ParserSink _sink = _ParserSink(_events);

  _Disposable? _dataSub;
  _Disposable? _resizeSub;
  bool _active = false;

  @override
  Stream<TuiEvent> get events => _events.stream;

  @override
  CellSize get size => CellSize(_terminal.cols, _terminal.rows);

  @override
  TerminalCapabilities get capabilities =>
      const TerminalCapabilities(colorMode: ColorMode.truecolor);

  @override
  bool get isActive => _active;

  @override
  bool get isInteractive => true;

  @override
  Future<void> enter(TerminalMode mode) async {
    if (_active) {
      throw StateError('WebTerminalDriver.enter called on an active driver.');
    }
    _active = true;
    // xterm delivers each keypress/sequence as one onData string; feed it as
    // UTF-8 bytes and flush immediately (the sequence arrives whole, and a
    // lone Esc should report at once rather than wait for a CSI that the
    // browser won't split across events).
    _dataSub = _terminal.onData(
      ((String data) {
        _parser.feed(utf8.encode(data), _sink);
        _parser.flush(_sink);
      }).toJS,
    );
    _resizeSub = _terminal.onResize(
      ((_ResizeDims dims) {
        _events.add(ResizeEvent(CellSize(dims.cols, dims.rows)));
      }).toJS,
    );
  }

  @override
  Future<void> restore() async {
    _dataSub?.dispose();
    _dataSub = null;
    _resizeSub?.dispose();
    _resizeSub = null;
    _active = false;
  }

  @override
  void write(String data) => _terminal.write(data);
}

class _ParserSink implements TuiEventSink {
  _ParserSink(this._target);
  final StreamController<TuiEvent> _target;
  @override
  void add(TuiEvent event) => _target.add(event);
}
