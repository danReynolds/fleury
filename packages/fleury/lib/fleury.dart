/// Fleury — Flutter ergonomics, terminal truth.
///
/// The native umbrella: the platform-agnostic core (`fleury_core.dart`)
/// plus the `dart:io`-backed pieces — native terminal drivers, `runTui`,
/// stray-output capture + the log console. Browser hosts import
/// `fleury_core.dart` and supply their own `TerminalDriver`.
///
/// See `docs/rfcs/0007-fleury-framework.md` for scope and gates.
library;

export 'fleury_core.dart';

// Native (dart:io) surface.
export 'src/effects/process_task.dart'
    show
        ProcessTaskCommand,
        ProcessTaskController,
        ProcessTaskException,
        ProcessTaskResult;
export 'src/effects/process_command_runner.dart'
    show ProcessCommandRunner, ProcessCommandScope;
export 'src/effects/external_editor.dart'
    show
        editTextInExternalEditor,
        ExternalEditorCommand,
        ExternalEditorCommandSource,
        ExternalEditorException,
        ExternalEditorResolvedCommand,
        ExternalEditorResult,
        ExternalEditorTempFile,
        ExternalEditorTempFileFactory,
        ExternalEditorTempFileRequest,
        ExternalEditorProcessRunner,
        resolveExternalEditorCommand;
export 'src/rendering/io_sink_ansi_sink.dart' show IoSinkAnsiSink;
export 'src/runtime/output_capture.dart' show LogBuffer, LogLine, LogSource;
export 'src/runtime/run_tui.dart' show ExitRequested, TuiEventHandler, runTui;
export 'src/terminal/native_driver.dart' show createNativeTerminalDriver;
export 'src/terminal/posix_driver.dart' show PosixTerminalDriver;
export 'src/terminal/windows_driver.dart' show WindowsTerminalDriver;
export 'src/widgets/log_view.dart' show LogBufferScope, LogConsole, LogView;
