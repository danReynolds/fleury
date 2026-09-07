// Live element-owned dependency storage, including SDK sets omitted from
// Fleury-class-only inventories. Self-inspection occurs after the heap sample.
// dart --deterministic --enable-vm-service=0 --disable-service-auth-codes \
//   bin/dependency_storage_probe.dart [dashboard|agent|files|finance|editor]
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'sample_frame_host.dart';

Future<void> main(List<String> args) async {
  final name = args.isEmpty ? 'dashboard' : args.first;
  final Widget app = switch (name) {
    'dashboard' => const DashboardApp(),
    'agent' => const AgentApp(),
    'files' => const FileManagerApp(),
    'finance' => const FinanceApp(),
    'editor' => const EditorApp(),
    _ => throw ArgumentError(name),
  };
  final server = (await developer.Service.getInfo()).serverUri!;
  final service = await vmServiceConnectUri(server.replace(
    scheme: 'ws',
    pathSegments: [...server.pathSegments.where((s) => s.isNotEmpty), 'ws'],
  ).toString());
  final host = SampleFrameHost(app, const CellSize(120, 40));
  try {
    final isolate = (await service.getVM()).isolates!.first.id!;
    for (var i = 0; i < 300; i++) host.frame('leaf', i);
    final elements = <Element>[];
    void visit(Element element) {
      elements.add(element);
      element.visitChildren(visit);
    }

    visit(host.tester.root!);
    final profile = await service.getAllocationProfile(isolate, gc: true);
    final classes = [
      for (final m in profile.members!)
        if ((m.instancesCurrent ?? 0) > 0 &&
            ((m.classRef?.library?.uri ?? '').startsWith('package:fleury') ||
                ['_Set', '_Map', '_List', '_GrowableList']
                    .contains(m.classRef?.name)))
          {
            'class': m.classRef!.name,
            'library': m.classRef!.library?.uri,
            'bytes': m.bytesCurrent,
            'instances': m.instancesCurrent
          }
    ];
    final storage = <String, Map<String, int>>{};
    var elementShallowBytes = 0;
    for (final element in elements) {
      final object = await service.getObject(
          isolate, developer.Service.getObjectId(element)!) as Instance;
      elementShallowBytes += object.json!['size'] as int;
      for (final field in object.fields ?? const <BoundField>[]) {
        final fieldName = field.decl!.name!;
        if (!['_inheritedDependencies', '_externalDependencies', '_dependents']
            .contains(fieldName)) continue;
        final stats = storage.putIfAbsent(
            fieldName,
            () => {
                  'owners': 0,
                  'allocatedSets': 0,
                  'emptySets': 0,
                  'entries': 0,
                  'setShallowBytes': 0,
                  'emptySetShallowBytes': 0,
                });
        stats['owners'] = stats['owners']! + 1;
        final ref = field.value as InstanceRef;
        if (ref.kind == InstanceKind.kNull) continue;
        final set = await service.getObject(isolate, ref.id!) as Instance;
        final length = set.length;
        if (length == null) throw StateError('No set length: ${set.json}');
        stats['allocatedSets'] = stats['allocatedSets']! + 1;
        final size = set.json!['size'] as int;
        stats['setShallowBytes'] = stats['setShallowBytes']! + size;
        if (length == 0) {
          stats['emptySets'] = stats['emptySets']! + 1;
          stats['emptySetShallowBytes'] = stats['emptySetShallowBytes']! + size;
        }
        stats['entries'] = stats['entries']! + length;
      }
    }
    stdout.writeln(jsonEncode({
      'app': name,
      'elements': elements.length,
      'renderObjects': host.renderObjects.length,
      'dependencyStorage': storage,
      'heap': profile.memoryUsage?.toJson(),
      'classes': classes,
      'elementShallowBytes': elementShallowBytes,
      'dart': Platform.version,
    }));
  } finally {
    host.tester.dispose();
    await service.dispose();
  }
}
