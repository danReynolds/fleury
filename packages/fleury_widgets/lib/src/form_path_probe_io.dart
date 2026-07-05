// Native implementation of the form path-field's `mustExist` check. Selected
// over form_path_probe.dart by a conditional import when `dart:io` is available
// (terminal or served target). See form_path_probe.dart for the web stub.

import 'dart:io' show FileSystemEntity, FileSystemEntityType;

/// Returns a validation error string if [path] fails the existence / kind
/// check, or null when it passes.
String? probeFormPathExistence({
  required String path,
  required bool requireFile,
  required bool requireDirectory,
  required String label,
}) {
  final type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.notFound) {
    return '$label must exist.';
  }
  if (requireFile && type != FileSystemEntityType.file) {
    return '$label must be a file.';
  }
  if (requireDirectory && type != FileSystemEntityType.directory) {
    return '$label must be a directory.';
  }
  return null;
}
