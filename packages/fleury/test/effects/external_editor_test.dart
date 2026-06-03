import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('External editor', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'fleury_external_editor_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('resolves explicit, environment, and fallback commands', () {
      final explicit = resolveExternalEditorCommand(
        command: const ExternalEditorCommand.executable('micro', ['--wait']),
        environment: const {},
      );
      expect(explicit.source, ExternalEditorCommandSource.explicit);
      expect(explicit.command.displayName, 'micro --wait');

      final visual = resolveExternalEditorCommand(
        environment: const {'VISUAL': ' code --wait ', 'EDITOR': 'vim'},
        isWindows: false,
      );
      expect(visual.source, ExternalEditorCommandSource.visualEnvironment);
      expect(visual.command.usesShell, isTrue);
      expect(visual.command.displayName, 'code --wait');

      final editor = resolveExternalEditorCommand(
        environment: const {'VISUAL': '   ', 'EDITOR': 'nano -w'},
        isWindows: false,
      );
      expect(editor.source, ExternalEditorCommandSource.editorEnvironment);
      expect(editor.command.displayName, 'nano -w');

      final posixFallback = resolveExternalEditorCommand(
        environment: const {},
        isWindows: false,
      );
      expect(posixFallback.source, ExternalEditorCommandSource.fallback);
      expect(posixFallback.command.displayName, 'vi');

      final windowsFallback = resolveExternalEditorCommand(
        environment: const {},
        isWindows: true,
      );
      expect(windowsFallback.command.displayName, 'notepad');
    });

    test(
      'edits text through terminal handoff and returns change metadata',
      () async {
        final driver = FakeTerminalDriver();
        await driver.enter(TerminalMode.interactive);
        final file = File('${tempDir.path}/message.md');
        var cleaned = false;
        ProcessTaskCommand? seenCommand;

        final result = await editTextInExternalEditor(
          initialText: 'before',
          terminalDriver: driver,
          command: const ExternalEditorCommand.executable('fake-editor', [
            '--wait',
          ]),
          fileName: 'message.md',
          fileExtension: 'md',
          tempFileFactory: (request) async {
            expect(request.fileName, 'message.md');
            expect(request.fileExtension, '.md');
            return ExternalEditorTempFile(
              file: file,
              cleanup: () async {
                cleaned = true;
                if (await file.exists()) await file.delete();
              },
            );
          },
          processRunner: (command) async {
            seenCommand = command;
            expect(await file.readAsString(), 'before');
            await file.writeAsString('after');
            return 0;
          },
        );

        expect(result.succeeded, isTrue);
        expect(result.changed, isTrue);
        expect(result.initialText, 'before');
        expect(result.editedText, 'after');
        expect(result.filePath, file.path);
        expect(result.commandSource, ExternalEditorCommandSource.explicit);
        expect(seenCommand?.executable, 'fake-editor');
        expect(seenCommand?.arguments, ['--wait', file.path]);
        expect(cleaned, isTrue);
        expect(await file.exists(), isFalse);
        expect(driver.handoffCallCount, 1);
        expect(driver.handoffSuspendCallCount, 1);
        expect(driver.handoffResumeCallCount, 1);
        expect(driver.isActive, isTrue);

        await driver.dispose();
      },
    );

    test(
      'runs environment editor commands through the platform shell',
      () async {
        final file = File('${tempDir.path}/buffer.txt');
        ProcessTaskCommand? seenCommand;

        final result = await editTextInExternalEditor(
          initialText: 'draft',
          environment: const {'VISUAL': 'code --wait'},
          isWindows: false,
          tempFileFactory: (_) async {
            return ExternalEditorTempFile(
              file: file,
              cleanup: () async {
                if (await file.exists()) await file.delete();
              },
            );
          },
          processRunner: (command) async {
            seenCommand = command;
            await file.writeAsString('published');
            return 0;
          },
        );

        expect(
          result.commandSource,
          ExternalEditorCommandSource.visualEnvironment,
        );
        expect(result.editedText, 'published');
        expect(seenCommand?.executable, '/bin/sh');
        expect(seenCommand?.arguments.first, '-c');
        expect(seenCommand?.arguments.last, contains('code --wait '));
        expect(seenCommand?.arguments.last, contains(file.path));
      },
    );

    test(
      'throws on non-zero editor exit with edited result metadata',
      () async {
        final file = File('${tempDir.path}/buffer.txt');
        var cleaned = false;

        await expectLater(
          editTextInExternalEditor(
            initialText: 'before',
            command: const ExternalEditorCommand.executable('bad-editor'),
            tempFileFactory: (_) async {
              return ExternalEditorTempFile(
                file: file,
                cleanup: () async {
                  cleaned = true;
                  if (await file.exists()) await file.delete();
                },
              );
            },
            processRunner: (_) async {
              await file.writeAsString('partial');
              return 2;
            },
          ),
          throwsA(
            isA<ExternalEditorException>()
                .having((error) => error.result.exitCode, 'exitCode', 2)
                .having(
                  (error) => error.result.editedText,
                  'editedText',
                  'partial',
                ),
          ),
        );

        expect(cleaned, isTrue);
        expect(await file.exists(), isFalse);
      },
    );
  });
}
