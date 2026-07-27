// Generator for the renderer's character-width tables.
//
// Fleury's width model used to be hand-written range checks, self-described as
// "pragmatic excerpts" of UAX #11. That is the one thing no mature width
// library does — wcwidth, go-runewidth, unicode-width, utf8proc, Rich and
// Ruby's unicode-display_width all generate from the Unicode Character
// Database and check the result in. Hand-maintained ranges rot silently and
// wrongly: a blanket "U+2500..U+25FF is Ambiguous" is wrong for a third of that
// block, and a blanket "Dingbats are wide" desynced whole frames.
//
// So: this fetches the UCD, derives the four tables the resolver needs, and
// emits them. Deliberate deviations from the raw data live in ONE place
// (_curate) and each says why — the same generated-base + thin-curated-layer
// shape utf8proc and Ratatui use.
//
//     dart run tool/fleury_dev.dart build-width-tables
//
// Network is required to regenerate (the UCD is fetched from unicode.org), but
// NOT to verify: `--check` recomputes the fingerprint from the committed file
// and the generator's own source, so CI catches a hand-edited table or a
// generator change without a rebuild, offline.

// Run directly, or via `dart run tool/fleury_dev.dart build-width-tables`.
// fleury_dev SPAWNS this script rather than importing it: fleury_dev must stay
// a single self-contained file, because it is the bootstrap launcher and has to
// run before the workspace has package resolution (dev_cli_contract_test copies
// it alone into a temp dir and expects it to work).

import 'dart:convert';
import 'dart:io';

/// The Unicode release these tables are pinned to.
///
/// Bumping this is a deliberate decision, not a maintenance chore: every
/// release since 8.0 has widened codepoints, and deployed terminals span
/// roughly Unicode 12.1 through 17.0 simultaneously, so "newest" is not the
/// same as "most compatible". Change it, regenerate, and run the perf gates.
const String unicodeVersion = '17.0.0';

const String _ucdBase = 'https://www.unicode.org/Public/$unicodeVersion/ucd';

Future<void> main(List<String> args) async {
  // <root>/tool/ucd_width_tables.dart -> <root>
  final root = File.fromUri(Platform.script).parent.parent.path;
  final target = File('$root/packages/fleury/lib/src/rendering/width_tables.dart');
  final generatorSource = File.fromUri(Platform.script).readAsStringSync();

  if (args.contains('--check')) {
    exit(_check(target, generatorSource));
  }

  stdout.writeln('fetching Unicode $unicodeVersion data files…');
  final client = HttpClient();
  try {
    final out = await generateWidthTables(
      generatorSource: generatorSource,
      fetch: (url) async {
        final response = await (await client.getUrl(Uri.parse(url))).close();
        if (response.statusCode != 200) {
          throw StateError('GET $url failed: HTTP ${response.statusCode}');
        }
        return response.transform(utf8.decoder).join();
      },
    );
    target.writeAsStringSync(out);
    stdout.writeln(
      'wrote ${target.path} (Unicode $unicodeVersion, ${out.length} bytes)',
    );
  } finally {
    client.close();
  }
}

/// Offline freshness verification. Returns a process exit code.
///
/// Deliberately needs no network: regenerating requires the UCD, but CI has to
/// be able to answer "was this hand-edited, or is the generator newer than the
/// tables?" without it.
int _check(File target, String generatorSource) {
  const rerun = 'Run: dart run tool/fleury_dev.dart build-width-tables';
  if (!target.existsSync()) {
    stderr.writeln('width tables missing: ${target.path}\n$rerun');
    return 1;
  }
  final content = target.readAsStringSync();
  final split = content.indexOf(tablesSentinel);
  if (split < 0) {
    stderr.writeln(
      'width tables file is malformed: missing the tables delimiter.\n$rerun',
    );
    return 1;
  }
  final version = _stringConst(content, 'widthTablesUnicodeVersion');
  if (version != unicodeVersion) {
    stderr.writeln(
      'width tables are pinned to Unicode $version but the generator declares '
      '$unicodeVersion.\n$rerun',
    );
    return 1;
  }
  final committed = _stringConst(content, 'widthTablesFingerprint');
  final current = computeFingerprint(
    generatorSource: generatorSource,
    tableBody: content.substring(split + tablesSentinel.length).trim(),
  );
  if (committed != current) {
    stderr.writeln(
      'width tables are STALE: committed fingerprint "$committed" != current '
      '"$current".\nEither the generator changed or the tables were '
      'hand-edited.\n$rerun',
    );
    return 1;
  }
  stdout.writeln(
    'width tables in sync (Unicode $version, fingerprint $current).',
  );
  return 0;
}

