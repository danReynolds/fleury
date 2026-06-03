import 'dart:convert' show Encoding, utf8;
import 'dart:io' show Directory, File, Platform, Process, ProcessStartMode;

import '../terminal/terminal_driver.dart';
import 'process_task.dart';

/// Where an external editor command was resolved from.
enum ExternalEditorCommandSource {
  explicit,
  visualEnvironment,
  editorEnvironment,
  fallback,
}

/// Editor command metadata before the target file path is appended.
final class ExternalEditorCommand {
  const ExternalEditorCommand.executable(
    this.executable, [
    this.arguments = const <String>[],
  ]) : shellCommand = null;

  const ExternalEditorCommand.shell(this.shellCommand)
    : executable = null,
      arguments = const <String>[];

  final String? executable;
  final List<String> arguments;
  final String? shellCommand;

  bool get usesShell => shellCommand != null;

  String get displayName {
    if (shellCommand != null) return shellCommand!;
    if (arguments.isEmpty) return executable!;
    return '$executable ${arguments.join(' ')}';
  }
}

/// A resolved editor command and the policy source that selected it.
final class ExternalEditorResolvedCommand {
  const ExternalEditorResolvedCommand({
    required this.command,
    required this.source,
  });

  final ExternalEditorCommand command;
  final ExternalEditorCommandSource source;
}

/// Temporary file allocated for an external editor session.
final class ExternalEditorTempFile {
  const ExternalEditorTempFile({required this.file, this.cleanup});

  final File file;
  final Future<void> Function()? cleanup;
}

/// Request metadata for creating an external editor temp file.
final class ExternalEditorTempFileRequest {
  const ExternalEditorTempFileRequest({
    required this.fileName,
    required this.fileExtension,
  });

  final String fileName;
  final String fileExtension;
}

/// Result from a completed external editor session.
final class ExternalEditorResult {
  const ExternalEditorResult({
    required this.initialText,
    required this.editedText,
    required this.exitCode,
    required this.filePath,
    required this.editorCommand,
    required this.processCommand,
    required this.commandSource,
  });

  final String initialText;
  final String editedText;
  final int exitCode;
  final String filePath;
  final ExternalEditorCommand editorCommand;
  final ProcessTaskCommand processCommand;
  final ExternalEditorCommandSource commandSource;

  bool get succeeded => exitCode == 0;
  bool get changed => initialText != editedText;
}

/// Raised when an external editor exits non-zero and the caller requested
/// failure-as-exception behavior.
final class ExternalEditorException implements Exception {
  const ExternalEditorException(this.result);

  final ExternalEditorResult result;

  @override
  String toString() {
    return 'External editor `${result.processCommand.displayName}` exited '
        'with code ${result.exitCode}.';
  }
}

typedef ExternalEditorProcessRunner =
    Future<int> Function(ProcessTaskCommand command);
typedef ExternalEditorTempFileFactory =
    Future<ExternalEditorTempFile> Function(
      ExternalEditorTempFileRequest request,
    );

/// Resolves an external editor from an explicit command, `$VISUAL`, `$EDITOR`,
/// or a conservative platform fallback.
ExternalEditorResolvedCommand resolveExternalEditorCommand({
  ExternalEditorCommand? command,
  Map<String, String>? environment,
  bool? isWindows,
}) {
  if (command != null) {
    return ExternalEditorResolvedCommand(
      command: command,
      source: ExternalEditorCommandSource.explicit,
    );
  }

  final env = environment ?? Platform.environment;
  final visual = _trimNonEmpty(env['VISUAL']);
  if (visual != null) {
    return ExternalEditorResolvedCommand(
      command: ExternalEditorCommand.shell(visual),
      source: ExternalEditorCommandSource.visualEnvironment,
    );
  }

  final editor = _trimNonEmpty(env['EDITOR']);
  if (editor != null) {
    return ExternalEditorResolvedCommand(
      command: ExternalEditorCommand.shell(editor),
      source: ExternalEditorCommandSource.editorEnvironment,
    );
  }

  final windows = isWindows ?? Platform.isWindows;
  return ExternalEditorResolvedCommand(
    command: ExternalEditorCommand.executable(windows ? 'notepad' : 'vi'),
    source: ExternalEditorCommandSource.fallback,
  );
}

