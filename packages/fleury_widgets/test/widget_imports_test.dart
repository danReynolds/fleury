import 'dart:io';

import 'package:fleury_widgets/fleury_widgets.dart' as widgets;
import 'package:fleury_widgets/fleury_widgets_io.dart' as native;
import 'package:fleury_widgets/fleury_widgets_web.dart' as legacy;
import 'package:test/test.dart';

void main() {
  test('native and legacy imports use the same widget types', () {
    final widgets.FileSource nativeSource = const native.LocalFileSource();
    final widgets.FileSource memorySource = legacy.MemoryFileSource(const []);
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