/// Value of a top-level `const String <name> = '...';`, or '' if absent.
String _stringConst(String content, String name) =>
    RegExp("$name = '([^']*)'").firstMatch(content)?.group(1) ?? '';

/// Width classes, in the shape [DefaultWidthResolver] consumes.
const int _narrow = 0;
const int _zero = 1;
const int _wide = 2;
const int _ambiguous = 3;

const int _maxCodePoint = 0x110000;

/// Generates the tables and returns the file content. [fetch] is injected so
/// the generator can be exercised without network.
Future<String> generateWidthTables({
  required Future<String> Function(String url) fetch,
  required String generatorSource,
}) async {
  final eaw = await fetch('$_ucdBase/EastAsianWidth.txt');
  final unicodeData = await fetch('$_ucdBase/UnicodeData.txt');
  final emoji = await fetch('$_ucdBase/emoji/emoji-data.txt');

  final classes = Uint8Buffer(_maxCodePoint);
  _applyCategories(unicodeData, classes);
  _applyEastAsianWidth(eaw, classes);
  _curate(classes);

  final tables = <String, List<int>>{
    'zeroWidthRanges': _rangesFor(classes, _zero),
    'wideRanges': _rangesFor(classes, _wide),
    'ambiguousRanges': _rangesFor(classes, _ambiguous),
    'emojiPresentationRanges': _coalesce(
      _emojiProperty(emoji, 'Emoji_Presentation'),
    ),
    // Sequence-parsing properties (RFC 0019 §6.4). Extended_Pictographic is
    // what UAX #29 GB11 keys ZWJ-sequence clustering on: a ZWJ-delimited
    // segment whose base carries it is an emoji sequence component; a ZWJ in
    // text whose neighbours don't (Arabic, Indic) is shaping-significant and
    // must never be touched by display lowering.
    'extendedPictographicRanges': _coalesce(
      _emojiProperty(emoji, 'Extended_Pictographic'),
    ),
    // Skin-tone modifiers attach to the preceding base; a component is split
    // at ZWJ boundaries only, never between a base and its modifier.
    'emojiModifierRanges': _coalesce(_emojiProperty(emoji, 'Emoji_Modifier')),
  };

  final body = StringBuffer();
  tables.forEach((name, ranges) {
    body.writeln(_emitTable(name, ranges));
  });

  final fingerprint = computeFingerprint(
    generatorSource: generatorSource,
    tableBody: body.toString(),
  );

  return '''// GENERATED — do not edit by hand.
//
// Character-width tables derived from the Unicode Character Database
// $unicodeVersion. Regenerate with:
//
//     dart run tool/fleury_dev.dart build-width-tables
//
// Each table is a flat list of INCLUSIVE [start, end] code-point pairs, sorted
// and coalesced, searched by [lookupRange] in width_resolver.dart. The
// freshness gate (width_tables_test) recomputes [widthTablesFingerprint] from
// this file plus the generator's own source, so a hand-edited table or a
// generator change without a rebuild fails offline — no network needed.
//
// Deliberate deviations from the raw UCD are applied by the generator and
// documented there; they are NOT edits to make here.

/// The Unicode release these tables were generated from.
const String widthTablesUnicodeVersion = '$unicodeVersion';

/// Hash of the generator source plus the emitted tables. See the freshness gate.
const String widthTablesFingerprint = '$fingerprint';

$tablesSentinel
$body''';
}

