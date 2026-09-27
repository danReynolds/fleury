// A float shown through an overlay — a toast, a tooltip, a suggestion list,
// the color picker's hex entry, a Select list, a menu — builds under the
// overlay, and runApp's overlay sits above any Theme the app sets. Each float
// paints the theme where its owner sits, and follows it when it changes.
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _lightSurface = RgbColor(0xF2, 0xF2, 0xF4);
const _darkSurface = RgbColor(0x12, 0x12, 0x14);
const _size = CellSize(40, 12);

/// The fill behind the first on-screen occurrence of [text].
Color? _fillBehind(FleuryTester tester, String text) {
  final lines = tester.renderToString(size: _size, emptyMark: ' ').split('\n');
  final row = lines.indexWhere((line) => line.contains(text));
  expect(row, isNot(-1), reason: '"$text" is on screen');
  final col = lines[row].indexOf(text);
  return tester.render(size: _size).atColRow(col, row).style.background;
}

final class _Capture extends StatelessWidget {
  const _Capture(this.onBuild);

  final void Function(BuildContext context) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(context);
    return const Text('home');
  }
}

final class _Brightness with Notifier {
  bool _light = true;
  bool get light => _light;
  set light(bool value) {
    _light = value;
    notify();
  }
}

Iterable<TextCompletionOption> _provider(TextCompletionRequest request) =>
    const [TextCompletionOption(label: 'checkout')];

/// A float: the widget that owns it, how to open it, and the text it shows.
typedef _Float = ({
  String name,
  Widget Function() owner,
  void Function(FleuryTester tester) open,
  List<String> shows,
});

late BuildContext _toasterContext;

final List<_Float> _floats = [
  (
    name: 'a toast',
    owner: () => Toaster(child: _Capture((c) => _toasterContext = c)),
    open: (_) => Toaster.show(_toasterContext, 'Saved'),
    shows: ['Saved'],
  ),
  (
    name: 'a tooltip',
    owner: () => const Tooltip(
      message: 'Save file',
      child: Focus(autofocus: true, child: Text('Save')),
    ),
    open: (_) {},
    shows: ['Save file'],
  ),
  (
    name: 'autocomplete suggestions',
    owner: () =>
        const Autocomplete(options: ['apple', 'apricot'], autofocus: true),
    open: (tester) => tester.type('ap'),
    shows: ['apricot'],
  ),
  (
    name: 'completions',
    owner: () => CompletionTextInput(provider: _provider, autofocus: true),
    open: (tester) => tester.type('ch'),
    shows: ['checkout'],
  ),
  (
    name: 'the hex entry',
    owner: () => ColorPicker(
      value: const AnsiColor(1),
      autofocus: true,
      onChanged: (_) {},
    ),
    open: (tester) => tester.type('#'),
    shows: ['Hex'],
  ),
  (
    name: 'a Select list',
    owner: () => Select<String>(
      autofocus: true,
      value: 'red',
      options: const [
        SelectOption(value: 'red', label: 'red'),
        SelectOption(value: 'teal', label: 'teal'),
      ],
      onChanged: (_) {},
    ),
    open: (tester) => tester.sendKey(const KeyEvent(KeyCode.enter)),
    shows: ['teal'],
  ),
  (
    name: 'a menu and its submenu',
    owner: () => Menu(
      trigger: const Text('Edit'),
      autofocus: true,
      items: [
        SubMenu(
          label: 'Share',
          items: [MenuItem(label: 'Email', onSelect: () {})],
        ),
      ],
    ),
    open: (tester) => tester
      ..sendKey(const KeyEvent(KeyCode.enter))
      ..sendKey(const KeyEvent(KeyCode.arrowRight)),
    shows: ['Share', 'Email'],
  ),
];

void main() {
  for (final float in _floats) {
    testWidgets('${float.name} paints the theme where its owner sits, and '
        'follows it', (tester) {
      final brightness = _Brightness();
      tester.pumpWidget(
        NotifierBuilder(
          notifier: brightness,
          builder: (_, brightness) => Theme(
            data: brightness.light ? ThemeData.light() : ThemeData.dark(),
            child: float.owner(),
          ),
        ),
      );
      tester.pump();
      float.open(tester);
      tester.pump();
      for (final text in float.shows) {
        expect(_fillBehind(tester, text), _lightSurface, reason: text);
      }

      brightness.light = false;
      tester.pump();

      for (final text in float.shows) {
        expect(_fillBehind(tester, text), _darkSurface, reason: text);
      }
    });
  }
}
