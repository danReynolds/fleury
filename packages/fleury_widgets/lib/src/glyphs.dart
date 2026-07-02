import 'package:fleury/fleury_core.dart';

/// Shared glyph helpers for the drawing widgets, so each one picks Unicode or
/// ASCII output from a single place rather than carrying its own ramp tables.
///
/// The ASCII tier ([GlyphTier.ascii]) keeps output to 7-bit characters for
/// `TERM=dumb`/`linux`, non-UTF-8 locales, or an explicit override; the Unicode
/// tier uses the block-element ramps. The glyph changes, never the value.

/// A horizontal eighth-block fill at [eighths] (0..8) — the ramp `▏▎▍▌▋▊▉█`.
/// ASCII collapses to `#` (full), `+` (partial), or a space (empty).
String horizontalFillGlyph(GlyphTier tier, int eighths) {
  final clamped = eighths.clamp(0, 8);
  if (tier == GlyphTier.ascii) {
    if (clamped == 0) return ' ';
    return clamped == 8 ? '#' : '+';
  }
  return const [' ', '▏', '▎', '▍', '▌', '▋', '▊', '▉', '█'][clamped];
}

/// The unfilled-track glyph (`░` in Unicode, `.` in ASCII).
String horizontalTrackGlyph(GlyphTier tier) =>
    tier == GlyphTier.ascii ? '.' : '░';

/// A vertical level at [level] (0..8) — the ramp `▁▂▃▄▅▆▇█`, where level 0 is
/// "below baseline, draw nothing" (empty string). ASCII steps `.:-=+*#`.
String verticalLevelGlyph(GlyphTier tier, int level) {
  final clamped = level.clamp(0, 8);
  if (tier == GlyphTier.ascii) {
    return const ['', '.', ':', '-', '=', '+', '*', '#', '#'][clamped];
  }
  return const ['', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'][clamped];
}

/// An ASCII density glyph for sub-cell buffers (braille/quadrant/half-block)
/// that have no 7-bit equivalent: maps the lit/total ratio onto ` .:*#`.
String densityGlyph(GlyphTier tier, int lit, int total) {
  if (tier == GlyphTier.unicode) {
    throw StateError('densityGlyph is only an ASCII fallback helper.');
  }
  if (lit <= 0 || total <= 0) return ' ';
  final ratio = lit / total;
  if (ratio <= 0.25) return '.';
  if (ratio <= 0.5) return ':';
  if (ratio <= 0.75) return '*';
  return '#';
}
