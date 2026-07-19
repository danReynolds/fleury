import 'dart:io';

/// Finds the nearest implicit Fleury handle inside the current Dart package.
///
/// A handle is trusted only when it sits between [workingDirectory] (the
/// process's current directory when omitted) and the nearest ancestor
/// containing `pubspec.yaml`, inclusive. This lets an app run from a package
/// subdirectory discover a shell started at the package root without accepting
/// a handle planted in an unrelated or shared ancestor.
///
/// A directory outside a Dart package may still use its own handle, but implicit
/// discovery does not walk upward in that case. Cross-project attachment is an
/// explicit `FLEURY_HANDLE` operation.
File? findImplicitFleuryHandle([Directory? workingDirectory]) {
  final start = (workingDirectory ?? Directory.current).absolute;
  final packageRoot = _nearestPackageRoot(start);
  if (packageRoot == null) {
    final local = _handleIn(start);
    return local.existsSync() ? local : null;
  }

  var directory = start;
  while (true) {
    final candidate = _handleIn(directory);
    if (candidate.existsSync()) return candidate;
    if (directory.path == packageRoot.path) return null;
    directory = directory.parent;
  }
}

Directory? _nearestPackageRoot(Directory start) {
  var directory = start;
  while (true) {
    if (File('${directory.path}/pubspec.yaml').existsSync()) return directory;
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}

File _handleIn(Directory directory) => File('${directory.path}/.fleury/handle');
