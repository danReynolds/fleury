// One-shot rendering of a richer layout to a PTY, for visual
// verification. Mounts a tree, paints exactly one frame, restores, and
// exits. Use under script(1) to capture the ANSI for offline rendering.

import 'package:fleury/fleury.dart';

Future<void> main() async {
  final driver = PosixTerminalDriver();
  await driver.enter(TerminalMode.interactive);
  final owner = BuildOwner();
  final root = owner.mountRoot(const _ShowcaseApp());
  final buf = CellBuffer(driver.size);
  owner.renderFrame(root, buf);
  final sink = _DriverSink(driver);
  const AnsiRenderer().renderFull(buf, sink);
  // Give the OS time to actually push the bytes through the PTY before
  // we tear it down.
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await driver.restore();
}

class _ShowcaseApp extends StatelessWidget {
  const _ShowcaseApp();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        children: const [
          Text(
            ' fleury showcase ',
            style: CellStyle(
              bold: true,
              foreground: AnsiColor(15),
              background: AnsiColor(4),
            ),
          ),
          Text(''),
          Text('A canonical chat layout in 60 lines of pure Dart:'),
          Text(''),
          SizedBox(
            height: 8,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 20, child: _Sidebar()),
                Expanded(child: _MessagePane()),
              ],
            ),
          ),
          Text(''),
          Text(
            'Layout: Row(SizedBox + Expanded) inside Column inside Padding.',
            style: CellStyle(dim: true),
          ),
          Text(
            'Rendering: integer cell flex, grapheme-aware text, diffed ANSI.',
            style: CellStyle(dim: true),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Text(
          ' Conversations ',
          style: CellStyle(bold: true, foreground: AnsiColor(14)),
        ),
        Text(''),
        Text(
          ' Family            3',
          style: CellStyle(foreground: AnsiColor(2)),
        ),
        Text(' Work'),
        Text(
          ' Climbing crew    12',
          style: CellStyle(foreground: AnsiColor(2)),
        ),
        Text(' Old roommates'),
      ],
    );
  }
}

class _MessagePane extends StatelessWidget {
  const _MessagePane();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Column(
        children: const [
          Text(' Climbing crew', style: CellStyle(bold: true)),
          Text(''),
          Text(
            ' jess   14:02   should we go saturday?',
            style: CellStyle(foreground: AnsiColor(6)),
          ),
          Text(
            ' dan    14:03   yeah, weather looks good',
            style: CellStyle(foreground: AnsiColor(6)),
          ),
          Text(' you    14:05   ill bring the rope'),
          Text(''),
          Text(' > _', style: CellStyle(foreground: AnsiColor(11))),
        ],
      ),
    );
  }
}

class _DriverSink implements AnsiSink {
  _DriverSink(this._d);
  final TerminalDriver _d;
  @override
  void write(String d) => _d.write(d);
  @override
  Future<void> flush() async {}
}
