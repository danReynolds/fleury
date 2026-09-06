// Static inventory for the testing-controls proposal. Does not execute tests.
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';

const interestingCalls = {
  'invokeSemanticAction',
  'semantics',
  'press',
  'type',
  'paste',
  'sendMouse',
  'sendKey',
  'sendEvent',
  'pumpWidget',
  'mountWidget',
  'pumpFleuryHome',
  'pump',
  'pumpAndSettle',
  'settle',
  'render',
  'renderToString',
  'exists',
  'find',
  'matchesGolden',
  'requestFocus',
  'jumpTo',
  'animateTo',
  'tap',
  'click',
};

class InventoryVisitor extends RecursiveAstVisitor<void> {
  InventoryVisitor(this.lineAt);
  final int Function(int offset) lineAt;
  final methods = <String, int>{};
  final roles = <String, int>{};
  final actions = <String, int>{};
  final properties = <String, int>{};
  final registrations = <Map<String, Object?>>[];
  final calls = <Map<String, Object?>>[];

  void add(Map<String, int> counts, String name) =>
      counts.update(name, (count) => count + 1, ifAbsent: () => 1);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    add(methods, name);
    final args = node.argumentList.arguments;
    if ({'test', 'testWidgets', 'testNocterm'}.contains(name)) {
      registrations.add({
        'line': lineAt(node.offset),
        'registration': name,
        'description': args.isEmpty ? null : args.first.toSource(),
      });
    }
    if (interestingCalls.contains(name)) {
      final named = <String, String>{};
      final positional = <String>[];
      for (final argument in args) {
        if (argument is NamedExpression) {
          named[argument.name.label.name] = clip(
            argument.expression.toSource(),
          );
        } else {
          positional.add(clip(argument.toSource()));
        }
      }
      calls.add({
        'line': lineAt(node.offset),
        'method': name,
        'receiver': clip(node.target?.toSource() ?? ''),
        if (positional.isNotEmpty) 'positional': positional,
        if (named.isNotEmpty) 'named': named,
      });
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == 'SemanticRole') add(roles, node.identifier.name);
    if (node.prefix.name == 'SemanticAction')
      add(actions, node.identifier.name);
    recordProperty(node.identifier.name);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    recordProperty(node.propertyName.name);
    super.visitPropertyAccess(node);
  }

  void recordProperty(String name) {
    if ({
      'focused',
      'enabled',
      'checked',
      'selected',
      'busy',
      'validationError',
      'value',
      'bounds',
      'actions',
      'state',
    }.contains(name))
      add(properties, name);
  }
}

String clip(String value) =>
    value.length <= 200 ? value : '${value.substring(0, 200)}…';

void main() {
  final listing = Process.runSync('rg', ['--files', 'packages', 'website']);
  if (listing.exitCode != 0) throw StateError(listing.stderr.toString());
  final files =
      (listing.stdout as String)
          .split('\n')
          .where((path) => path.endsWith('_test.dart'))
          .toList()
        ..sort();
  final entries = <Map<String, Object?>>[];
  for (final path in files) {
    final source = File(path).readAsStringSync();
    final parsed = parseString(
      content: source,
      path: path,
      featureSet: FeatureSet.latestLanguageVersion(flags: ['dot-shorthands']),
      throwIfDiagnostics: false,
    );
    final visitor = InventoryVisitor(
      (offset) => parsed.lineInfo.getLocation(offset).lineNumber,
    );
    parsed.unit.accept(visitor);
    entries.add({
      'path': path,
      'lines': '\n'.allMatches(source).length + 1,
      'parser_diagnostics': parsed.errors
          .map((error) => error.toString())
          .toList(),
      'registrations': visitor.registrations,
      'method_counts': visitor.methods,
      'role_references': visitor.roles,
      'action_references': visitor.actions,
      'property_references': visitor.properties,
      'calls': visitor.calls,
    });
  }
  print(
    const JsonEncoder.withIndent('  ').convert({
      'scope':
          'Owned *_test.dart files under packages and website; rg respects ignore rules. Excludes peer fixtures and audit probes.',
      'method':
          'Dart AST syntax inventory, not resolved receiver types or runtime execution. Registrations in loops are counted once at the source call site.',
      'file_count': entries.length,
      'files': entries,
    }),
  );
}
