// Every shipped theme has to be usable, complete, and legible. These are
// contracts rather than snapshots: they check properties that would make a
// theme wrong in a way a screenshot wouldn't catch.

import 'dart:io';

import 'package:fleury/fleury_core.dart';
import 'package:fleury_themes/fleury_themes.dart';
import 'package:test/test.dart';

void main() {
  _webSafetyGuard();
  test('the registry is non-empty and every name is unique', () {
    expect(fleuryThemes, isNotEmpty);
    final names = fleuryThemes.map((t) => t.name).toSet();
    expect(names.length, fleuryThemes.length, reason: 'duplicate theme name');
    for (final theme in fleuryThemes) {
      expect(theme.name.trim(), isNotEmpty);
    }
  });

  test('every theme sets the opaque roles explicitly', () {
    // A named palette exists to deliver ITS look. Leaving background/surface/
    // foreground null would mean "use the terminal's own", which silently
    // defeats the point — and `surface` in particular backs dialogs, so a
    // transparent one lets content show through.
    for (final theme in fleuryThemes) {
      final cs = theme.data.colorScheme;
      expect(cs.background, isNotNull, reason: '${theme.name}: background');
      expect(cs.surface, isNotNull, reason: '${theme.name}: surface');
      expect(cs.foreground, isNotNull, reason: '${theme.name}: foreground');
    }
  });

  test('status roles stay distinguishable within a theme', () {
    // error/success/warning carry meaning; if two collide, a status display
    // becomes ambiguous no matter how pretty the palette is.
    for (final theme in fleuryThemes) {
      final cs = theme.data.colorScheme;
      final status = <String, Color>{
        'success': cs.success,
        'warning': cs.warning,
        'error': cs.error,
      };
      final distinct = status.values.toSet();
      expect(
        distinct.length,
        status.length,
        reason: '${theme.name}: status colours collide — $status',
      );
    }
  });

  test('foreground is not the background', () {
    for (final theme in fleuryThemes) {
      final cs = theme.data.colorScheme;
      expect(
        cs.foreground,
        isNot(cs.background),
        reason: '${theme.name}: invisible text',
      );
    }
  });

  test('brightness matches the palette it describes', () {
    // Solarized ships both; everything else here is dark. Brightness drives
    // the surface fallback and `context.adaptive`, so a wrong value is a real
    // bug rather than metadata.
    for (final theme in fleuryThemes) {
      final expected = theme.name.toLowerCase().contains('light')
          ? Brightness.light
          : Brightness.dark;
      expect(theme.data.brightness, expected, reason: theme.name);
    }
  });

  test('themes are const, so they cost nothing to hold', () {
    // A regression here would mean someone made a theme non-const, which
    // turns a compile-time constant into per-use allocation.
    const held = <ThemeData>[nord, dracula, tokyoNight, solarizedLight];
    expect(held, hasLength(4));
  });
}

/// Themes are data, so they must work on every surface Fleury renders to —
/// including the browser, where `fleury serve` and the docs-site examples run.
///
/// Importing the native `package:fleury/fleury.dart` umbrella instead of
/// `fleury_core` pulls in the POSIX drivers and package:stdio's FFI, which
/// fails dart2js with "Only JS interop members may be 'external'". That is not
/// a hypothetical: it broke the docs-site compile the first time this package
/// was wired up, and the failure surfaces two packages away from the cause.
void _webSafetyGuard() {
  test('the package never imports the native umbrella', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains("package:fleury/fleury.dart")) {
        offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'import package:fleury/fleury_core.dart instead — the native '
          'umbrella breaks the web build',
    );
  });
}
