import 'dart:io';

import 'file_source.dart';

/// The local disk, read through `dart:io`. `FileBrowser` and `FilePicker` use
/// it by default on native platforms; it is not available in the browser.
final class LocalFileSource implements FileSource {
  const LocalFileSource();

  @override
  String absolute(String path) => Directory(path).absolute.path;

  @override
  String parent(String path) => Directory(path).absolute.parent.path;

  @override
  List<FileEntry> list(String directory) {
    final List<FileSystemEntity> entities;
    try {
      entities = Directory(directory).listSync(followLinks: false);
    } on FileSystemException catch (error) {
      throw FileSourceException(error.message);
    }
    return [for (final entity in entities) _entryFor(entity)];
  }

  FileEntry _entryFor(FileSystemEntity entity) {
    final path = entity.absolute.path;
    final name = _basename(path);
    FileStat? stat;
    try {
      stat = entity.statSync();
    } on FileSystemException {
      stat = null;
    }
    return FileEntry(
      path: path,
      name: name,
      type: _typeFor(entity, stat),
      sizeBytes: stat?.type == FileSystemEntityType.file ? stat!.size : null,
      modified: stat?.modified,
      hidden: name.startsWith('.'),
    );
  }

  FileEntryType _typeFor(FileSystemEntity entity, FileStat? stat) {
    if (entity is Directory) return FileEntryType.directory;
    if (entity is File) return FileEntryType.file;
    if (entity is Link) return FileEntryType.link;
    return switch (stat?.type) {
      FileSystemEntityType.directory => FileEntryType.directory,
      FileSystemEntityType.file => FileEntryType.file,
      FileSystemEntityType.link => FileEntryType.link,
      _ => FileEntryType.other,
    };
  }

  static String _basename(String path) {
    final separator = Platform.pathSeparator;
    final normalized = path.endsWith(separator) && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final index = normalized.lastIndexOf(separator);
    return index < 0 ? normalized : normalized.substring(index + 1);
  }
}
