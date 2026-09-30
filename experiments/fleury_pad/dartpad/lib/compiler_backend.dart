import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';

import 'package:dart_services/src/caching.dart';
import 'package:dart_services/src/common_server.dart';
import 'package:dart_services/src/project_templates.dart';
import 'package:dart_services/src/sdk.dart';
import 'package:path/path.dart' as path;

/// The build-time starter and live requests use exactly the same template.
CommonServerApi createCompilerBackend(String root, String sdkPath) {
  final build = path.join(root, '.build');
  ProjectTemplates.instance = ProjectTemplates.custom(
    projectPath: path.join(build, 'project'),
    bootstrapSource: File(
      path.join(root, 'lib/bootstrap.dart'),
    ).readAsStringSync(),
    summaries: [path.join(build, 'deps.dill')],
    packages: {'fleury', 'fleury_web', 'fleury_widgets', 'http', 'image'},
  );
  return CommonServerApi(
    CommonServerImpl(Sdk.fromDartSdk(sdkPath), NoopCache()),
  );
}

/// Reuse DartPad's scheduler and workers for a validated, self-contained project.
/// This adapter keeps the upstream single-file HTTP protocol unchanged.
Future<Response> handleProject(
  CommonServerApi api,
  String method,
  Map<String, dynamic> payload,
) async {
  final files = Map<String, String>.from(payload['files'] as Map);
  final source = files['main.dart']!;
  final active = payload['activeFile'] as String;
  final overlays = {
    for (final entry in files.entries) 'lib/${entry.key}': entry.value,
  };
  final analyzer = api.impl.analyzer.analysisServer;
  return api.serialize(() async {
    Object result;
    if (method.startsWith('compile')) {
      final compiled = method == 'compileNewDDCReload'
          ? await api.impl.compiler.compileNewDDCReload(
              source,
              payload['deltaDill'] as String,
              files: files,
            )
          : await api.impl.compiler.compileNewDDC(source, files: files);
      if (!compiled.hasOutput) {
        final analysis = await analyzer.analyzeFiles(overlays);
        final issues = (analysis['issues'] as List)
            .where((issue) => issue['kind'] == 'error')
            .toList();
        for (final issue in issues) {
          issue['file'] = (issue['file'] as String).substring(4);
        }
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Could not compile the project. Check the source errors.',
            'issues': issues,
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      result = {'result': compiled.compiledJS, 'deltaDill': compiled.deltaDill};
    } else if (method == 'analyze') {
      final analysis = await analyzer.analyzeFiles(overlays);
      for (final issue in analysis['issues'] as List) {
        issue['file'] = (issue['file'] as String).substring(4);
      }
      result = analysis;
    } else if (method == 'complete') {
      result = (await analyzer.complete(
        files[active]!,
        payload['offset'] as int,
        files: overlays,
        activeFile: 'lib/$active',
      )).toJson();
    } else if (method == 'document') {
      result = (await analyzer.dartdoc(
        files[active]!,
        payload['offset'] as int,
        files: overlays,
        activeFile: 'lib/$active',
      )).toJson();
    } else {
      result = (await analyzer.format(
        files[active]!,
        payload['offset'] as int?,
      )).toJson();
    }
    return Response.ok(
      jsonEncode(result),
      headers: {'content-type': 'application/json'},
    );
  });
}
