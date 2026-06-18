import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

Future<File> _hostileTempFile(Directory root) async {
  final dir = Directory(
    '${root.path}/dir with spaces and quotes \' ; touch SHOULD_NOT_EXIST ;',
  )..createSync();
  final file = File('${dir.path}/buffer with \$dollar and `ticks`.txt');
  return file;
}

String _quotePosixArgument(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

void main() {
  group('explicit-effect security boundaries', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'fleury_effect_security_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('ProcessTaskCommand does not request a shell unless explicit', () {
      const defaultCommand = ProcessTaskCommand('tool', ['arg']);
      expect(defaultCommand.runInShell, isFalse);

      const shellCommand = ProcessTaskCommand.configured(
        executable: 'tool',
        arguments: ['arg'],
        runInShell: true,
      );
      expect(shellCommand.runInShell, isTrue);
    });

    test(
      'external editor executable command receives hostile path as an argument',
      () async {
        final file = await _hostileTempFile(tempDir);
        ProcessTaskCommand? seen;

        final result = await editTextInExternalEditor(
          initialText: 'draft',
          command: const ExternalEditorCommand.executable('fake-editor', [
            '--wait',
          ]),
          tempFileFactory: (_) async => ExternalEditorTempFile(file: file),
          processRunner: (command) async {
            seen = command;
            await file.writeAsString('edited');
            return 0;
          },
        );

        expect(result.succeeded, isTrue);
        expect(seen?.executable, 'fake-editor');
        expect(seen?.arguments, ['--wait', file.path]);
        expect(seen?.runInShell, isFalse);
      },
    );

    test('environment shell editor quotes the appended file path', () async {
      final file = await _hostileTempFile(tempDir);
      ProcessTaskCommand? seen;

      final result = await editTextInExternalEditor(
        initialText: 'draft',
        environment: const {'VISUAL': 'code --wait'},
        isWindows: false,
        tempFileFactory: (_) async => ExternalEditorTempFile(file: file),
        processRunner: (command) async {
          seen = command;
          await file.writeAsString('edited');
          return 0;
        },
      );

      expect(result.succeeded, isTrue);
      expect(seen?.executable, '/bin/sh');
      expect(seen?.arguments, [
        '-c',
        'code --wait ${_quotePosixArgument(file.path)}',
      ]);
      expect(seen?.runInShell, isFalse);
    });

    test('external editor fileName cannot escape the temp directory', () async {
      await expectLater(
        editTextInExternalEditor(
          fileName: '../escape.txt',
          processRunner: (_) async => 0,
        ),
        throwsArgumentError,
      );

      await expectLater(
        editTextInExternalEditor(
          fileName: r'..\escape.txt',
          processRunner: (_) async => 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
