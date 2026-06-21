import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Extracts the source of each example's widget so the docs site can show the
/// code that produces the running example. Parses lib/registry.dart, finds each
/// `ExampleInfo(...)`, and pulls its `builder` body verbatim (original
/// formatting preserved), unwrapping the `_framed(...)` theme helper and
/// rewriting the private `_theme` reference to `theme` so it reads like app
/// code. Emits id → code JSON.
///
/// Usage: dart run bin/examples_code.dart [out.json]
void main(List<String> args) {
  final src = File('lib/registry.dart').readAsStringSync();
  final unit = parseString(content: src, throwIfDiagnostics: false).unit;
  final visitor = _Visitor(src);
  unit.accept(visitor);

  final json = const JsonEncoder.withIndent('  ').convert(visitor.out);
  if (args.isNotEmpty) {
    File(args.first).writeAsStringSync('$json\n');
    stdout.writeln('extracted ${visitor.out.length} example snippets → ${args.first}');
  } else {
    stdout.write(json);
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.src);
  final String src;
  final Map<String, String> out = <String, String>{};

  // An unresolved parse treats `ExampleInfo(...)` (no new/const) as a method
  // invocation, so match it here rather than as an instance creation.
  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'ExampleInfo') {
      String? id;
      String? code;
      for (final arg in node.argumentList.arguments) {
        if (arg is! NamedExpression) continue;
        final name = arg.name.label.name;
        if (name == 'id' && arg.expression is StringLiteral) {
          id = (arg.expression as StringLiteral).stringValue;
        } else if (name == 'builder' && arg.expression is FunctionExpression) {
          code = _bodyCode(arg.expression as FunctionExpression);
        }
      }
      if (id != null && code != null) out[id] = code;
    }
    super.visitMethodInvocation(node);
  }

  String _bodyCode(FunctionExpression fn) {
    Expression? expr;
    final body = fn.body;
    if (body is ExpressionFunctionBody) expr = body.expression;
    // Unwrap the docs-only `_framed(widget)` theme wrapper.
    if (expr is MethodInvocation &&
        expr.methodName.name == '_framed' &&
        expr.argumentList.arguments.length == 1) {
      expr = expr.argumentList.arguments.first;
    }
    final node = expr ?? fn;
    final raw = src.substring(node.offset, node.end);
    return _dedent(raw).replaceAll('_theme.', 'theme.');
  }
}

/// Removes the common leading indentation from all but the first line.
String _dedent(String code) {
  final lines = code.split('\n');
  if (lines.length <= 1) return code.trim();
  var min = 1 << 30;
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) continue;
    final indent = line.length - line.trimLeft().length;
    if (indent < min) min = indent;
  }
  if (min == 1 << 30) min = 0;
  final out = <String>[lines.first];
  for (final line in lines.skip(1)) {
    out.add(line.length >= min ? line.substring(min) : line.trimLeft());
  }
  return out.join('\n').trim();
}
