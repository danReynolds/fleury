import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

MemoryFileSource _project() => MemoryFileSource(
  [
    '/app/lib/main.dart',
    '/app/lib/src/widgets.dart',
    '/app/README.md',
    '/app/.env',
    '/app/build/',
  ],
  sizes: {'/app/README.md': 1200},
);

List<String> _names(List<FileEntry> entries) =>
    [for (final entry in entries) entry.name]..sort();

void main() {
  group('MemoryFileSource', () {
    test('lists implicit parents, files, and empty directories', () {
      final source = _project();

      expect(_names(source.list('/')), ['app']);
      expect(_names(source.list('/app')), [
        '.env',
        'README.md',
        'build',
        'lib',
      ]);
      expect(source.list('/app/build'), isEmpty);

      final entries = {for (final e in source.list('/app')) e.name: e};
      expect(entries['lib']!.type, FileEntryType.directory);
      expect(entries['build']!.isDirectory, isTrue);
      expect(entries['README.md']!.isFile, isTrue);
      expect(entries['README.md']!.path, '/app/README.md');
      expect(entries['README.md']!.sizeBytes, 1200);
      expect(entries['.env']!.hidden, isTrue);
      expect(entries['lib']!.sizeBytes, isNull);
    });

    test('normalizes paths and finds parents', () {
      final source = _project();

      expect(source.absolute('app/lib/'), '/app/lib');
      expect(source.absolute('/app/./lib/../README.md'), '/app/README.md');
      expect(source.parent('/app/lib/src'), '/app/lib');
      expect(source.parent('/app'), '/');
      expect(source.parent('/'), '/');
      expect(_names(source.list('app/lib/')), ['main.dart', 'src']);
    });

    test('reports missing directories and files listed as directories', () {
      final source = _project();

      expect(
        () => source.list('/nope'),
        throwsA(
          isA<FileSourceException>().having(
            (e) => e.message,
            'message',
            'No such directory: /nope',
          ),
        ),
      );
      expect(
        () => source.list('/app/README.md'),
        throwsA(
          isA<FileSourceException>().having(
            (e) => e.message,
            'message',
            'Not a directory: /app/README.md',
          ),
        ),
      );
    });

    test('a path that is also another path\'s parent is a directory', () {
      for (final paths in [
        ['/a', '/a/b.txt'],
        ['/a/b.txt', '/a'],
      ]) {
        final source = MemoryFileSource(paths);

        expect(source.list('/').single.isDirectory, isTrue, reason: '$paths');
        expect(_names(source.list('/a')), ['b.txt'], reason: '$paths');
      }
    });
  });

  group('file widgets over a MemoryFileSource', () {
    testWidgets('FileBrowser browses a tree without touching the disk', (
      tester,
    ) {
      FileEntry? activated;
      tester.pumpWidget(
        FileBrowser(
          source: _project(),
          initialDirectory: '/app',
          autofocus: true,
          onActivate: (entry) => activated = entry,
        ),
      );
      var out = tester.renderToString(
        size: const CellSize(40, 8),
        emptyMark: ' ',
      );
      expect(out, contains('/app'));
      expect(out, contains('build/'));
      expect(out, contains('lib/'));
      expect(out, contains('README.md'));
      expect(out, isNot(contains('.env')), reason: 'hidden by default');

      // build/ is first (directories lead), then lib/: open lib.
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(KeyCode.enter));
      out = tester.renderToString(size: const CellSize(40, 8), emptyMark: ' ');
      expect(out, contains('/app/lib'));
      expect(out, contains('src/'));
      expect(out, contains('main.dart'));

      // src/ leads, then main.dart: activate the file.
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(KeyCode.enter));
      expect(activated?.path, '/app/lib/main.dart');

      tester.sendKey(const KeyEvent(KeyCode.backspace));
      out = tester.renderToString(size: const CellSize(40, 8), emptyMark: ' ');
      expect(out, contains('README.md'), reason: 'went back up to /app');
    });

    testWidgets('FileBrowser applies entryFilter and shows listing errors', (
      tester,
    ) {
      tester.pumpWidget(
        FileBrowser(
          source: _project(),
          initialDirectory: '/app',
          entryFilter: (entry) => entry.isDirectory,
        ),
      );
      var out = tester.renderToString(
        size: const CellSize(40, 8),
        emptyMark: ' ',
      );
      expect(out, contains('lib/'));
      expect(out, isNot(contains('README.md')));

      // The browser reads initialDirectory once, so key a fresh one.
      tester.pumpWidget(
        FileBrowser(
          key: const ValueKey('missing'),
          source: _project(),
          initialDirectory: '/missing',
        ),
      );
      out = tester.renderToString(size: const CellSize(40, 8), emptyMark: ' ');
      expect(out, contains('No such directory: /missing'));
    });

    testWidgets('FilePicker picks a file from a tree', (tester) {
      FileEntry? picked;
      tester.pumpWidget(
        FilePicker(
          source: _project(),
          initialDirectory: '/app/lib',
          autofocus: true,
          filter: (entry) => entry.isDirectory || entry.name.endsWith('.dart'),
          onSelect: (file) => picked = file,
        ),
      );
      final out = tester.renderToString(
        size: const CellSize(40, 8),
        emptyMark: ' ',
      );
      expect(out, contains('/app/lib'));
      expect(out, contains('src/'));

      // src/ leads; main.dart is the second row.
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(KeyCode.enter));
      expect(picked?.path, '/app/lib/main.dart');
      expect(picked?.name, 'main.dart');
    });
  });
}
