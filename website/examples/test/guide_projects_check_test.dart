// The generator's hidden-code check (bin/guide_projects.dart), on small
// projects. Each project marks its editable views with « and ».
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:test/test.dart';

import '../bin/guide_projects.dart' as generator;

/// A generated project: examples/registry.dart holds [registry], and
/// [others] holds more project files. Each file marks its views with « and ».
Map<String, Object> project(
  String registry, {
  Map<String, String> others = const {},
}) {
  final files = <String, String>{'main.dart': ''};
  final views = <Map<String, Object>>[];
  for (final MapEntry(key: file, value: marked) in {
    'examples/registry.dart': registry,
    ...others,
  }.entries) {
    final out = StringBuffer();
    var start = 0;
    for (final rune in marked.runes) {
      final char = String.fromCharCode(rune);
      if (char == '«') {
        start = out.length;
      } else if (char == '»') {
        views.add({
          'id': 'view-${views.length}',
          'label': 'view_${views.length}.dart',
          'file': file,
          'start': start,
          'end': out.length,
        });
      } else {
        out.write(char);
      }
    }
    files[file] = out.toString();
  }
  return {'files': files, 'views': views};
}

/// The names of the code [registry]'s views don't show.
Set<String> hidden(String registry) =>
    generator.hiddenCode(project(registry)).map((h) => h.name).toSet();

