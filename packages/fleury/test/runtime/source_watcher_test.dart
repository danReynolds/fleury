import 'dart:async';
import 'dart:io';

import 'package:fleury/src/runtime/source_watcher.dart';
import 'package:test/test.dart';
import 'package:watcher/watcher.dart';

void main() {
  group('DevSourceRoots', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('fleury_watch_roots_');
    });

    tearDown(() {
      temp.deleteSync(recursive: true);
    });

    Directory dir(String relative) =>
        Directory('${temp.path}/$relative')..createSync(recursive: true);

    test('watches the root package lib+bin and local path deps, '
        'skips the pub cache', () {
      dir('app/lib');
      dir('app/bin');
      dir('app/.dart_tool');
      dir('local_dep/lib');
      dir('cache/hosted/pub.dev/http-1.0.0/lib');
      dir('cache/git/fleury-abc123/packages/fleury/lib');

      final roots = DevSourceRoots.resolveFromConfig(
        <String, Object?>{
          'configVersion': 2,
          'packages': <Object?>[
            <String, Object?>{'name': 'app', 'rootUri': '../'},
            <String, Object?>{
              'name': 'local_dep',
              'rootUri': '../../local_dep',
            },
            <String, Object?>{
              'name': 'http',
              'rootUri':
                  Uri.directory(
                    '${temp.path}/cache/hosted/pub.dev/http-1.0.0',
                  ).toString(),
            },
            <String, Object?>{
              'name': 'fleury',
              'rootUri':
                  Uri.directory(
                    '${temp.path}/cache/git/fleury-abc123/packages/fleury',
                  ).toString(),
            },
          ],
        },
        configDirectory: Uri.directory('${temp.path}/app/.dart_tool'),
        pubCachePath: '${temp.path}/cache',
      );

      expect(
        roots.directories,
        unorderedEquals(<String>[
          Directory('${temp.path}/app/lib').path,
          Directory('${temp.path}/app/bin').path,
          Directory('${temp.path}/local_dep/lib').path,
        ]),
      );
    });

    test('skips packages whose lib/ does not exist and non-root bin/', () {
      dir('app/lib');
      dir('app/.dart_tool');
      dir('no_lib_dep/bin'); // bin only — not the root package, not watched.

      final roots = DevSourceRoots.resolveFromConfig(
        <String, Object?>{
          'packages': <Object?>[
            <String, Object?>{'name': 'app', 'rootUri': '../'},
            <String, Object?>{
              'name': 'no_lib_dep',
              'rootUri': '../../no_lib_dep',
            },
          ],
        },
        configDirectory: Uri.directory('${temp.path}/app/.dart_tool'),
        pubCachePath: '${temp.path}/cache',
      );

      expect(roots.directories, <String>[
        Directory('${temp.path}/app/lib').path,
      ]);
    });

    test('resolve returns null without a package_config', () {
      expect(DevSourceRoots.resolve(projectRoot: temp.path), isNull);
    });

    test('resolve reads a real package_config.json from disk', () {
      dir('app/lib');
      dir('app/.dart_tool');
      File('${temp.path}/app/.dart_tool/package_config.json').writeAsStringSync(
        '{"configVersion":2,"packages":[{"name":"app","rootUri":"../"}]}',
      );

      final roots = DevSourceRoots.resolve(
        projectRoot: '${temp.path}/app',
        pubCachePath: '${temp.path}/cache',
      );
      expect(roots, isNotNull);
      expect(roots!.directories, contains(Directory('${temp.path}/app/lib').path));
    });
  });

  group('SourceWatcher', () {
    test('coalesces a burst into one batch and filters non-dart files', () async {
      final fake = _FakeWatcher('/app/lib');
      final batches = <Set<String>>[];
      final watcher = SourceWatcher(
        roots: DevSourceRoots(directories: ['/app/lib']),
        onChanged: batches.add,
        debounce: const Duration(milliseconds: 20),
        watcherFactory: (_) => fake,
      )..start();

      fake.emit('/app/lib/a.dart');
      fake.emit('/app/lib/b.dart');
      fake.emit('/app/lib/notes.md'); // filtered
      fake.emit('/app/lib/a.dart'); // deduped

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches, hasLength(1));
      expect(batches.single, {'/app/lib/a.dart', '/app/lib/b.dart'});

      // A later save starts a fresh batch.
      fake.emit('/app/lib/c.dart');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches, hasLength(2));
      expect(batches.last, {'/app/lib/c.dart'});

      await watcher.dispose();
    });

    test('dispose stops pending batches and further events', () async {
      final fake = _FakeWatcher('/app/lib');
      final batches = <Set<String>>[];
      final watcher = SourceWatcher(
        roots: DevSourceRoots(directories: ['/app/lib']),
        onChanged: batches.add,
        debounce: const Duration(milliseconds: 20),
        watcherFactory: (_) => fake,
      )..start();

      fake.emit('/app/lib/a.dart');
      await watcher.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches, isEmpty);
    });

    test('a watcher stream error does not take the session down', () async {
      final fake = _FakeWatcher('/app/lib');
      final batches = <Set<String>>[];
      final watcher = SourceWatcher(
        roots: DevSourceRoots(directories: ['/app/lib']),
        onChanged: batches.add,
        debounce: const Duration(milliseconds: 20),
        watcherFactory: (_) => fake,
      )..start();

      fake.controller.addError(const FileSystemException('gone'));
      fake.emit('/app/lib/a.dart');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // The error ended that root's subscription quietly; no crash. (With a
      // single root the batch may be lost — acceptable best-effort behavior.)
      await watcher.dispose();
    });
  });
}

final class _FakeWatcher implements Watcher {
  _FakeWatcher(this.path);

  @override
  final String path;

  final StreamController<WatchEvent> controller =
      StreamController<WatchEvent>.broadcast();

  void emit(String changedPath) =>
      controller.add(WatchEvent(ChangeType.MODIFY, changedPath));

  @override
  Stream<WatchEvent> get events => controller.stream;

  @override
  bool get isReady => true;

  @override
  Future<void> get ready => Future<void>.value();
}
