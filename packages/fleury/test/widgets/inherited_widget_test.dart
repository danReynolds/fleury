import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _Theme extends InheritedWidget {
  const _Theme({required this.color, required super.child});
  final int color;

  static _Theme of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Theme>()!;

  @override
  bool updateShouldNotify(_Theme oldWidget) => color != oldWidget.color;
}

class _Reader extends StatefulWidget {
  const _Reader({required this.log});
  final List<String> log;
  @override
  State<_Reader> createState() => _ReaderState();
}

class _ReaderState extends State<_Reader> {
  @override
  Widget build(BuildContext context) {
    final theme = _Theme.of(context);
    widget.log.add('build:${theme.color}');
    return const EmptyBox();
  }
}

// A stateful provider lets us mutate the inherited value in place via
// setState (rather than swapping the whole widget tree, which would
// rebuild the dependent via normal reconciliation regardless of the
// updateShouldNotify return value).
class _ThemeProvider extends StatefulWidget {
  const _ThemeProvider({required this.child});
  final Widget child;
  @override
  State<_ThemeProvider> createState() => _ThemeProviderState();
}

class _ThemeProviderState extends State<_ThemeProvider> {
  int color = 1;
  void setColor(int c) => setState(() => color = c);

  @override
  Widget build(BuildContext context) {
    return _Theme(color: color, child: widget.child);
  }
}

void main() {
  group('InheritedWidget', () {
    test('descendant reads value via dependOn...OfExactType', () {
      final owner = BuildOwner();
      final log = <String>[];
      owner.mountRoot(_Theme(color: 7, child: _Reader(log: log)));
      expect(log, ['build:7']);
    });

    test('updateShouldNotify=true triggers dependent rebuild via setState '
        'in an ancestor', () {
      final owner = BuildOwner();
      final log = <String>[];
      final reader = _Reader(log: log);
      final root =
          owner.mountRoot(_ThemeProvider(child: reader)) as StatefulElement;
      log.clear();

      final providerState = root.state as _ThemeProviderState;
      providerState.setColor(2);
      owner.flushBuild();

      expect(log, ['build:2']);
    });

    test('updateShouldNotify=false does NOT rebuild dependent', () {
      final owner = BuildOwner();
      final log = <String>[];
      final reader = _Reader(log: log);
      final root =
          owner.mountRoot(_ThemeProvider(child: reader)) as StatefulElement;
      log.clear();

      final providerState = root.state as _ThemeProviderState;
      providerState.setColor(
        1,
      ); // same value — updateShouldNotify returns false
      owner.flushBuild();

      expect(
        log,
        isEmpty,
        reason: 'No-change update must not rebuild dependents.',
      );
    });

    test(
      'getInheritedWidgetOfExactType reads without registering dependency',
      () {
        final owner = BuildOwner();
        final log = <String>[];
        final reader = _NonDependentReader(log: log);
        final root =
            owner.mountRoot(_ThemeProvider(child: reader)) as StatefulElement;
        log.clear();

        final providerState = root.state as _ThemeProviderState;
        providerState.setColor(2);
        owner.flushBuild();

        // Reader read the theme but did NOT register; it should not rebuild.
        expect(log, isEmpty);
      },
    );
  });
}

class _NonDependentReader extends StatefulWidget {
  const _NonDependentReader({required this.log});
  final List<String> log;
  @override
  State<_NonDependentReader> createState() => _NonDependentReaderState();
}

class _NonDependentReaderState extends State<_NonDependentReader> {
  @override
  Widget build(BuildContext context) {
    final theme = context.getInheritedWidgetOfExactType<_Theme>()!;
    widget.log.add('build:${theme.color}');
    return const EmptyBox();
  }
}
