// Post-GC document ownership across mount, replace, resize and unmount.
// Project-class shallow bytes exclude SDK strings/lists and VM/tool overhead.
// Use --deterministic --enable-vm-service=0 --disable-service-auth-codes.
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:fleury/fleury.dart';
import 'package:vm_service/vm_service_io.dart';

import 'sample_frame_host.dart';

Future<void> main(List<String> args) async {
  final kind = args.isEmpty ? 'rich' : args.single;
  if (!['plain', 'rich', 'spans'].contains(kind))
    throw ArgumentError('Invalid kind');
  const size = CellSize(80, 24);
  final source = List.generate(
      1000, (i) => '$i INFO accepted request; elapsed=12ms status=ok 漢字 👩‍💻');
  final text = source.join('\n');
  Widget app(int revision) => ScrollView(
      child: kind == 'plain'
          ? Text('$revision $text')
          : RichText(
              text: kind == 'spans'
                  ? TextSpan(text: '$revision ', children: [
                      for (final (i, line) in source.indexed)
                        TextSpan(
                            text: '$line${i == source.length - 1 ? '' : '\n'}',
                            style: CellStyle(foreground: AnsiColor(i % 6 + 1))),
                    ])
                  : TextSpan(text: '$revision $text')));
  SampleFrameHost mount() {
    final host = SampleFrameHost(app(0), size, settle: false);
    host.frame('clean', 0);
    host.size = const CellSize(60, 24);
    host.frame('clean', 1);
    host.tester.pumpWidget(app(1));
    host.frame('clean', 2);
    host.renderObjects.whereType<Selectable>().single.dispatchSelectionEvent(
        const SelectionGranularEvent(granularity: SelectionGranularity.all));
    host.frame('clean', 3);
    return host;
  }

  void cycle() {
    final host = mount();
    host.tester.dispose();
  }

  final uri = (await developer.Service.getInfo()).serverUri!;
  final service = await vmServiceConnectUri(uri.replace(
      scheme: 'ws',
      pathSegments: [
        ...uri.pathSegments.where((s) => s.isNotEmpty),
        'ws'
      ]).toString());
  try {
    final isolate = (await service.getVM()).isolates!.first.id!;
    Future<void> snapshot(String phase) async {
      final profile = await service.getAllocationProfile(isolate, gc: true);
      final classes = [
        for (final m in profile.members!)
          if ((m.classRef?.library?.uri ?? '').startsWith('package:fleury') &&
              (m.bytesCurrent ?? 0) > 0)
            {
              'class': m.classRef!.name,
              'library': m.classRef!.library!.uri,
              'instances': m.instancesCurrent,
              'bytes': m.bytesCurrent
            }
      ];
      print(jsonEncode({
        'kind': kind,
        'phase': phase,
        'heap': profile.memoryUsage?.toJson(),
        'classes': classes
      }));
    }

    // Warm the same mutation/lifecycle code before the first empty snapshot.
    for (var i = 0; i < 10; i++) cycle();
    await snapshot('empty-before');
    Future<void> mountedSnapshot() async {
      final host = mount();
      await snapshot('mounted');
      host.tester.dispose();
    }

    await mountedSnapshot();
    await snapshot('released');
    for (var i = 0; i < 50; i++) cycle();
    await snapshot('empty-after-50');
  } finally {
    await service.dispose();
  }
}