/// Delimiter between the generated header and the emitted tables. The
/// freshness gate splits on it to recompute the fingerprint over exactly the
/// bytes the generator hashed.
const String tablesSentinel = '// ---- tables ----';

/// The fingerprint the `--check` gate compares. Deliberately covers BOTH the
/// generator's logic and the emitted data, so either drifting alone is caught.
String computeFingerprint({
  required String generatorSource,
  required String tableBody,
}) {
  // A plain FNV-1a over the normalized inputs — this is a staleness tripwire,
  // not a security boundary, and avoiding `package:crypto` keeps the dev tool
  // dependency-free.
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  final bytes = utf8.encode(
    '$unicodeVersion '
    '${_normalize(generatorSource)} '
    '${_normalize(tableBody)}',
  );
  for (final b in bytes) {
    hash = ((hash ^ b) * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// Line-ending and trailing-whitespace normalization, so the gate does not go
/// red on a checkout that rewrote CRLFs.
String _normalize(String s) => s
    .replaceAll('\r\n', '\n')
    .split('\n')
    .map((l) => l.trimRight())
    .join('\n')
    .trim();

// ---- UCD parsing ---------------------------------------------------------

/// General categories that occupy no cell. Matches the set utf8proc derives
/// (Mn/Me/Cf/Cc/Cs/Zl/Zp); combining marks, format controls, surrogates and
/// line/paragraph separators all advance the cursor zero columns.
const Set<String> _zeroWidthCategories = <String>{
  'Mn',
  'Me',
  'Cf',
  'Cc',
  'Cs',
  'Zl',
  'Zp',
};

void _applyCategories(String unicodeData, Uint8Buffer classes) {
  // UnicodeData.txt encodes large blocks as a "<..., First>" / "<..., Last>"
  // pair rather than one line per code point.
  int? rangeStart;
  for (final line in const LineSplitter().convert(unicodeData)) {
    if (line.isEmpty) continue;
    final f = line.split(';');
    if (f.length < 3) continue;
    final code = int.parse(f[0], radix: 16);
    final name = f[1];
    final category = f[2];
    if (name.endsWith(', First>')) {
      rangeStart = code;
      continue;
    }
    final start = name.endsWith(', Last>') ? (rangeStart ?? code) : code;
    rangeStart = null;
    if (!_zeroWidthCategories.contains(category)) continue;
    for (var c = start; c <= code; c++) {
      classes[c] = _zero;
    }
  }
}

void _applyEastAsianWidth(String eaw, Uint8Buffer classes) {
  for (final entry in _parseRanges(eaw)) {
    final value = entry.value;
    final int cls;
    if (value == 'W' || value == 'F') {
      cls = _wide;
    } else if (value == 'A') {
      cls = _ambiguous;
    } else {
      continue; // N / Na / H stay narrow.
    }
    for (var c = entry.start; c <= entry.end; c++) {
      // Zero-width wins: a combining mark inside a Wide block still advances
      // nothing. UAX #11 §6.2 says EAW for combining marks is not their
      // display width.
      if (classes[c] == _zero) continue;
      classes[c] = cls;
    }
  }
}

/// Code points carrying [property] in emoji-data.txt, sorted ascending.
List<int> _emojiProperty(String emoji, String property) {
  final flags = Uint8Buffer(_maxCodePoint);
  for (final entry in _parseRanges(emoji)) {
    if (entry.value != property) continue;
    for (var c = entry.start; c <= entry.end; c++) {
      flags[c] = 1;
    }
  }
  final out = <int>[];
  for (var c = 0; c < _maxCodePoint; c++) {
    if (flags[c] == 1) out.add(c);
  }
  return out;
}

/// Shared parser for the `code[..code] ; VALUE # comment` UCD line shape used
/// by EastAsianWidth.txt and emoji-data.txt.
Iterable<_UcdRange> _parseRanges(String content) sync* {
  for (var line in const LineSplitter().convert(content)) {
    final hash = line.indexOf('#');
    if (hash >= 0) line = line.substring(0, hash);
    line = line.trim();
    if (line.isEmpty) continue;
    final parts = line.split(';');
    if (parts.length < 2) continue;
    final codes = parts[0].trim();
    final value = parts[1].trim();
    final dots = codes.indexOf('..');
    final int start;
    final int end;
    if (dots >= 0) {
      start = int.parse(codes.substring(0, dots), radix: 16);
      end = int.parse(codes.substring(dots + 2), radix: 16);
    } else {
      start = int.parse(codes, radix: 16);
      end = start;
    }
    yield _UcdRange(start, end, value);
  }
}

class _UcdRange {
  _UcdRange(this.start, this.end, this.value);
  final int start;
  final int end;
  final String value;
}

// ---- The curated layer ---------------------------------------------------

/// Deliberate deviations from the raw UCD. Every entry states why, because a
/// generated table with undocumented edits is just a hand-maintained table
/// again.
void _curate(Uint8Buffer classes) {
  // U+00AD SOFT HYPHEN is Cf, so the category pass makes it zero-width, but
  // terminals print it as a visible hyphen. utf8proc carries the same
  // override. (The field is genuinely split — Alacritty/kitty/WezTerm say 0;
  // foot/VTE/xterm/xterm.js say 1 — and 1 preserves Fleury's prior behaviour.)
  classes[0x00AD] = _narrow;

  // Private Use Area is Ambiguous per UAX #11, because a PUA code point may
  // stand for a glyph of any width. In practice every terminal renders it
  // one cell, and Nerd Fonts DEPEND on that: their icons deliberately keep a
  // one-cell advance while the ink overflows, so that patched fonts still
  // measure as monospace. WezTerm's ambiguous-width toggle likewise skips PUA.
  // Treating it as Ambiguous would double-width every Powerline segment and
  // Nerd Font icon under a CJK profile.
  for (final range in const <List<int>>[
    <int>[0xE000, 0xF8FF],
    <int>[0xF0000, 0xFFFFD],
    <int>[0x100000, 0x10FFFD],
  ]) {
    for (var c = range[0]; c <= range[1]; c++) {
      if (classes[c] == _ambiguous) classes[c] = _narrow;
    }
  }
}

// ---- Emission ------------------------------------------------------------

List<int> _rangesFor(Uint8Buffer classes, int cls) {
  final codes = <int>[];
  for (var c = 0; c < _maxCodePoint; c++) {
    if (classes[c] == cls) codes.add(c);
  }
  return _coalesce(codes);
}

/// Sorted code points -> flat inclusive [start, end] pairs.
List<int> _coalesce(List<int> codes) {
  final out = <int>[];
  var i = 0;
  while (i < codes.length) {
    final start = codes[i];
    var end = start;
    while (i + 1 < codes.length && codes[i + 1] == end + 1) {
      end = codes[++i];
    }
    out
      ..add(start)
      ..add(end);
    i++;
  }
  return out;
}

String _emitTable(String name, List<int> ranges) {
  final buf = StringBuffer()
    ..writeln('/// ${ranges.length ~/ 2} inclusive [start, end] code-point pairs.')
    ..writeln('const List<int> $name = <int>[');
  for (var i = 0; i < ranges.length; i += 2) {
    final start = _hex(ranges[i]);
    final end = _hex(ranges[i + 1]);
    buf.writeln('  $start, $end,');
  }
  buf.writeln('];');
  return buf.toString();
}

String _hex(int v) => '0x${v.toRadixString(16).toUpperCase()}';

/// Minimal growable byte buffer — avoids importing dart:typed_data into the
/// generator's public surface for one internal array.
class Uint8Buffer {
  Uint8Buffer(int length) : _data = List<int>.filled(length, 0);
  final List<int> _data;
  int operator [](int i) => _data[i];
  void operator []=(int i, int v) => _data[i] = v;
}
