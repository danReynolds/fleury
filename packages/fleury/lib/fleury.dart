/// Fleury — Flutter ergonomics, terminal truth.
///
/// The native umbrella: the platform-agnostic core (`fleury_core.dart`)
/// plus the `dart:io`-backed pieces — the POSIX terminal driver, `runTui`,
/// stray-output capture + the log console. Browser hosts import
/// `fleury_core.dart` and supply their own `TerminalDriver`.
///
/// See `docs/rfcs/0007-fleury-framework.md` for scope and gates.
library;

export 'fleury_core.dart';

// Native (dart:io) surface.
export 'src/rendering/io_sink_ansi_sink.dart' show IoSinkAnsiSink;
export 'src/runtime/output_capture.dart' show LogBuffer, LogLine, LogSource;
export 'src/runtime/run_tui.dart' show ExitRequested, TuiEventHandler, runTui;
export 'src/terminal/posix_driver.dart' show PosixTerminalDriver;
export 'src/widgets/log_view.dart' show LogBufferScope, LogConsole, LogView;