/// Opens [initialText] in the user's external editor and returns the edited
/// text after the editor exits.
///
/// When [terminalDriver] supports [TerminalHandoffDriver], the TUI terminal is
/// restored for the duration of the editor process and resumed afterward.
Future<ExternalEditorResult> editTextInExternalEditor({
  String initialText = '',
  TerminalDriver? terminalDriver,
  ExternalEditorCommand? command,
  Map<String, String>? environment,
  bool? isWindows,
  String? fileName,
  String fileExtension = '.txt',
  String? workingDirectory,
  Encoding encoding = utf8,
  bool deleteTempFile = true,
  bool failOnNonZeroExit = true,
  ExternalEditorProcessRunner? processRunner,
  ExternalEditorTempFileFactory? tempFileFactory,
}) async {
  final extension = _normalizeFileExtension(fileExtension);
  final normalizedFileName = _normalizeFileName(fileName, extension);
  final tempFile = await (tempFileFactory ?? _createSystemTempFile)(
    ExternalEditorTempFileRequest(
      fileName: normalizedFileName,
      fileExtension: extension,
    ),
  );
  final file = tempFile.file;

  try {
    await file.writeAsString(initialText, encoding: encoding);

    final resolved = resolveExternalEditorCommand(
      command: command,
      environment: environment,
      isWindows: isWindows,
    );
    final processCommand = _toProcessCommand(
      resolved.command,
      file.path,
      environment: environment,
      isWindows: isWindows,
      workingDirectory: workingDirectory,
    );
    final runner = processRunner ?? _runExternalEditorProcess;

    Future<int> runEditor() => runner(processCommand);
    final exitCode = terminalDriver == null
        ? await runEditor()
        : await withTerminalHandoff(terminalDriver, runEditor);
    final editedText = await file.readAsString(encoding: encoding);
    final result = ExternalEditorResult(
      initialText: initialText,
      editedText: editedText,
      exitCode: exitCode,
      filePath: file.path,
      editorCommand: resolved.command,
      processCommand: processCommand,
      commandSource: resolved.source,
    );
    if (failOnNonZeroExit && exitCode != 0) {
      throw ExternalEditorException(result);
    }
    return result;
  } finally {
    if (deleteTempFile) {
      final cleanup = tempFile.cleanup;
      if (cleanup != null) {
        await cleanup();
      } else if (await file.exists()) {
        await file.delete();
      }
    }
  }
}

ProcessTaskCommand _toProcessCommand(
  ExternalEditorCommand command,
  String filePath, {
  required Map<String, String>? environment,
  required bool? isWindows,
  required String? workingDirectory,
}) {
  final windows = isWindows ?? Platform.isWindows;
  if (command.shellCommand case final shellCommand?) {
    if (windows) {
      return ProcessTaskCommand.configured(
        executable: 'cmd',
        arguments: ['/c', '$shellCommand ${_quoteWindowsArgument(filePath)}'],
        workingDirectory: workingDirectory,
        environment: environment,
      );
    }
    return ProcessTaskCommand.configured(
      executable: '/bin/sh',
      arguments: ['-c', '$shellCommand ${_quotePosixArgument(filePath)}'],
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }

  return ProcessTaskCommand.configured(
    executable: command.executable!,
    arguments: [...command.arguments, filePath],
    workingDirectory: workingDirectory,
    environment: environment,
  );
}

Future<int> _runExternalEditorProcess(ProcessTaskCommand command) async {
  final process = await Process.start(
    command.executable,
    command.arguments,
    workingDirectory: command.workingDirectory,
    environment: command.environment,
    includeParentEnvironment: command.includeParentEnvironment,
    runInShell: command.runInShell,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

Future<ExternalEditorTempFile> _createSystemTempFile(
  ExternalEditorTempFileRequest request,
) async {
  final directory = await Directory.systemTemp.createTemp('fleury_editor_');
  final file = File(
    '${directory.path}${Platform.pathSeparator}${request.fileName}',
  );
  return ExternalEditorTempFile(
    file: file,
    cleanup: () async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    },
  );
}

String _normalizeFileName(String? fileName, String extension) {
  final value = _trimNonEmpty(fileName);
  if (value == null) return 'buffer$extension';
  if (value.contains('/') || value.contains(r'\')) {
    throw ArgumentError.value(
      fileName,
      'fileName',
      'must be a file name, not a path',
    );
  }
  return value;
}

String _normalizeFileExtension(String extension) {
  final trimmed = extension.trim();
  if (trimmed.isEmpty) return '.txt';
  return trimmed.startsWith('.') ? trimmed : '.$trimmed';
}

String? _trimNonEmpty(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

String _quotePosixArgument(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

String _quoteWindowsArgument(String value) {
  return '"${value.replaceAll('"', '""')}"';
}
