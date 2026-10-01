/// Fleury — Flutter ergonomics, terminal truth.
///
/// The native umbrella: the host SPI (`fleury_host.dart`, which itself
/// re-exports the app-facing core `fleury_core.dart`) plus the
/// `dart:io`-backed pieces — native terminal drivers, `runApp`, and
/// stray-output capture. Browser hosts import `fleury_host.dart` and supply
/// their own presentation/input surfaces.
///
/// See `docs/rfcs/0007-fleury-framework.md` for scope and gates.
library;

export 'fleury_host.dart';

// Native (dart:io) surface.
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
        ExternalEditorProcessRequest,
        resolveExternalEditorCommand;
export 'src/rendering/io_sink_ansi_sink.dart' show IoSinkAnsiSink;
export 'src/runtime/hot_reload.dart' show HotReloadController;
export 'src/runtime/system_clipboard.dart' show SystemClipboard;
export 'src/debug/debug_state.dart' show DebugConfig, DebugMode, DebugPanelSide;
export 'src/runtime/run_app.dart'
    show
        AppExit,
        EventHandled,
        EventResponse,
        ExitRequested,
        TuiEventHandler,
        exitApp,
        runApp;
export 'src/terminal/native_driver.dart' show createNativeTerminalDriver;
export 'src/terminal/posix_driver.dart' show PosixTerminalDriver;
export 'src/terminal/windows_driver.dart' show WindowsTerminalDriver;

// Native filesystem source for the bundled catalog.
export 'src/catalog/local_file_source.dart' show LocalFileSource;
