import 'dart:convert';
import 'dart:io';

import 'package:fleury_doc_examples/registry.dart';

/// Dumps the example registry metadata as JSON so the docs site can generate
/// the widget-reference pages from it. Usage:
///   dart run bin/manifest.dart [out.json]   (defaults to stdout)
void main(List<String> args) {
  final data = <Map<String, Object?>>[
    for (final e in exampleList)
      <String, Object?>{
        'id': e.id,
        'widget': e.widget,
        'category': e.category,
        'blurb': e.blurb,
        'cols': e.cols,
        'rows': e.rows,
      },
  ];
  final json = const JsonEncoder.withIndent('  ').convert(data);
  if (args.isNotEmpty) {
    File(args.first).writeAsStringSync('$json\n');
    stdout.writeln('wrote ${data.length} examples → ${args.first}');
  } else {
    stdout.write(json);
  }
}
