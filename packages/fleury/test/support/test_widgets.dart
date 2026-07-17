import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart' as pkg_test;

Never _throwTestFailure(String message) {
  throw pkg_test.TestFailure(message);
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
        failureHandler: _throwTestFailure,
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