void main() {
  group('hiddenCode', () {
    test('passes a demo whose view shows everything it runs', () {
      expect(
        hidden('''
«class _Demo extends StatelessWidget {
  const _Demo();

  @override
  Widget build(BuildContext context) => const Text('hi');
}»

Widget example() => const _Demo();
'''),
        isEmpty,
      );
    });

    test('finds a helper that a partial view of its class calls', () {
      expect(
        hidden('''
class _Demo extends StatelessWidget {
  const _Demo();

  Widget _label() => const Text('hi');

  @override
  Widget build(BuildContext context) => «Center(child: _label())»;
}

Widget example() => const _Demo();
'''),
        contains('_Demo._label'),
      );
    });

    test('checks what a State view\'s widget reads', () {
      expect(
        hidden(r'''
const _defaultRows = 3;

class _Demo extends StatefulWidget {
  const _Demo({this.rows = _defaultRows});

  final int rows;

  @override
  State<_Demo> createState() => _DemoState();
}

«class _DemoState extends State<_Demo> {
  @override
  Widget build(BuildContext context) => Text('${widget.rows}');
}»

Widget example() => const _Demo();
'''),
        contains('_defaultRows'),
      );
    });

    test('counts an extension method reached through a target', () {
      expect(
        hidden('''
extension _Shout on String {
  String shout() => toUpperCase();
}

«Widget example() => Text('hi'.shout());»
'''),
        anyElement(startsWith('_Shout')),
      );
    });

    test('a field in one view does not hide a top-level name used in '
        'another', () {
      expect(
        hidden(r'''
const _limit = 5;

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

«class _CounterState extends State<_Counter> {
  final _limit = 2;

  @override
  Widget build(BuildContext context) => Text('$_limit');
}»

«Widget _footer() => Text('of $_limit');»

Widget example() => const _Counter();
'''),
        {'_limit'},
      );
    });

    test('a local in one view does not hide a top-level name used in '
        'another', () {
      expect(
        hidden(r'''
const _limit = 5;

«Widget _first() {
  const _limit = 1;
  return Text('$_limit');
}»

«Widget _second() => Text('$_limit');»

«Widget example() => Column(children: [_first(), _second()]);»
'''),
        {'_limit'},
      );
    });

    test('a local hides a top-level name only inside its own function', () {
      // One view: `_first` declares a local `_limit`, `_second` reads the
      // hidden top-level one.
      expect(
        hidden(r'''
const _limit = 5;

«Widget _first() {
  const _limit = 1;
  return Text('$_limit');
}

Widget _second() => Text('$_limit');

Widget example() => Column(children: [_first(), _second()]);»
'''),
        {'_limit'},
      );
    });

    test(
      "a shown private name in one file does not stand for another file's",
      () {
        final names = generator
            .hiddenCode(
              project(
                r'''
«const _rows = 3;

Widget example() => Text('${_rows + helperRows}');»
''',
                others: {
                  'examples/helpers.dart': '''
const _rows = 4;

«const helperRows = _rows;»
''',
                },
              ),
            )
            .map((h) => '${h.file} ${h.name}')
            .toSet();
        expect(names, {'examples/helpers.dart _rows'});
      },
    );

    test('a named constructor uses its class', () {
      const demo = '''
class _Demo extends StatelessWidget {
  const _Demo.wide();

  @override
  Widget build(BuildContext context) => const Text('wide');
}
''';
      expect(
        hidden('$demo\n«Widget example() => const _Demo.wide();»\n'),
        contains('_Demo'),
      );
      expect(
        hidden(
          "$demo\n«Widget _other() => const Text('x');»\n\n"
          'Widget example() => const _Demo.wide();\n',
        ),
        contains('_Demo'),
      );
    });

    test('ignores dot shorthands, cascades, and doc comments', () {
      expect(
        hidden(r'''
const center = 0;

void clear() {}

void _helper() {}

«/// Mentions [_helper] without calling it.
Widget example() {
  final items = <int>[1]..clear();
  return Align(alignment: .center, child: Text('${items.length}'));
}»
'''),
        isEmpty,
      );
    });
  });

  group('demoProblems', () {
    test('an excused class covers its members', () {
      expect(
        generator.demoProblems(
          project('''
class _Tile extends StatelessWidget {
  const _Tile();

  Widget get _label => const Text('tile');

  @override
  Widget build(BuildContext context) => «Center(child: _label)»;
}

Widget example() => const _Tile();
'''),
          {'_Tile': 'an excerpt'},
        ),
        isEmpty,
      );
    });

    test('an excused file covers what it declares, not what it uses', () {
      const other = r'''
const _greeting = 'hi';

class Demo extends StatelessWidget {
  const Demo();

  @override
  Widget build(BuildContext context) => Text('$_greeting $suffix');
}
''';
      Map<String, Object> demo(String registry) =>
          project(registry, others: {'examples/other.dart': other});
      const excuse = {'examples/other.dart': 'shown elsewhere in full'};
      expect(
        generator.demoProblems(
          demo('''
import 'other.dart' as other;

const suffix = '!';

«Widget _shown() => const Text('the lesson');»

Widget example() => const other.Demo();
'''),
          excuse,
        ),
        ['Demo uses suffix, which no view shows'],
      );
      expect(
        generator.demoProblems(
          demo('''
import 'other.dart' as other;

«const suffix = '!';»

Widget example() => const other.Demo();
'''),
          excuse,
        ),
        isEmpty,
      );
    });

    test('reports an excuse that matches nothing', () {
      expect(
        generator.demoProblems(
          project('''
«class _Demo extends StatelessWidget {
  const _Demo();

  @override
  Widget build(BuildContext context) => const Text('hi');
}»

Widget example() => const _Demo();
'''),
          {'_Gone': 'an excerpt'},
        ),
        ['hiddenByDesign lists _Gone, which is not hidden'],
      );
    });

    test(
      'code reached through an excused declaration needs its own excuse',
      () {
        const reached = '''
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) => const Text('preview');
}

class _Tile extends StatelessWidget {
  const _Tile();

  Widget get _label => const Text('tile');

  @override
  Widget build(BuildContext context) =>
      Column(children: [«_label», const _Preview()]);
}

Widget example() => const _Tile();
''';
        expect(
          generator.demoProblems(project(reached), {'_Tile': 'an excerpt'}),
          [contains('_Preview')],
        );
      },
    );
  });

  group('widgetPageViews', () {
    test('edits the class a named-constructor demo creates', () {
      final dir = Directory.systemTemp.createTempSync('guide_projects_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final registry = File('${dir.path}/registry.dart')
        ..writeAsStringSync('''
Widget _framed(Widget child) => child;

class _Demo extends StatelessWidget {
  const _Demo.wide();

  @override
  Widget build(BuildContext context) => const Text('wide');
}

final builder = _framed(const _Demo.wide());
''');
      final unit = parseString(
        content: registry.readAsStringSync(),
        throwIfDiagnostics: false,
      ).unit;
      final builder = unit.declarations
          .whereType<TopLevelVariableDeclaration>()
          .single
          .variables
          .variables
          .single
          .initializer!;
      final views = generator.widgetPageViews(
        'demo.basic',
        registry.path,
        builder,
      );
      expect(views.single['declaration'], '_Demo');
    });
  });
}
