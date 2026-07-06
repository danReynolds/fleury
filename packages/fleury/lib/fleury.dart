/// Fleury — Flutter ergonomics, terminal truth.
///
/// The native umbrella: the host SPI (`fleury_host.dart`, which itself
/// re-exports the app-facing core `fleury_core.dart`) plus the
/// `dart:io`-backed pieces — native terminal drivers, `runApp`,
/// stray-output capture + the log console. Browser hosts import
/// `fleury_host.dart` and supply their own presentation/input surfaces.
///
/// See `docs/rfcs/0007-fleury-framework.md` for scope and gates.
library;

export 'fleury_host.dart';

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
export 'src/runtime/hot_reload.dart' show HotReloadController;
export 'src/runtime/output_capture.dart' show LogBuffer, LogLine, LogSource;
export 'src/runtime/system_clipboard.dart' show SystemClipboard;
export 'src/debug/debug_state.dart'
    show DebugConfig, DebugMode, DebugPanelSide;
export 'src/runtime/run_app.dart' show ExitRequested, TuiEventHandler, runApp;
export 'src/terminal/native_driver.dart' show createNativeTerminalDriver;
export 'src/terminal/posix_driver.dart' show PosixTerminalDriver;
export 'src/terminal/windows_driver.dart' show WindowsTerminalDriver;
export 'src/widgets/output_capture_view.dart'
    show LogBufferScope, OutputCaptureConsole, OutputCaptureView;
