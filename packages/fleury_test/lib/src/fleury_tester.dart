import 'dart:async';

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_test_support.dart' as support;
import 'package:meta/meta.dart';
import 'package:test/test.dart' as pkg_test;

part 'fleury_target.dart';
part 'target_matchers.dart';

Never _throwTestFailure(String message) {
  throw pkg_test.TestFailure(message);
}

/// Drives a Fleury widget tree with deterministic time and test-native
/// assertion failures.
class FleuryTester extends support.FleuryTester {
  FleuryTester({
    super.animationPolicy,
    super.viewportSize,
    super.colorMode,
    super.glyphTier,
    super.images,
    super.textPolicy,
    super.overlayRepaintBoundaries,
    super.clipboard,
  }) : super(failureHandler: _throwTestFailure);

  /// A reusable widget scope or semantic-control query. See [FleuryTarget].
  FleuryTarget target({
    Type? type,
    Key? key,
    support.SemanticRole? role,
    String? label,
    support.SemanticNodeId? id,
  }) => FleuryTarget._create(this, null, type, key, role, label, id);

  /// Finds a button by its exact semantic label.
  FleuryTarget button(String label) =>
      target(role: support.SemanticRole.button, label: label);

  /// Finds an editable-text control, including read-only/disabled fields.
  FleuryTarget field(String label) =>
      FleuryTarget._(this, label: label, textField: true);

  /// Finds a checkbox by its exact semantic label.
  FleuryTarget checkbox(String label) =>
      target(role: support.SemanticRole.checkbox, label: label);

  /// Invokes an action and fails the test if it cannot complete.
  ///
  /// Use [allowFailure] only when asserting an expected rejection or callback
  /// failure. The package-neutral harness keeps its result-returning contract.
  /// Default diagnostics omit value/validation-error selectors and handler
  /// messages, which may contain input. With [allowFailure], the result retains
  /// its original error.
  @override
  Future<support.SemanticActionInvocationResult> invokeSemanticAction(
    support.SemanticAction action, {
    support.SemanticNode? node,
    support.SemanticNodeId? id,
    support.SemanticRole? role,
    String? label,
    Object? value,
    Object? payload,
    bool? focused,
    bool? selected,
    bool? enabled,
    bool? checked,
    bool? busy,
    String? validationError,
    bool allowFailure = false,
  }) async {
    final result = await super.invokeSemanticAction(
      action,
      node: node,
      id: id,
      role: role,
      label: label,
      value: value,
      payload: payload,
      focused: focused,
      selected: selected,
      enabled: enabled,
      checked: checked,
      busy: busy,
      validationError: validationError,
    );
    if (!result.completed && !allowFailure) {
      final target = <String, Object?>{
        'node': ?node,
        'id': ?id,
        'role': ?role?.name,
        'label': ?label,
        if (value != null) 'value': '<redacted>',
        'focused': ?focused,
        'selected': ?selected,
        'enabled': ?enabled,
        'checked': ?checked,
        'busy': ?busy,
        if (validationError != null) 'validationError': '<redacted>',
      };
      final queryFailed =
          result.status == support.SemanticActionInvocationStatus.notFound ||
          result.status == support.SemanticActionInvocationStatus.ambiguous;
      final details = queryFailed && result.error is support.SemanticQueryError
          ? result.error.toString()
          : [
              if (result.node != null) 'Target: ${result.node}',
              if (result.error != null)
                'Handler error: ${result.error.runtimeType}. '
                    'Use allowFailure: true to inspect the original error.',
              _failureTreeSummary(),
            ].join('\n');
      _throwTestFailure(
        'Semantic action ${action.name} for $target did not complete: '
        '${result.status.name}.\n$details',
      );
    }
    return result;
  }

  String _failureTreeSummary() {
    if (root == null) return 'No widget is mounted.';
    final lines = semantics().debugTree(includeState: false).split('\n');
    return [
      ...lines.take(60),
      if (lines.length > 60) '… ${lines.length - 60} more lines',
    ].join('\n');
  }
}

/// Registers a package:test test with a fresh, automatically disposed tester.
@isTest
void testWidgets(
  String description,
  FutureOr<void> Function(FleuryTester tester) body, {
  AnimationPolicy animationPolicy = AnimationPolicy.enabled,
  CellSize viewportSize = const CellSize(80, 24),
  ColorMode colorMode = ColorMode.truecolor,
  GlyphTier glyphTier = GlyphTier.unicode,
  InlineImageSupport images = InlineImageSupport.none,
  TextPresentationPolicy textPolicy = TextPresentationPolicy.spec,
  bool overlayRepaintBoundaries = true,
  pkg_test.Timeout? timeout,
  Object? skip,
}) {
  pkg_test.test(
    description,
    () async {
      final tester = FleuryTester(
        animationPolicy: animationPolicy,
        viewportSize: viewportSize,
        colorMode: colorMode,
        glyphTier: glyphTier,
        images: images,
        textPolicy: textPolicy,
        overlayRepaintBoundaries: overlayRepaintBoundaries,
      );
      try {
        await body(tester);
      } finally {
        tester.dispose();
      }
    },
    timeout: timeout,
    skip: skip,
  );
}

/// The width policy a terminal whose probe measured ambiguous glyphs two
/// cells wide reports (RFC 0019) — the default state of roughly 19 of 30
/// surveyed terminals, including the macOS, GNOME and VS Code defaults.
const TextPresentationPolicy ambiguousWidePolicy = TextPresentationPolicy(
  widths: CellWidthPolicy.cjk,
);

/// Registers [body] TWICE — once on a [TextPresentationPolicy.spec] surface
/// and once on an [ambiguousWidePolicy] one — and hands it the policy in
/// force so it can state the expectation for each.
///
/// Use it for any subject whose painting involves an East Asian Ambiguous
/// glyph (box-drawing edges, the `…` ellipsis, the scrollbar thumb, CJK
/// content) or a scratch-buffer replay. Plain [testWidgets] runs on spec
/// only, where every one of those measures a single cell, so it cannot see a
/// width bug that only exists off spec.
@isTestGroup
void testWidgetsOnBothTextPolicies(
  String description,
  FutureOr<void> Function(FleuryTester tester, TextPresentationPolicy policy)
  body, {
  AnimationPolicy animationPolicy = AnimationPolicy.enabled,
  CellSize viewportSize = const CellSize(80, 24),
  ColorMode colorMode = ColorMode.truecolor,
  GlyphTier glyphTier = GlyphTier.unicode,
  InlineImageSupport images = InlineImageSupport.none,
  bool overlayRepaintBoundaries = true,
  pkg_test.Timeout? timeout,
  Object? skip,
}) {
  const cases = <String, TextPresentationPolicy>{
    'spec': TextPresentationPolicy.spec,
    'ambiguous-wide': ambiguousWidePolicy,
  };
  for (final entry in cases.entries) {
    testWidgets(
      '$description [${entry.key}]',
      (tester) => body(tester, entry.value),
      animationPolicy: animationPolicy,
      viewportSize: viewportSize,
      colorMode: colorMode,
      glyphTier: glyphTier,
      images: images,
      textPolicy: entry.value,
      overlayRepaintBoundaries: overlayRepaintBoundaries,
      timeout: timeout,
      skip: skip,
    );
  }
}
