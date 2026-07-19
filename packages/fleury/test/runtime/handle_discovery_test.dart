import 'dart:io';

import 'package:fleury/src/runtime/handle_discovery.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fleury_handle_discovery_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('finds a package-root handle from a nested working directory', () {
    _writePubspec(tempDir, 'root_package');
    final handle = _writeHandle(tempDir, '/tmp/fleury-package.sock');
    final nested = Directory('${tempDir.path}/lib/src')
      ..createSync(recursive: true);

    expect(findImplicitFleuryHandle(nested)?.path, handle.path);
  });

  test('stops at the nearest Dart package boundary', () {
    _writePubspec(tempDir, 'outer_package');
    _writeHandle(tempDir, '/tmp/fleury-outer.sock');
    final inner = Directory('${tempDir.path}/packages/inner')
      ..createSync(recursive: true);
    _writePubspec(inner, 'inner_package');
    final nested = Directory('${inner.path}/bin/nested')
      ..createSync(recursive: true);

    expect(findImplicitFleuryHandle(nested), isNull);

    final innerHandle = _writeHandle(inner, '/tmp/fleury-inner.sock');
    expect(findImplicitFleuryHandle(nested)?.path, innerHandle.path);
  });

  test('outside a Dart package accepts only a current-directory handle', () {
    final ancestor = Directory('${tempDir.path}/shared')..createSync();
    _writeHandle(ancestor, '/tmp/fleury-untrusted.sock');
    final child = Directory('${ancestor.path}/child')..createSync();

    expect(findImplicitFleuryHandle(child), isNull);

    final localHandle = _writeHandle(child, '/tmp/fleury-local.sock');
    expect(findImplicitFleuryHandle(child)?.path, localHandle.path);
  });
}

void _writePubspec(Directory directory, String name) {
  File('${directory.path}/pubspec.yaml').writeAsStringSync('name: $name\n');
}

File _writeHandle(Directory directory, String socketPath) {
  final handle = File('${directory.path}/.fleury/handle');
  handle.parent.createSync(recursive: true);
  handle.writeAsStringSync(socketPath);
  return handle;
}
