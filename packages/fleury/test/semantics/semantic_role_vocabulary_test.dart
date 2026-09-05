// The core vocabulary is a hand-maintained list beside the constants it lists.
// Nothing at compile time ties the two together, and a constant missing from
// `values` is invisible to every test that iterates `values` — while peers
// (the served client, the MCP bridge) would rebuild that role as `text`. This
// guard reads the source, the same way the widget catalog's drift guard does.
@TestOn('vm')
library;

import 'dart:io';

import 'package:fleury/fleury_core.dart';
import 'package:test/test.dart';

void main() {
  test('every core role constant is listed in SemanticRole.values', () {
    final source = File('lib/src/semantics/semantics.dart').readAsStringSync();
    final declared = RegExp(
      r"SemanticRole\._core\(\s*'(\w+)'",
    ).allMatches(source).map((m) => m.group(1)!).toList();
    expect(declared, isNotEmpty);
    expect(declared.toSet().length, declared.length, reason: 'duplicate name');
    final listed = [for (final role in SemanticRole.values) role.name];
    expect(listed.toSet(), declared.toSet());
    expect(listed.length, declared.length, reason: 'a role listed twice');
    for (final name in declared) {
      expect(SemanticRole.coreByName(name)?.name, name);
    }
  });
}
