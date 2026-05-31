import 'dart:io';

import 'ansi_renderer.dart';

/// Wraps a Dart [IOSink] (typically `stdout`) as an [AnsiSink].
///
/// This is the only path the framework writes to stdout through on native
/// platforms; widget code never gets a reference to one of these. Kept apart
/// from [AnsiRenderer] so the renderer itself stays free of `dart:io` and can
/// compile to the web.
final class IoSinkAnsiSink implements AnsiSink {
  IoSinkAnsiSink(this._sink);

  final IOSink _sink;

  @override
  void write(String data) => _sink.write(data);

  @override
  Future<void> flush() => _sink.flush();
}
