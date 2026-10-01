/// Kind of entry a [FileSource] lists.
enum FileEntryType { directory, file, link, other }

/// One entry in a directory listing, as `FileBrowser` and `FilePicker` show
/// it.
final class FileEntry {
  const FileEntry({
    required this.path,
    required this.name,
    required this.type,
    this.sizeBytes,
    this.modified,
    this.hidden = false,
  });

  /// Absolute path, in the source's own path syntax.
  final String path;

  /// Last segment of [path], as displayed.
  final String name;

  /// Whether this is a directory, a file, or something else.
  final FileEntryType type;

  /// Size of a file in bytes, when the source knows it.
  final int? sizeBytes;

  /// Last modification time, when the source knows it.
  final DateTime? modified;

  /// Whether the entry is hidden by convention, such as a dot-file.
  final bool hidden;

  bool get isDirectory => type == FileEntryType.directory;
  bool get isFile => type == FileEntryType.file;
}

/// Predicate applied to entries when a directory is read.
typedef FileEntryFilter = bool Function(FileEntry entry);

/// Thrown by [FileSource.list] when a directory can't be listed.
final class FileSourceException implements Exception {
  const FileSourceException(this.message);

  /// What went wrong, as the file widgets display it.
  final String message;

  @override
  String toString() => 'FileSourceException: $message';
}

/// Where `FileBrowser` and `FilePicker` read directories from.
///
/// On native platforms both widgets default to the local disk
/// (`LocalFileSource`). A browser has no disk to list, so a browser embed
/// passes a source: a [MemoryFileSource] for a fixed tree, or your own
/// implementation over data the app already holds, such as a project listing
/// fetched from a server. Listing is synchronous: the widgets read a directory
/// when they open it.
abstract interface class FileSource {
  /// [path] as an absolute, normalized path.
  String absolute(String path);

  /// The directory containing [path], or [path] itself at a root.
  String parent(String path);

  /// The entries directly inside [directory], in any order.
  ///
  /// Throws a [FileSourceException] when [directory] can't be listed.
  List<FileEntry> list(String directory);
}

/// A fixed, in-memory tree of `/`-separated paths.
///
/// ```dart
/// final source = MemoryFileSource([
///   '/app/lib/main.dart',
///   '/app/README.md',
///   '/app/build/', // a trailing slash makes an empty directory
/// ]);
/// ```
///
/// A file's parent directories exist implicitly. `sizes` gives file sizes in
/// bytes, keyed by path. Relative paths resolve against `/`.
final class MemoryFileSource implements FileSource {
  MemoryFileSource(Iterable<String> paths, {Map<String, int> sizes = const {}})
    : _sizes = {
        for (final entry in sizes.entries) _normalize(entry.key): entry.value,
      } {
    for (final raw in paths) {
      final path = _normalize(raw);
      if (path == '/') continue;
      _add(
        path,
        raw.endsWith('/') ? FileEntryType.directory : FileEntryType.file,
      );
    }
  }

  // Directory path -> child name -> type.
  final Map<String, Map<String, FileEntryType>> _children = {'/': {}};
  final Map<String, int> _sizes;

  void _add(String path, FileEntryType type) {
    final parentPath = _parentOf(path);
    if (parentPath != path && !_children.containsKey(parentPath)) {
      _add(parentPath, FileEntryType.directory);
    }
    final name = path.substring(path.lastIndexOf('/') + 1);
    final siblings = _children[parentPath]!;
    // A path listed as a file and also as some other path's parent is a
    // directory.
    if (siblings[name] != FileEntryType.directory) siblings[name] = type;
    if (type == FileEntryType.directory) _children.putIfAbsent(path, () => {});
  }

  @override
  String absolute(String path) => _normalize(path);

  @override
  String parent(String path) => _parentOf(_normalize(path));

  @override
  List<FileEntry> list(String directory) {
    final path = _normalize(directory);
    final children = _children[path];
    if (children == null) {
      final isFile = _children[_parentOf(path)]?[_nameOf(path)] != null;
      throw FileSourceException(
        isFile ? 'Not a directory: $path' : 'No such directory: $path',
      );
    }
    return [
      for (final MapEntry(key: name, value: type) in children.entries)
        FileEntry(
          path: path == '/' ? '/$name' : '$path/$name',
          name: name,
          type: type,
          sizeBytes: type == FileEntryType.file
              ? _sizes[path == '/' ? '/$name' : '$path/$name']
              : null,
          hidden: name.startsWith('.'),
        ),
    ];
  }

  static String _normalize(String path) {
    final segments = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (segments.isNotEmpty) segments.removeLast();
        continue;
      }
      segments.add(segment);
    }
    return '/${segments.join('/')}';
  }

  static String _parentOf(String path) {
    final index = path.lastIndexOf('/');
    return index <= 0 ? '/' : path.substring(0, index);
  }

  static String _nameOf(String path) =>
      path.substring(path.lastIndexOf('/') + 1);
}
