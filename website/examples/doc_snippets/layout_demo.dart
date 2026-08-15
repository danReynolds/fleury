// Compile-checked source behind the Layout guide. It demonstrates fixed and
// flexible space plus a local LayoutBuilder breakpoint.
// Guarded by ../test/doc_snippets_test.dart.

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

void main() => runApp(layoutDemoApp());

Widget layoutDemoApp() =>
    const FleuryApp(title: 'Responsive workspace', home: ResponsiveWorkspace());

class ResponsiveWorkspace extends StatefulWidget {
  const ResponsiveWorkspace({super.key});

  @override
  State<ResponsiveWorkspace> createState() => _ResponsiveWorkspaceState();
}

class _ResponsiveWorkspaceState extends State<ResponsiveWorkspace> {
  var _width = 68;

  Widget _files() => const Panel(
    title: 'Files',
    child: Padding(
      padding: EdgeInsets.all(1),
      child: Text('README.md\nlib/\ntest/'),
    ),
  );

  Widget _preview() => const Panel(
    title: 'Preview',
    child: Padding(
      padding: EdgeInsets.all(1),
      child: Text('# Fleury\n\nA framework for terminal apps.'),
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Button(
              label: 'Narrow',
              autofocus: true,
              onPressed: () => setState(() => _width = 42),
            ),
            const SizedBox(width: 1),
            Button(label: 'Wide', onPressed: () => setState(() => _width = 68)),
          ],
        ),
        const SizedBox(height: 1),
        Expanded(
          child: SizedBox(
            width: _width,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = (constraints.maxCols ?? 0) >= 60;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      wide ? 'WIDE · TWO PANES' : 'NARROW · STACKED',
                      style: const CellStyle(bold: true),
                    ),
                    const SizedBox(height: 1),
                    Expanded(
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: 2, child: _files()),
                                const SizedBox(width: 1),
                                Expanded(flex: 3, child: _preview()),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: _files()),
                                const SizedBox(height: 1),
                                Expanded(child: _preview()),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}
