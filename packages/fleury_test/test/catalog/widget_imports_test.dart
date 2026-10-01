import 'dart:io';

import 'package:fleury/fleury_core.dart' as widgets;
import 'package:fleury/fleury.dart' as native;
import 'package:test/test.dart';

void main() {
  test('native and browser imports use the same widget types', () {
    final widgets.FileSource nativeSource = const native.LocalFileSource();
    final widgets.FileSource memorySource = widgets.MemoryFileSource(const []);
    expect(nativeSource, isA<native.FileSource>());
    expect(memorySource, isA<widgets.MemoryFileSource>());
  });

  test('explicit native source reads local files', () {
    final directory = Directory.systemTemp.createTempSync('fleury_source_');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/note.txt').writeAsStringSync('hello');
    const source = native.LocalFileSource();
    final entries = source.list(directory.path);
    expect(entries.single.name, 'note.txt');
    expect(entries.single.type, widgets.FileEntryType.file);
    expect(entries.single.sizeBytes, 5);
  });
}
