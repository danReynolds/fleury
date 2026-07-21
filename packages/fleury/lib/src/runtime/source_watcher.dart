// Dev-time source watching for self-hosting hot reload.
//
// Two pieces, both deliberately dumb and unit-testable:
//
//   - DevSourceRoots — resolves *which directories to watch* from the app's
//     `.dart_tool/package_config.json`: the root package's lib/ and bin/, plus
//     the lib/ of every *local* dependency (path deps — e.g. a framework
//     checkout during development). Anything inside the pub cache is immutable
//     and skipped.
//   - SourceWatcher — recursive-watches those roots (package:watcher, which
//     papers over Linux's non-recursive inotify and editors' atomic-rename
//     saves), filters to `.dart`, and coalesces bursts behind a debounce so a
//     format-on-save multi-file write triggers one reload, not five.
//
// This file is native-only dev machinery: never exported from the public
// barrels and never imported by web-safe code.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:watcher/watcher.dart';

/// The source directories a dev session should watch for hot reload.
class DevSourceRoots {
  DevSourceRoots({required this.directories});

  /// Absolute directory paths to watch recursively.
  final List<String> directories;

  /// Resolves watch roots for the package containing [projectRoot] (defaults
  /// to the current working directory): the nearest directory — itself or an
  /// ancestor — holding `.dart_tool/package_config.json`, matching how
  /// `dart run` locates the config when launched from a subdirectory.
  ///
  /// Returns null when no ancestor has one — the app is not running from a
  /// pub workspace (e.g. a compiled snapshot in a bare directory) and there
  /// is nothing meaningful to watch.
  static DevSourceRoots? resolve({String? projectRoot, String? pubCachePath}) {
    var dir = Directory(projectRoot ?? Directory.current.path).absolute;
    while (true) {
      final configFile = File(
        '${dir.path}${Platform.pathSeparator}.dart_tool'
        '${Platform.pathSeparator}package_config.json',
      );
      if (configFile.existsSync()) {
        final Object? decoded;
        try {
          decoded = jsonDecode(configFile.readAsStringSync());
        } on FormatException {
          return null;
        }
        if (decoded is! Map<String, Object?>) return null;
        return resolveFromConfig(
          decoded,
          configDirectory: configFile.parent.uri,
          pubCachePath: pubCachePath ?? defaultPubCachePath(),
        );
      }
      final parent = dir.parent;
      if (parent.path == dir.path) return null; // Hit the filesystem root.
      dir = parent;
    }
  }

  /// Pure resolution from a decoded package_config — separated for tests.
  ///
  /// [configDirectory] is the URI of the directory holding
  /// `package_config.json` (relative `rootUri`s resolve against it).
  /// Packages whose root lives under [pubCachePath] are skipped (hosted and
  /// git dependencies are immutable); everything else is a local package the
  /// developer may be editing.
  static DevSourceRoots resolveFromConfig(
    Map<String, Object?> config, {
    required Uri configDirectory,
    required String pubCachePath,
  }) {
    final packages = config['packages'];
    final directories = <String>[];
    final normalizedCache = _normalize(pubCachePath);
    if (packages is List) {
      for (final entry in packages) {
        if (entry is! Map<String, Object?>) continue;
        final rootUri = entry['rootUri'];
        if (rootUri is! String) continue;
        final resolved = configDirectory.resolve(
          rootUri.endsWith('/') ? rootUri : '$rootUri/',
        );
        if (resolved.scheme != 'file') continue;
        final rootPath = resolved.toFilePath();
        if (_normalize(rootPath).startsWith(normalizedCache)) continue;
        final lib = Directory('${rootPath}lib');
        if (lib.existsSync()) directories.add(lib.path);
        // Entrypoints live outside lib/ only for the root package, whose
        // rootUri resolves to the directory above .dart_tool.
        final isRootPackage =
            _normalize(rootPath) ==
            _normalize(configDirectory.resolve('../').toFilePath());
        if (isRootPackage) {
          final bin = Directory('${rootPath}bin');
          if (bin.existsSync()) directories.add(bin.path);
        }
      }
    }
    return DevSourceRoots(directories: directories);
  }

  /// The active pub cache root: `PUB_CACHE` when set, else the platform
  /// default (`~/.pub-cache`, or `%LOCALAPPDATA%\Pub\Cache` on Windows).
  static String defaultPubCachePath() {
    final env = Platform.environment['PUB_CACHE'];
    if (env != null && env.isNotEmpty) return env;
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return '$localAppData\\Pub\\Cache';
      }
    }
    final home = Platform.environment['HOME'];
    return '${home ?? ''}/.pub-cache';
  }

  static String _normalize(String path) {
    var p = path.replaceAll('\\', '/');
    if (!p.endsWith('/')) p = '$p/';
    return Platform.isWindows || Platform.isMacOS ? p.toLowerCase() : p;
  }
}

/// Watches [DevSourceRoots] and fires one coalesced callback per burst of
/// `.dart` changes.
class SourceWatcher {
  SourceWatcher({
    required this.roots,
    required this.onChanged,
    this.debounce = const Duration(milliseconds: 200),
    this.watcherFactory = _defaultWatcherFactory,
  });

  final DevSourceRoots roots;

  /// Called after the debounce window with the batch of changed `.dart`
  /// paths (modify/add/remove all count — a deleted file still needs a
  /// reload so stale code stops running).
  final void Function(Set<String> paths) onChanged;

  /// Quiet period after the last event before [onChanged] fires.
  final Duration debounce;

  /// Test seam: builds the per-root watcher.
  final Watcher Function(String path) watcherFactory;

  static Watcher _defaultWatcherFactory(String path) =>
      DirectoryWatcher(path);

  final List<StreamSubscription<WatchEvent>> _subscriptions = [];
  final Set<String> _pending = {};
  Timer? _timer;
  bool _disposed = false;

  /// Begins watching. Watcher backends surface errors (e.g. a root deleted
  /// mid-session) on their streams; those end that root's watch quietly —
  /// hot reload is best-effort dev machinery and must never take the app
  /// down.
  void start() {
    for (final root in roots.directories) {
      final watcher = watcherFactory(root);
      _subscriptions.add(
        watcher.events.listen(_onEvent, onError: (Object _) {}),
      );
    }
  }

  void _onEvent(WatchEvent event) {
    if (_disposed) return;
    if (!event.path.endsWith('.dart')) return;
    _pending.add(event.path);
    _timer?.cancel();
    _timer = Timer(debounce, _fire);
  }

  void _fire() {
    if (_disposed || _pending.isEmpty) return;
    final batch = Set<String>.from(_pending);
    _pending.clear();
    onChanged(batch);
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _pending.clear();
  }
}
