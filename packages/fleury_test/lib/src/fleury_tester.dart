import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart' as support;
import 'package:meta/meta.dart';
import 'package:test/test.dart' as pkg_test;

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
