// Catalog-wide fuzz / undersize pass for the non-viz widgets, mirroring
// what viz_fuzz_test.dart does for charts. Same payoff: any unguarded
// writeGrapheme path surfaces here via CellBuffer's existing RangeError
// on OOB writes — random sizes + random data drive the widget into the
// untested corners that focused tests skip.

import 'dart:math';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _word(Random rng, {int min = 1, int max = 10}) {
  const letters = 'abcdefghijklmnopqrstuvwxyz';
  final n = min + rng.nextInt(max - min + 1);
  return [for (var i = 0; i < n; i++) letters[rng.nextInt(26)]].join();
}

void main() {
  // ------------------------------------------------------------------
  // ProgressBar — has a direct writeGrapheme loop that scans `size.cols`.
  // ------------------------------------------------------------------
  group('ProgressBar fuzz / undersize', () {
    testWidgets('survives undersize container', (tester) {
      // Box smaller than the intrinsic width — make sure the bar's
      // internal loop respects the actual buffer width.
      tester.pumpWidget(
        const SizedBox(width: 3, height: 1, child: ProgressBar(value: 0.42)),
      );
      tester.render(size: const CellSize(3, 1));
    });

    testWidgets('fuzz: random values + sizes', (tester) {
      final rng = Random(0xBA1);
      for (var iter = 0; iter < 25; iter++) {
        final cols = 1 + rng.nextInt(40);
        final v = -1.0 + rng.nextDouble() * 3; // also try below 0 / above 1
        tester.pumpWidget(
          SizedBox(
            width: cols,
            height: 1,
            child: ProgressBar(value: v),
          ),
        );
        tester.render(size: CellSize(cols, 1));
      }
    });
  });

  // ------------------------------------------------------------------
  // Table — direct writeGrapheme for selection background + separator.
  // ------------------------------------------------------------------
  group('Table fuzz / undersize', () {
    testWidgets('survives an undersize container', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 5,
          height: 3,
          child: Table(
            header: const [Text('Name'), Text('Lang'), Text('Year')],
            rows: const [
              [Text('Ada'), Text('Ada'), Text('1843')],
              [Text('Grace'), Text('COBOL'), Text('1959')],
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(5, 3));
    });

    testWidgets('fuzz: random rows / cols / sizes', (tester) {
      final rng = Random(0x7AB);
      for (var iter = 0; iter < 20; iter++) {
        final colCount = 1 + rng.nextInt(5);
        final rowCount = rng.nextInt(8);
        final header = <Widget>[
          for (var c = 0; c < colCount; c++) Text(_word(rng)),
        ];
        final rows = <List<Widget>>[
          for (var r = 0; r < rowCount; r++)
            [for (var c = 0; c < colCount; c++) Text(_word(rng))],
        ];
        final ww = 4 + rng.nextInt(40);
        final hh = 2 + rng.nextInt(10);
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: hh,
            child: Table(header: header, rows: rows),
          ),
        );
        tester.render(size: CellSize(ww, hh));
      }
    });
  });

  // ------------------------------------------------------------------
  // Tabs — focus + content area composition.
  // ------------------------------------------------------------------
  group('Tabs fuzz / undersize', () {
    testWidgets('survives an undersize container', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 6,
          height: 2,
          child: Tabs(
            controller: TabController(),
            tabs: const [
              TabItem(label: 'Files', content: Text('a')),
              TabItem(label: 'Edit', content: Text('b')),
              TabItem(label: 'Run', content: Text('c')),
              TabItem(label: 'Debug', content: Text('d')),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(6, 2));
    });

    testWidgets('fuzz: random tab counts + labels + sizes', (tester) {
      final rng = Random(0x7AB5);
      for (var iter = 0; iter < 20; iter++) {
        final n = 1 + rng.nextInt(6);
        final tabs = [
          for (var i = 0; i < n; i++)
            TabItem(
              label: _word(rng, min: 1, max: 12),
              content: Text(_word(rng, min: 1, max: 30)),
            ),
        ];
        final ww = 4 + rng.nextInt(50);
        final hh = 2 + rng.nextInt(10);
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: hh,
            child: Tabs(
              controller: TabController(initialIndex: rng.nextInt(n)),
              tabs: tabs,
            ),
          ),
        );
        tester.render(size: CellSize(ww, hh));
      }
    });
  });

  // ------------------------------------------------------------------
  // Tree
  // ------------------------------------------------------------------
  group('Tree fuzz / undersize', () {
    testWidgets('survives a long-label tree in a narrow container', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 5,
          height: 3,
          child: Tree<String>(
            roots: [
              TreeNode<String>(
                'this-is-a-very-long-root-label',
                children: [TreeNode<String>('and-this-is-also-very-long')],
              ),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(5, 3));
    });

    testWidgets('fuzz: random tree shapes + sizes', (tester) {
      final rng = Random(0x7233);
      TreeNode<String> randomNode(int depth) {
        if (depth >= 3 || rng.nextDouble() > 0.5) {
          return TreeNode<String>(_word(rng));
        }
        return TreeNode<String>(
          _word(rng),
          children: [
            for (var i = 0; i < rng.nextInt(4); i++) randomNode(depth + 1),
          ],
        );
      }

      for (var iter = 0; iter < 15; iter++) {
        final roots = [
          for (var i = 0; i < 1 + rng.nextInt(4); i++) randomNode(0),
        ];
        final ww = 4 + rng.nextInt(30);
        final hh = 2 + rng.nextInt(12);
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: hh,
            child: Tree<String>(roots: roots),
          ),
        );
        tester.render(size: CellSize(ww, hh));
      }
    });
  });

  // ------------------------------------------------------------------
  // Menu — the trigger is what gets rendered until activated; we exercise
  // it at random sizes. The overlay-popped menu is fuzzed via its trigger
  // press paths in the focused tests.
  // ------------------------------------------------------------------
  group('Menu fuzz / undersize', () {
    testWidgets('survives undersize container', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 4,
          height: 1,
          child: Menu(
            trigger: const Text('▾ menu'),
            items: [
              MenuItem(label: 'this-is-too-long-for-the-box', onSelect: () {}),
              MenuItem(label: 'another-long-entry-here', onSelect: () {}),
            ],
          ),
        ),
      );
      tester.render(size: const CellSize(4, 1));
    });

    testWidgets('fuzz: random items + sizes', (tester) {
      final rng = Random(0x4E22);
      for (var iter = 0; iter < 15; iter++) {
        final n = 1 + rng.nextInt(8);
        final items = <MenuEntry>[
          for (var i = 0; i < n; i++)
            if (rng.nextDouble() > 0.85)
              const MenuSeparator()
            else
              MenuItem(label: _word(rng, min: 1, max: 14), onSelect: () {}),
        ];
        final ww = 4 + rng.nextInt(30);
        final hh = 1 + rng.nextInt(8);
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: hh,
            child: Menu(trigger: const Text('▾'), items: items),
          ),
        );
        tester.render(size: CellSize(ww, hh));
      }
    });
  });

  // ------------------------------------------------------------------
  // Select
  // ------------------------------------------------------------------
  group('Select fuzz / undersize', () {
    testWidgets('survives undersize container with long options', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 5,
          height: 1,
          child: Select<String>(
            value: 'aa',
            options: const [
              SelectOption(value: 'aa', label: 'a-very-very-long-label'),
            ],
            onChanged: (_) {},
          ),
        ),
      );
      tester.render(size: const CellSize(5, 1));
    });

    testWidgets('fuzz: random options + sizes', (tester) {
      final rng = Random(0x5E1E);
      for (var iter = 0; iter < 15; iter++) {
        final n = 1 + rng.nextInt(8);
        final opts = [
          for (var i = 0; i < n; i++)
            SelectOption<int>(value: i, label: _word(rng, min: 1, max: 12)),
        ];
        final ww = 4 + rng.nextInt(30);
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: 1,
            child: Select<int>(
              value: opts[rng.nextInt(n)].value,
              options: opts,
              onChanged: (_) {},
            ),
          ),
        );
        tester.render(size: CellSize(ww, 1));
      }
    });
  });

  // ------------------------------------------------------------------
  // Stepper / NumberInput / RangeSlider — form inputs from tier 2.
  // ------------------------------------------------------------------
  group('Stepper fuzz / undersize', () {
    testWidgets('survives narrow container with a long label', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 4,
          height: 1,
          child: Stepper(
            value: 42,
            label: 'a-very-long-quantity-label',
            onChanged: (_) {},
          ),
        ),
      );
      tester.render(size: const CellSize(4, 1));
    });

    testWidgets('fuzz: random values + bounds + sizes', (tester) {
      final rng = Random(0x57E9);
      for (var iter = 0; iter < 20; iter++) {
        final ww = 2 + rng.nextInt(30);
        final hasMin = rng.nextBool();
        final hasMax = rng.nextBool();
        final v = rng.nextDouble() * 200 - 100;
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: 1,
            child: Stepper(
              value: v,
              min: hasMin ? -100 : null,
              max: hasMax ? 100 : null,
              onChanged: (_) {},
            ),
          ),
        );
        tester.render(size: CellSize(ww, 1));
      }
    });
  });

  group('NumberInput fuzz / undersize', () {
    testWidgets('survives narrow container', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 2,
          height: 1,
          child: NumberInput(initialValue: 12345),
        ),
      );
      tester.render(size: const CellSize(2, 1));
    });

    testWidgets('fuzz: random initial values + bounds + sizes', (tester) {
      final rng = Random(0x29);
      for (var iter = 0; iter < 20; iter++) {
        final ww = 2 + rng.nextInt(20);
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: 1,
            child: NumberInput(
              initialValue: rng.nextDouble() * 1000 - 500,
              allowDecimal: rng.nextBool(),
              allowNegative: rng.nextBool(),
              min: rng.nextBool() ? -200 : null,
              max: rng.nextBool() ? 200 : null,
            ),
          ),
        );
        tester.render(size: CellSize(ww, 1));
      }
    });
  });

  group('RangeSlider fuzz / undersize', () {
    testWidgets('survives narrow container', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 3,
          height: 1,
          child: RangeSlider(
            values: const (20, 80),
            min: 0,
            max: 100,
            onChanged: (_) {},
          ),
        ),
      );
      tester.render(size: const CellSize(3, 1));
    });

    testWidgets('fuzz: random ranges + sizes', (tester) {
      final rng = Random(0x57E5);
      for (var iter = 0; iter < 25; iter++) {
        final lo = -50.0 + rng.nextDouble() * 50;
        final hi = lo + 1 + rng.nextDouble() * 100;
        final lov = lo + rng.nextDouble() * (hi - lo);
        final hiv = lov + rng.nextDouble() * (hi - lov);
        final ww = 2 + rng.nextInt(40);
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: 1,
            child: RangeSlider(
              values: (lov, hiv),
              min: lo,
              max: hi,
              onChanged: (_) {},
            ),
          ),
        );
        tester.render(size: CellSize(ww, 1));
      }
    });
  });

  group('DatePicker fuzz / undersize', () {
    testWidgets('survives narrow container', (tester) {
      tester.pumpWidget(
        SizedBox(
          width: 6,
          height: 4,
          child: DatePicker(value: DateTime(2024, 3, 15), onChanged: (_) {}),
        ),
      );
      tester.render(size: const CellSize(6, 4));
    });

    testWidgets('fuzz: random dates / bounds / sizes', (tester) {
      final rng = Random(0xDA7E);
      for (var iter = 0; iter < 20; iter++) {
        final y = 2020 + rng.nextInt(10);
        final m = 1 + rng.nextInt(12);
        final d = 1 + rng.nextInt(28);
        final ww = 8 + rng.nextInt(20);
        final hh = 4 + rng.nextInt(8);
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: hh,
            child: DatePicker(
              value: DateTime(y, m, d),
              firstDate: rng.nextBool() ? DateTime(y, m, 1) : null,
              lastDate: rng.nextBool() ? DateTime(y, m, 28) : null,
              weekStartsOn: rng.nextBool()
                  ? CalendarWeekStart.sunday
                  : CalendarWeekStart.monday,
              onChanged: (_) {},
            ),
          ),
        );
        tester.render(size: CellSize(ww, hh));
      }
    });
  });

  // ------------------------------------------------------------------
  // PasswordInput / Switch / ColorPicker / FilePicker — tier-3 widgets.
  // ------------------------------------------------------------------
  group('PasswordInput fuzz / undersize', () {
    testWidgets('fuzz: random text + sizes', (tester) {
      final rng = Random(0xBADD);
      for (var iter = 0; iter < 15; iter++) {
        final ww = 1 + rng.nextInt(30);
        final ctrl = TextEditingController(text: _word(rng, min: 0, max: 20));
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: 1,
            child: PasswordInput(controller: ctrl),
          ),
        );
        tester.render(size: CellSize(ww, 1));
      }
    });
  });

  group('Switch fuzz / undersize', () {
    testWidgets('fuzz: random state + label + sizes', (tester) {
      final rng = Random(0x5511);
      for (var iter = 0; iter < 15; iter++) {
        final ww = 1 + rng.nextInt(20);
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: 1,
            child: Switch(
              value: rng.nextBool(),
              label: rng.nextBool() ? _word(rng, min: 1, max: 10) : null,
              onChanged: (_) {},
            ),
          ),
        );
        tester.render(size: CellSize(ww, 1));
      }
    });
  });

  group('ColorPicker fuzz / undersize', () {
    testWidgets('fuzz: random columns + swatchWidth + sizes', (tester) {
      final rng = Random(0xC07);
      for (var iter = 0; iter < 12; iter++) {
        final ww = 4 + rng.nextInt(30);
        final hh = 1 + rng.nextInt(6);
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: hh,
            child: ColorPicker(
              value: AnsiColor(rng.nextInt(16)),
              columns: 1 + rng.nextInt(8),
              swatchWidth: 1 + rng.nextInt(4),
              onChanged: (_) {},
            ),
          ),
        );
        tester.render(size: CellSize(ww, hh));
      }
    });
  });

  // ------------------------------------------------------------------
  // Autocomplete — wrap state via pumpWidget so its overlay can flow.
  // ------------------------------------------------------------------
  group('Autocomplete fuzz / undersize', () {
    testWidgets('survives narrow container with no matches', (tester) {
      tester.pumpWidget(
        const SizedBox(
          width: 4,
          height: 1,
          child: Autocomplete(options: ['apple', 'apricot', 'banana']),
        ),
      );
      tester.render(size: const CellSize(4, 1));
    });

    testWidgets('fuzz: random option lists', (tester) {
      final rng = Random(0xA17C);
      for (var iter = 0; iter < 12; iter++) {
        final opts = [
          for (var i = 0; i < 1 + rng.nextInt(10); i++)
            _word(rng, min: 1, max: 12),
        ];
        final ww = 4 + rng.nextInt(30);
        final hh = 1 + rng.nextInt(8);
        tester.pumpWidget(
          SizedBox(
            width: ww,
            height: hh,
            child: Autocomplete(options: opts),
          ),
        );
        tester.render(size: CellSize(ww, hh));
      }
    });
  });
}
