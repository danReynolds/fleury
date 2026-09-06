// AOT document lifecycle and interaction costs through the real frame loop.
// Fixtures are prepared before timing. Opening includes mounting and first
// frame; other operations include mutation, frame construction/diff and commit.
// Excludes terminal encoding/transport and process/VM startup.
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';

import 'sample_frame_host.dart';

void main(List<String> args) {
  final options = {
    '--kind': 'rich',
    '--lines': '1000',
    '--frames': '60',
    '--operation': 'all',
    '--policy': 'spec'
  };
  for (var i = 0; i < args.length; i += 2) {
    if (i + 1 == args.length || !options.containsKey(args[i])) {
      throw ArgumentError(
          'Expected --kind plain|rich|spans, --lines N, --frames N, --operation NAME');
    }
    options[args[i]] = args[i + 1];
  }
  const operations = [
    'open',
    'rebuild-same',
    'rebuild-equal',
    'edit',
    'resize',
    'drag',
    'copy',
    'copy-all'
  ];
  final operationFilter = options['--operation']!;
  if (operationFilter != 'all' && !operations.contains(operationFilter)) {
    throw ArgumentError('Invalid operation');
  }
  final policyName = options['--policy']!;
  final policy = switch (policyName) {
    'spec' => TextPresentationPolicy.spec,
    'split' => const TextPresentationPolicy(lowering: ClusterLowering.split),
    _ => throw ArgumentError('Invalid text policy'),
  };
  final kind = options['--kind']!;
  final count = int.parse(options['--lines']!);
  final frames = int.parse(options['--frames']!);
  if (!['plain', 'rich', 'spans'].contains(kind) || count < 50 || frames < 2) {
    throw ArgumentError('Invalid workload');
  }
  List<String> lines(int revision) => List.generate(
      count,
      (i) =>
          '${i.toString().padLeft(6, '0')}  INFO  worker accepted request $revision; '
          'elapsed=12ms status=ok 漢字 👩‍💻');
  final documents = [lines(0).join('\n'), lines(1).join('\n')];
  TextSpan span(int revision) => kind == 'spans'
      ? TextSpan(children: [
          for (final (i, line) in lines(revision).indexed)
            TextSpan(
                text: '$line${i == count - 1 ? '' : '\n'}',
                style: CellStyle(foreground: AnsiColor(i % 6 + 1))),
        ])
      : TextSpan(
          text: documents[revision],
          style: const CellStyle(foreground: AnsiColor(6)));
  final spans = [span(0), span(1)];
  // Equal content in distinct span trees exercises the public update path.
  final equalSpans = [span(0), span(0)];
  const size = CellSize(80, 24);
  for (final operation in operations) {
    if (operationFilter != 'all' && operation != operationFilter) continue;
    final controller = ScrollController();
    Widget app(int revision, {TextSpan? text}) => ScrollView(
        controller: controller,
        child: kind == 'plain'
            ? Text(documents[revision])
            : RichText(text: text ?? spans[revision]));
    SampleFrameHost? host;
    if (operation != 'open') {
      host = SampleFrameHost(app(0), size, textPolicy: policy);
      if (operation == 'drag' ||
          operation == 'copy' ||
          operation == 'copy-all') {
        controller.jumpTo(controller.maxOffset ~/ 2);
        host.frame('clean', 0);
        host.tester.sendMouse(const MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: 0,
            row: 5));
        host.tester.sendMouse(const MouseEvent(
            kind: MouseEventKind.drag,
            button: MouseButton.left,
            col: 20,
            row: 8));
        if (operation == 'copy-all') {
          host.renderObjects
              .whereType<Selectable>()
              .single
              .dispatchSelectionEvent(const SelectionGranularEvent(
                  granularity: SelectionGranularity.all));
        }
        host.frame('clean', 0);
        if (host.renderObjects
                .whereType<Selectable>()
                .single
                .getSelectedContent() ==
            null) {
          throw StateError('The pointer drag must select visible content');
        }
      }
    }
    final times = <int>[];
    var changed = 0;
    var copiedUnits = 0;
    for (var i = -10; i < frames; i++) {
      final watch = Stopwatch()..start();
      if (operation == 'open')
        host = SampleFrameHost(app(0), size, settle: false, textPolicy: policy);
      final current = host!;
      switch (operation) {
        case 'rebuild-same':
          current.tester.pumpWidget(app(0));
        case 'rebuild-equal':
          current.tester.pumpWidget(app(0, text: equalSpans[i & 1]));
        case 'edit':
          current.tester.pumpWidget(app(i & 1));
        case 'resize':
          current.size = CellSize(i.isEven ? 60 : 80, 24);
        case 'drag':
          current.tester.sendMouse(MouseEvent(
              kind: MouseEventKind.drag,
              button: MouseButton.left,
              col: 20 + (i & 1),
              row: 8));
        case 'copy':
        case 'copy-all':
          copiedUnits += current.renderObjects
              .whereType<Selectable>()
              .single
              .getSelectedContent()!
              .plainText
              .length;
      }
      final frame = current.frame('clean', i);
      watch.stop();
      if (i >= 0) {
        times.add(watch.elapsedMicroseconds);
        if (frame.changed) changed++;
      }
      if (operation == 'open' && i < frames - 1) current.tester.dispose();
    }
    final current = host!;
    final buffer = current.tester.render(size: current.size);
    var hash = 2166136261;
    for (var r = 0; r < buffer.size.rows; r++) {
      for (var c = 0; c < buffer.size.cols; c++) {
        final cell = buffer.atColRow(c, r);
        for (final code
            in '${cell.role}|${cell.grapheme}|${cell.style};'.codeUnits) {
          hash = ((hash ^ code) * 16777619) & 0xffffffff;
        }
      }
    }
    times.sort();
    stdout.writeln(jsonEncode({
      'kind': kind,
      'policy': policyName,
      'lines': count,
      'operation': operation,
      'frames': frames,
      'changedFrames': changed,
      'copiedUnits': copiedUnits,
      'fingerprint': hash,
      'medianUs': times[times.length ~/ 2],
      'p95Us': times[(times.length * .95).ceil() - 1],
      'dart': Platform.version
    }));
    current.tester.dispose();
    controller.dispose();
  }
}
