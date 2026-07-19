import 'dart:io';

/// The Dart SDK executable used for child tooling commands.
///
/// [Platform.resolvedExecutable] is only the SDK executable in a JIT process.
/// In a compiled Fleury CLI it points back to the Fleury binary itself, so
/// child commands must resolve Dart from PATH instead.
String get dartSdkExecutable => const bool.fromEnvironment('dart.vm.product')
    ? (Platform.isWindows ? 'dart.exe' : 'dart')
    : Platform.resolvedExecutable;
