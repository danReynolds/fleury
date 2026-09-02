import 'dart:io';

/// Finds the nearest LIVE implicit Fleury handle inside the current Dart
/// package.
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
///
/// Path shape is not ownership: `.fleury/handle` is an ordinary file that
/// outlives a SIGKILLed `fleury shell` / `fleury serve`, and a leftover one
/// used to keep every later `dart run` in that project out of the hot-reload
/// supervisor — silently, project-wide, with the app still working. Each
/// candidate is therefore proved live before it is returned, and a handle
/// proved dead is deleted on the way past (see [_handleOwnerIsAlive]).
File? findImplicitFleuryHandle([Directory? workingDirectory]) {
  final start = (workingDirectory ?? Directory.current).absolute;
  final packageRoot = _nearestPackageRoot(start);
  if (packageRoot == null) {
    final local = _handleIn(start);
    return _liveOrReaped(local);
  }

  var directory = start;
  while (true) {
    final live = _liveOrReaped(_handleIn(directory));
    if (live != null) return live;
    if (directory.path == packageRoot.path) return null;
    directory = directory.parent;
  }
}

/// [handle] when it exists and its owner is alive; null otherwise — deleting a
/// handle whose owner is provably gone so the next run does not have to
/// re-prove it.
File? _liveOrReaped(File handle) {
  if (!handle.existsSync()) return null;
  if (_handleOwnerIsAlive(handle)) return handle;
  try {
    handle.deleteSync();
  } catch (_) {
    // Read-only checkout, a racing owner, someone else's cleanup: the handle
    // is already being ignored, which is the part that matters.
  }
  return null;
}

/// Whether a `fleury shell` / `fleury serve` still owns [handle]'s directory.
///
/// The CLI takes an exclusive lock on `.fleury/lock` for as long as it owns
/// the handle (`_tryAcquireHandleLock` in bin/fleury.dart) and the kernel
/// drops that lock when the process dies — including under SIGKILL, where no
/// cleanup code runs and the handle file survives. Non-blocking `lockSync`
/// therefore answers "is anybody home?" synchronously, which is what the
/// synchronous discovery path needs.
///
/// Conservative in both directions: a missing lock file means no owner ever
/// registered (the CLI creates it before writing the handle), and an
/// unopenable one means the answer cannot be established — the handle is kept
/// rather than hijacking a session that may well be live.
///
/// Note the POSIX record-lock rule this depends on: a lock belongs to the
/// process, and closing ANY descriptor for the file drops that process's
/// locks. Only a process that does NOT own the handle may run this probe —
/// today the app side (runApp / the dev supervisor's pre-gate), never the CLI
/// that holds the lock.
bool _handleOwnerIsAlive(File handle) {
  final lock = File('${handle.parent.path}/lock');
  if (!lock.existsSync()) return false;
  final RandomAccessFile probe;
  try {
    // Append, never write: opening must not truncate the owner's lock file,
    // and existsSync above means this does not create one either.
    probe = lock.openSync(mode: FileMode.append);
  } on FileSystemException {
    return true;
  }
  try {
    // Non-blocking: throws when someone else holds it, which is the live case.
    probe.lockSync(FileLock.exclusive);
    try {
      probe.unlockSync();
    } catch (_) {}
    return false;
  } on FileSystemException {
    return true;
  } finally {
    try {
      probe.closeSync();
    } catch (_) {}
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
