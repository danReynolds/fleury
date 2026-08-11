import 'dart:async';
import '../input/keyboard_state.dart';

import 'package:meta/meta.dart';

import 'capabilities.dart';
import 'capability_requirements.dart';

/// Outcome for an explicit, opt-in terminal capability probe.
enum TerminalProbeStatus { confirmed, unsupported, skipped, timeout, error }

/// One active terminal probe result.
@immutable
final class TerminalProbeResult {
  const TerminalProbeResult({
    required this.id,
    required this.label,
    required this.status,
    required this.elapsed,
    this.feature,
    this.response,
    this.detail,
    this.details = const <String, Object?>{},
  });

  final String id;
  final String label;
  final TerminalFeature? feature;
  final TerminalProbeStatus status;
  final Duration elapsed;
  final String? response;
  final String? detail;
  final Map<String, Object?> details;

  bool get isConfirmed => status == TerminalProbeStatus.confirmed;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    if (feature != null) 'feature': feature!.name,
    'status': status.name,
    'elapsedMs': elapsed.inMilliseconds,
    if (response != null) 'response': response,
    if (detail != null) 'detail': detail,
    if (details.isNotEmpty) 'details': details,
  };
}

/// Active probe evidence attached to terminal diagnostics.
@immutable
final class TerminalProbeReport {
  const TerminalProbeReport({
    required this.probes,
    this.schemaVersion = 1,
    this.skippedReason,
  });

  TerminalProbeReport.skipped(String reason)
    : this(skippedReason: reason, probes: const <TerminalProbeResult>[]);

  final int schemaVersion;
  final String? skippedReason;
  final List<TerminalProbeResult> probes;

  Set<TerminalFeature> get confirmedFeatures => <TerminalFeature>{
    for (final result in probes)
      if (result.isConfirmed && result.feature != null) result.feature!,
  };

  Map<String, int> get summary {
    final counts = <String, int>{
      for (final status in TerminalProbeStatus.values) status.name: 0,
    };
    for (final result in probes) {
      counts[result.status.name] = (counts[result.status.name] ?? 0) + 1;
    }
    return Map<String, int>.unmodifiable(counts);
  }

  TerminalProbeResult? resultFor(String id) {
    for (final result in probes) {
      if (result.id == id) return result;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    if (skippedReason != null) 'skippedReason': skippedReason,
    'confirmedFeatures': <String>[
      for (final feature in confirmedFeatures) feature.name,
    ],
    'summary': summary,
    'probes': <Object?>[for (final probe in probes) probe.toJson()],
  };
}

/// Transport boundary for opt-in active probes.
///
/// Implementations write [bytes] to a terminal and return raw bytes collected
/// from stdin until [timeout]. The core probe suite stays pure; real stdio
/// setup lives in the native CLI.
abstract interface class TerminalProbeTransport {
  Future<List<int>> request(String bytes, {required Duration timeout});
}

/// Runs Fleury's conservative active terminal probe suite.
Future<TerminalProbeReport> runTerminalProbeSuite(
  TerminalProbeTransport transport, {
  Duration perProbeTimeout = const Duration(milliseconds: 150),
}) async {
  final results = <TerminalProbeResult>[];
  for (final definition in _probeDefinitions) {
    final stopwatch = Stopwatch()..start();
    try {
      final responseBytes = await transport.request(
        definition.request,
        timeout: perProbeTimeout,
      );
      stopwatch.stop();
      results.add(definition.parse(responseBytes, elapsed: stopwatch.elapsed));
    } on TimeoutException catch (error) {
      stopwatch.stop();
      results.add(
        TerminalProbeResult(
          id: definition.id,
          label: definition.label,
          feature: definition.feature,
          status: TerminalProbeStatus.timeout,
          elapsed: stopwatch.elapsed,
          detail: 'Probe timed out before a terminal response was received.',
          details: <String, Object?>{
            'timeoutMs': perProbeTimeout.inMilliseconds,
            if (error.message != null) 'message': error.message,
          },
        ),
      );
    } on Object catch (error) {
      stopwatch.stop();
      results.add(
        TerminalProbeResult(
          id: definition.id,
          label: definition.label,
          feature: definition.feature,
          status: TerminalProbeStatus.error,
          elapsed: stopwatch.elapsed,
          detail: error.toString(),
        ),
      );
    }
  }
  return TerminalProbeReport(probes: results);
}

/// Actively probes the terminal for a native image protocol and returns the
/// confirmed [ImageProtocol], or null if none is confirmed (the caller keeps
/// its environment-derived fallback). Currently detects the **Kitty graphics
/// protocol** (kitty, WezTerm, Ghostty, recent Warp, …) — the broadest and
/// most capable. A single query/response round trip bounded by [timeout]; the
/// request appends a Device Attributes query so a terminal that ignores the
/// graphics query still replies, letting the caller stop waiting promptly
/// instead of always blocking for the full [timeout].
Future<ImageProtocol?> probeImageProtocol(
  TerminalProbeTransport transport, {
  Duration timeout = const Duration(milliseconds: 150),
}) async {
  final stopwatch = Stopwatch()..start();
  final List<int> response;
  try {
    response = await transport.request(_kittyGraphicsQuery, timeout: timeout);
  } on Object {
    return null;
  }
  stopwatch.stop();
  final result = _parseKittyGraphicsQuery(response, elapsed: stopwatch.elapsed);
  return result.isConfirmed ? ImageProtocol.kitty : null;
}

/// Asks the terminal which Kitty keyboard flags are actually active.
///
/// Returns the confirmed bitset, or null when the terminal does not support
/// the protocol (or answered nothing in time). The query is bracketed by a
/// primary device-attributes request, which every real emulator answers —
/// so "unsupported" is detected by DA1 arriving WITHOUT a flags reply
/// rather than by a wall-clock timeout, keeping the verdict independent of
/// link latency (RFC 0020 §8.2).
///
/// Shares [_parseKittyKeyboardStatus] with the diagnostic probe, so runtime
/// negotiation and `diagnose --probe` can never disagree about what a reply
/// means.
Future<int?> probeKeyboardFlags(
  TerminalProbeTransport transport, {
  Duration timeout = const Duration(milliseconds: 150),
}) async {
  final stopwatch = Stopwatch()..start();
  final List<int> response;
  try {
    response = await transport.request(_kittyKeyboardQuery, timeout: timeout);
  } on Object {
    return null;
  }
  stopwatch.stop();
  final result = _parseKittyKeyboardStatus(
    response,
    elapsed: stopwatch.elapsed,
  );
  if (!result.isConfirmed) return null;
  final flags = result.details['flags'];
  return flags is int ? flags : null;
}

/// Confirms that DEC synchronized-output mode 2026 is mutable on this terminal.
///
/// DECRQM values 1 (set) and 2 (reset) are the protocol's supported states.
/// Values 0 and 4 are unsupported; value 3 is undefined for mode 2026 and is
/// therefore rejected conservatively. The appended DA1 sentinel distinguishes
/// an unsupported mode from a transport that never replied.
Future<bool> probeSynchronizedOutput(
  TerminalProbeTransport transport, {
  Duration timeout = const Duration(milliseconds: 150),
}) async {
  final stopwatch = Stopwatch()..start();
  final List<int> response;
  try {
    response = await transport.request(
      synchronizedOutputQuery,
      timeout: timeout,
    );
  } on Object {
    return false;
  }
  stopwatch.stop();
  return _parseSynchronizedOutput(
    response,
    elapsed: stopwatch.elapsed,
  ).isConfirmed;
}

/// Actively measures whether the terminal renders East-Asian *Ambiguous*-width
/// glyphs as one column or two.
///
/// Delegates to the batched [probeGlyphWidths] and answers from the
/// ambiguous-class representatives under RFC 0019's agreement rule: narrow
/// only when every representative measured 1, wide only when every one
/// measured ≥ 2, and null on any disagreement, anomaly, or missing reply — a
/// single glyph is a signal, not proof, and box drawing in particular is the
/// character a terminal is most likely to special-case narrow (grids must
/// work) while rendering the rest of the Ambiguous class wide. Null keeps the
/// caller's safe (defensive) default. This is the same cursor-measurement
/// trick vim's `t_u7` uses to auto-set `ambiwidth`.
Future<AmbiguousCharWidth?> probeAmbiguousWidth(
  TerminalProbeTransport transport, {
  Duration timeout = const Duration(milliseconds: 150),
}) async {
  final measured = await probeGlyphWidths(transport, timeout: timeout);
  return ambiguousWidthFromMeasurements(measured);
}

/// The agreement-rule derivation shared by [probeAmbiguousWidth], the POSIX
/// driver, and `fleury diagnose`: one answer for the ambiguous axis, or null
/// when the evidence doesn't agree.
AmbiguousCharWidth? ambiguousWidthFromMeasurements(
  WidthMeasurements measurements,
) {
  final widths = measurements.widthsIn(WidthProbeClass.ambiguous);
  if (widths.isEmpty || widths.any((w) => w == null)) return null;
  if (widths.every((w) => w == 1)) return AmbiguousCharWidth.narrow;
  if (widths.every((w) => w! >= 2)) return AmbiguousCharWidth.wide;
  return null; // Disagreement — conservative, keep the default.
}

/// The width-disagreement class a probe glyph represents. Classes are
/// independent: a representative votes only within its own class (RFC 0019
/// §6.1), so "bare emoji wide, variation sequence narrow" — the common
/// combination in the field — derives cleanly instead of poisoning agreement.
enum WidthProbeClass {
  /// UAX #11 East Asian Ambiguous: 1 on modern terminals, 2 on CJK-configured
  /// ones.
  ambiguous,

  /// Bare `Emoji_Presentation` scalars, probed without any selector. Also the
  /// measured component inputs to the ZWJ summing equation.
  emojiPresentation,

  /// Simple base + VS16 sequences. The biggest single disagreement in the
  /// field: roughly 19 of ~30 surveyed terminals draw `❤️` at 1 cell.
  emojiVariationSequence,

  /// Emoji ZWJ sequences: ≤ 2 when the terminal clusters, component-sum when
  /// it draws each code point separately.
  zwjSequence,

  /// Text-presentation dingbats. Diagnostic only — expected 1 everywhere; a 2
  /// means the terminal emoji-fies text-default symbols, which no policy axis
  /// models (that tail stays pinned).
  textPresentation,
}

/// One glyph in the probe battery: what is written, which class it votes in,
/// and a stable [id] used in JSON and diagnostics.
@immutable
final class WidthProbeGlyph {
  const WidthProbeGlyph(this.id, this.glyph, this.probeClass);

  final String id;
  final String glyph;
  final WidthProbeClass probeClass;
}

/// The probe battery: several representatives per class, from distinct blocks,
/// all old and widely deployed — agreement across them is what authorizes an
/// axis to adapt, and any disagreement leaves the axis unknown (RFC 0019
/// §6.1). The ZWJ sequences' components are probed bare so summing can be
/// established by the measured equation
/// `componentSum ≤ sequenceAdvance ≤ componentSum + zwjCount`
/// rather than inferred.
///
/// Order defines the write order and therefore the CPR reply order.
const List<WidthProbeGlyph> widthProbeBattery = <WidthProbeGlyph>[
  // Ambiguous — three different blocks; box drawing alone is the glyph most
  // likely to be special-cased narrow by an otherwise ambiguous-wide terminal.
  WidthProbeGlyph('boxDrawing', '\u{2500}', WidthProbeClass.ambiguous), // ─
  WidthProbeGlyph('greekAlpha', '\u{03B1}', WidthProbeClass.ambiguous), // α
  WidthProbeGlyph('degreeSign', '\u{00B0}', WidthProbeClass.ambiguous), // °
  // Bare emoji presentation, including the family components.
  WidthProbeGlyph(
    'slightSmile',
    '\u{1F642}',
    WidthProbeClass.emojiPresentation,
  ), // 🙂
  WidthProbeGlyph(
    'grinningFace',
    '\u{1F600}',
    WidthProbeClass.emojiPresentation,
  ), // 😀
  WidthProbeGlyph('man', '\u{1F468}', WidthProbeClass.emojiPresentation), // 👨
  WidthProbeGlyph(
    'woman',
    '\u{1F469}',
    WidthProbeClass.emojiPresentation,
  ), // 👩
  WidthProbeGlyph('boy', '\u{1F466}', WidthProbeClass.emojiPresentation), // 👦
  // Simple variation sequences (one base + VS16, nothing else).
  WidthProbeGlyph(
    'heartVs16',
    '\u{2764}\u{FE0F}',
    WidthProbeClass.emojiVariationSequence,
  ), // ❤️
  WidthProbeGlyph(
    'warningVs16',
    '\u{26A0}\u{FE0F}',
    WidthProbeClass.emojiVariationSequence,
  ), // ⚠️
  WidthProbeGlyph(
    'medicalVs16',
    '\u{2695}\u{FE0F}',
    WidthProbeClass.emojiVariationSequence,
  ), // ⚕️ — also the second component of the profession sequence below.
  // ZWJ sequences from two different sequence families.
  WidthProbeGlyph(
    'familyZwj',
    '\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466}',
    WidthProbeClass.zwjSequence,
  ), // 👨‍👩‍👦
  WidthProbeGlyph(
    'healthWorkerZwj',
    '\u{1F469}\u{200D}\u{2695}\u{FE0F}',
    WidthProbeClass.zwjSequence,
  ), // 👩‍⚕️
  // Diagnostic only.
  WidthProbeGlyph(
    'checkMark',
    '\u{2713}',
    WidthProbeClass.textPresentation,
  ), // ✓
];

/// What the terminal ACTUALLY drew for each battery glyph, in cells, measured
/// rather than assumed — raw observations, parallel to [widthProbeBattery].
///
/// There is no protocol by which an application can ask a terminal how wide it
/// will draw something — DECRQM 2027 reports a capability that is known to lie
/// in both directions, and OSC 66 exists on two emulators. What does work,
/// everywhere, is what vim's `t_u7` does: draw it and look at where the cursor
/// ended up.
///
/// **The batch is atomic** (RFC 0019 §6.1): CPR replies are ordered but
/// unlabeled, so a reply count that doesn't match the battery means later
/// replies can't be attributed safely — the whole battery is discarded
/// ([WidthMeasurements.empty]) rather than salvaged per-glyph. Judgement
/// (agreement, anomaly rejection) lives in derivation, not here: a measured
/// zero advance is recorded as 0 and fails agreement downstream.
@immutable
final class WidthMeasurements {
  /// [cellWidths] must be parallel to [widthProbeBattery] (or empty).
  const WidthMeasurements(this.cellWidths)
    : assert(
        cellWidths.length == 0 || cellWidths.length == widthProbeBattery.length,
        'cellWidths must be empty or parallel to widthProbeBattery',
      );

  /// No usable measurements: the terminal never answered, or the batch was
  /// discarded as unattributable.
  const WidthMeasurements.empty() : cellWidths = const <int?>[];

  /// Builds measurements from glyph [id] → width, for tests and fixtures.
  /// Ids not mentioned measure null.
  factory WidthMeasurements.of(Map<String, int?> byId) {
    for (final id in byId.keys) {
      assert(
        widthProbeBattery.any((g) => g.id == id),
        'unknown probe glyph id: $id',
      );
    }
    return WidthMeasurements(
      List<int?>.unmodifiable(widthProbeBattery.map((g) => byId[g.id])),
    );
  }

  /// Measured advance in cells per battery glyph, or null where unanswered.
  /// Empty when the whole batch was discarded.
  final List<int?> cellWidths;

  bool get isEmpty => cellWidths.isEmpty;

  /// The measured width of the battery glyph with [id], or null.
  int? widthOf(String id) {
    for (var i = 0; i < widthProbeBattery.length; i++) {
      if (widthProbeBattery[i].id == id) {
        return i < cellWidths.length ? cellWidths[i] : null;
      }
    }
    return null;
  }

  /// The measured widths of every representative in [probeClass], in battery
  /// order. Empty when the batch was discarded.
  List<int?> widthsIn(WidthProbeClass probeClass) {
    if (isEmpty) return const <int?>[];
    final out = <int?>[];
    for (var i = 0; i < widthProbeBattery.length; i++) {
      if (widthProbeBattery[i].probeClass == probeClass) {
        out.add(cellWidths[i]);
      }
    }
    return out;
  }

  /// Battery glyphs paired with their measurements, for diagnostics.
  Iterable<(WidthProbeGlyph, int?)> get entries sync* {
    for (var i = 0; i < widthProbeBattery.length; i++) {
      yield (widthProbeBattery[i], isEmpty ? null : cellWidths[i]);
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    for (final (glyph, width) in entries) glyph.id: width,
  };

  @override
  String toString() {
    if (isEmpty) return 'WidthMeasurements.empty()';
    final parts = [for (final (glyph, width) in entries) '${glyph.id}: $width'];
    return 'WidthMeasurements(${parts.join(', ')})';
  }
}

/// Measures the whole [widthProbeBattery] in ONE round trip.
///
/// Each probe glyph is written at column 1 of the CURRENT line and immediately
/// followed by a Cursor Position Report request, so the replies arrive in the
/// same order the glyphs were written; the line is erased afterwards. Safe on
/// the normal screen as well as the alternate one — it never homes the cursor,
/// so it cannot overwrite content above the caller's line.
Future<WidthMeasurements> probeGlyphWidths(
  TerminalProbeTransport transport, {
  Duration timeout = const Duration(milliseconds: 150),
}) async {
  final List<int> response;
  try {
    response = await transport.request(glyphWidthQuery, timeout: timeout);
  } on Object {
    return const WidthMeasurements.empty();
  }
  final columns = _cursorReportColumns(response);
  // Atomicity: an unexpected reply count means attribution is unsafe.
  if (columns.length != widthProbeBattery.length) {
    return const WidthMeasurements.empty();
  }
  // Each glyph started at column 1, so the reported column is advance + 1.
  // Recorded raw — a zero or negative-looking advance is kept as measured and
  // rejected by derivation's agreement rules, not silently repaired here.
  return WidthMeasurements(List<int?>.unmodifiable(columns.map((c) => c - 1)));
}

/// Return to column 1, draw, ask where the cursor landed — once per battery
/// glyph — then erase the line. Built from [widthProbeBattery], so the write
/// order and the reply order can't drift apart. The trailing Device Attributes
/// query is the transport's stop sentinel.
///
/// Uses `\r` rather than `ESC [ H`: carriage return stays on the CURRENT line,
/// so this is safe both on the alternate screen (where the driver probes) and
/// on the normal screen (where `fleury diagnose --probe` does). Homing to the
/// top-left would overwrite whatever the user already had on screen. Every
/// glyph is `\r`-anchored, so widths never accumulate across the line and a
/// narrow viewport can't wrap mid-battery.
final String glyphWidthQuery =
    '${widthProbeBattery.map((g) => '\r${g.glyph}\x1B[6n').join()}'
    '\r\x1B[K'
    '$_deviceAttributesQuery';

/// Every column reported by a Cursor Position Report (`ESC [ row ; col R`) in
/// [responseBytes], in arrival order. Scans past any other CSI reply (e.g. the
/// trailing Device Attributes `c`) that shares the buffer, so a batched probe
/// can read one column per glyph it wrote.
List<int> _cursorReportColumns(List<int> responseBytes) {
  final columns = <int>[];
  for (var i = 0; i + 1 < responseBytes.length; i++) {
    if (responseBytes[i] != 0x1B || responseBytes[i + 1] != 0x5B) {
      continue; // ESC [
    }
    var j = i + 2;
    final start = j;
    while (j < responseBytes.length &&
        responseBytes[j] >= 0x30 &&
        responseBytes[j] <= 0x3F) {
      j++; // CSI parameter bytes (digits, ';')
    }
    if (j >= responseBytes.length) break; // final byte not arrived
    if (responseBytes[j] == 0x52) {
      // 'R' → Cursor Position Report. Parameters are `row;col`.
      final parts = String.fromCharCodes(
        responseBytes.sublist(start, j),
      ).split(';');
      if (parts.length == 2) {
        final col = int.tryParse(parts[1]);
        if (col != null) columns.add(col);
      }
    }
    // Resume from `j`: the for-loop's `i++` steps to `j`. If `j` is a real CSI
    // final byte it's re-examined harmlessly (not an ESC, so skipped); if the
    // parameter run instead ended because the NEXT escape sequence began (an
    // aborted CSI abutting a real CPR), that ESC is not skipped and the CPR is
    // still found. Using `i = j` here would step over that ESC and miss it.
    i = j - 1;
  }
  return columns;
}

typedef _ProbeParser =
    TerminalProbeResult Function(
      List<int> responseBytes, {
      required Duration elapsed,
    });

@immutable
final class _ProbeDefinition {
  const _ProbeDefinition({
    required this.id,
    required this.label,
    required this.request,
    required this.parse,
    this.feature,
  });

  final String id;
  final String label;
  final TerminalFeature? feature;
  final String request;
  final _ProbeParser parse;
}

const _deviceAttributesQuery = '\x1B[c';

/// DECRQM query for synchronized-output mode 2026, bracketed by DA1 so an
/// unsupported terminal resolves promptly instead of consuming the timeout.
@visibleForTesting
const synchronizedOutputQuery = '\x1B[?2026\$p$_deviceAttributesQuery';

/// Runtime negotiation's query: the app's enter sequences ALREADY pushed a
/// tier, so a bare status read reports what the terminal honoured of it.
@visibleForTesting
const kittyKeyboardRuntimeQuery = _kittyKeyboardQuery;

const _kittyKeyboardQuery = '\x1B[?u$_deviceAttributesQuery';

/// The DIAGNOSTIC's query, which must measure SUPPORT rather than current
/// state.
///
/// `CSI ? u` alone reports the flags currently in force — and a terminal
/// sitting at a shell prompt has pushed nothing, so every emulator on earth
/// answers 0. Read as support, that says Ghostty and Kitty do not implement
/// the protocol they invented. So the probe asks for everything, reads back
/// the honoured subset, and pops to leave the terminal exactly as found. The
/// pop lands before the DA1 that brackets the exchange, so the restore is
/// complete by the time the probe resolves.
@visibleForTesting
const kittyKeyboardSupportQuery = _kittyKeyboardSupportQuery;

const _kittyKeyboardSupportQuery =
    '\x1B[>31u' // push: request every progressive-enhancement flag
    '\x1B[?u' // query: what stuck
    '\x1B[<1u' // pop: restore the prior stack entry
    '$_deviceAttributesQuery';
const _kittyGraphicsQuery =
    '\x1B_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1B\\$_deviceAttributesQuery';

const List<_ProbeDefinition> _probeDefinitions = <_ProbeDefinition>[
  _ProbeDefinition(
    id: 'primaryDeviceAttributes',
    label: 'Primary device attributes',
    request: _deviceAttributesQuery,
    parse: _parsePrimaryDeviceAttributes,
  ),
  _ProbeDefinition(
    id: 'kittyKeyboardStatus',
    label: 'Kitty keyboard status',
    feature: TerminalFeature.kittyKeyboard,
    request: _kittyKeyboardSupportQuery,
    parse: _parseKittyKeyboardStatus,
  ),
  _ProbeDefinition(
    id: 'synchronizedOutput',
    label: 'Synchronized output',
    feature: TerminalFeature.synchronizedOutput,
    request: synchronizedOutputQuery,
    parse: _parseSynchronizedOutput,
  ),
  _ProbeDefinition(
    id: 'kittyGraphicsQuery',
    label: 'Kitty graphics query',
    feature: TerminalFeature.imageKitty,
    request: _kittyGraphicsQuery,
    parse: _parseKittyGraphicsQuery,
  ),
];

TerminalProbeResult _parseSynchronizedOutput(
  List<int> responseBytes, {
  required Duration elapsed,
}) {
  final response = _escapedResponse(responseBytes);
  final state = _synchronizedOutputState(responseBytes);
  final supported = state == 1 || state == 2;
  if (supported) {
    return TerminalProbeResult(
      id: 'synchronizedOutput',
      label: 'Synchronized output',
      feature: TerminalFeature.synchronizedOutput,
      status: TerminalProbeStatus.confirmed,
      elapsed: elapsed,
      response: response,
      detail: 'Terminal reports mutable DEC mode 2026 support.',
      details: <String, Object?>{
        'mode': 2026,
        'state': state!,
        'enabled': state == 1,
      },
    );
  }

  final sentinelReceived = _primaryDeviceAttributes(responseBytes) != null;
  return TerminalProbeResult(
    id: 'synchronizedOutput',
    label: 'Synchronized output',
    feature: TerminalFeature.synchronizedOutput,
    status: sentinelReceived
        ? TerminalProbeStatus.unsupported
        : TerminalProbeStatus.timeout,
    elapsed: elapsed,
    response: response,
    detail: sentinelReceived
        ? state == 3
              ? 'Terminal reported undefined permanently-set state for mode 2026.'
              : 'Terminal did not report mutable DEC mode 2026 support.'
        : 'No sentinel terminal response received before timeout.',
    details: <String, Object?>{'mode': 2026, 'state': state},
  );
}

TerminalProbeResult _parsePrimaryDeviceAttributes(
  List<int> responseBytes, {
  required Duration elapsed,
}) {
  final response = _escapedResponse(responseBytes);
  final attributes = _primaryDeviceAttributes(responseBytes);
  if (attributes == null) {
    return TerminalProbeResult(
      id: 'primaryDeviceAttributes',
      label: 'Primary device attributes',
      status: responseBytes.isEmpty
          ? TerminalProbeStatus.timeout
          : TerminalProbeStatus.unsupported,
      elapsed: elapsed,
      response: response,
      detail: responseBytes.isEmpty
          ? 'No terminal response received before timeout.'
          : 'No primary device attributes response was detected.',
    );
  }

  return TerminalProbeResult(
    id: 'primaryDeviceAttributes',
    label: 'Primary device attributes',
    status: TerminalProbeStatus.confirmed,
    elapsed: elapsed,
    response: response,
    detail: 'Primary device attributes reply received.',
    details: <String, Object?>{'parameters': attributes},
  );
}

/// The §5.7 projection, flattened for a JSON details map.
Map<String, Object?> _semanticDetails(int flags) {
  final caps = KeyboardCapabilities.fromKittyFlags(flags);
  return <String, Object?>{
    'supportsHeldState': caps.supportsHeldState,
    'distinguishesRepeats': caps.distinguishesRepeats,
    'supportsPositions': caps.supportsPositions,
    'reportsPrintableKeys': caps.reportsPrintableKeys,
    'lifecycleSafe':
        flags & 0x02 != 0 && flags & 0x08 != 0 && flags & 0x10 != 0,
  };
}

TerminalProbeResult _parseKittyKeyboardStatus(
  List<int> responseBytes, {
  required Duration elapsed,
}) {
  final response = _escapedResponse(responseBytes);
  final flags = _kittyKeyboardFlags(responseBytes);
  if (flags != null) {
    return TerminalProbeResult(
      id: 'kittyKeyboardStatus',
      label: 'Kitty keyboard status',
      feature: TerminalFeature.kittyKeyboard,
      status: TerminalProbeStatus.confirmed,
      elapsed: elapsed,
      response: response,
      detail: 'Kitty keyboard protocol status reply received.',
      details: <String, Object?>{
        'flags': flags,
        'disambiguateEscapeCodes': flags & 0x01 != 0,
        'reportEventTypes': flags & 0x02 != 0,
        'reportAlternateKeys': flags & 0x04 != 0,
        'reportAllKeysAsEscapes': flags & 0x08 != 0,
        'reportAssociatedText': flags & 0x10 != 0,
        // What apps actually plan against (RFC 0020 §5.7). Raw flags are the
        // protocol's vocabulary; these are the framework's, and a support
        // matrix compared across terminals wants the latter — "held state
        // works here" is the reviewable claim, not "bit 3 is set".
        ..._semanticDetails(flags),
      },
    );
  }

  return TerminalProbeResult(
    id: 'kittyKeyboardStatus',
    label: 'Kitty keyboard status',
    feature: TerminalFeature.kittyKeyboard,
    status: _primaryDeviceAttributes(responseBytes) == null
        ? TerminalProbeStatus.timeout
        : TerminalProbeStatus.unsupported,
    elapsed: elapsed,
    response: response,
    detail: _primaryDeviceAttributes(responseBytes) == null
        ? 'No sentinel terminal response received before timeout.'
        : 'Terminal answered DA but not the Kitty keyboard status query.',
  );
}

TerminalProbeResult _parseKittyGraphicsQuery(
  List<int> responseBytes, {
  required Duration elapsed,
}) {
  final response = _escapedResponse(responseBytes);
  final graphics = _kittyGraphicsResponse(responseBytes);
  if (graphics != null) {
    return TerminalProbeResult(
      id: 'kittyGraphicsQuery',
      label: 'Kitty graphics query',
      feature: TerminalFeature.imageKitty,
      status: TerminalProbeStatus.confirmed,
      elapsed: elapsed,
      response: response,
      detail: 'Kitty graphics protocol query reply received.',
      details: graphics,
    );
  }

  return TerminalProbeResult(
    id: 'kittyGraphicsQuery',
    label: 'Kitty graphics query',
    feature: TerminalFeature.imageKitty,
    status: _primaryDeviceAttributes(responseBytes) == null
        ? TerminalProbeStatus.timeout
        : TerminalProbeStatus.unsupported,
    elapsed: elapsed,
    response: response,
    detail: _primaryDeviceAttributes(responseBytes) == null
        ? 'No sentinel terminal response received before timeout.'
        : 'Terminal answered DA but not the Kitty graphics query.',
  );
}

List<int>? _primaryDeviceAttributes(List<int> bytes) {
  final text = String.fromCharCodes(bytes);
  final match = RegExp('\x1B\\[\\?([0-9;]*)c').firstMatch(text);
  if (match == null) return null;
  final params = match.group(1);
  if (params == null || params.isEmpty) return const <int>[];
  return <int>[
    for (final part in params.split(';'))
      if (part.isNotEmpty) int.tryParse(part) ?? -1,
  ];
}

int? _kittyKeyboardFlags(List<int> bytes) {
  final text = String.fromCharCodes(bytes);
  final match = RegExp('\x1B\\[\\?([0-9]+)u').firstMatch(text);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

int? _synchronizedOutputState(List<int> bytes) {
  final text = String.fromCharCodes(bytes);
  final match = RegExp('\x1B\\[\\?2026;([0-4])\\\$y').firstMatch(text);
  return match == null ? null : int.parse(match.group(1)!);
}

Map<String, Object?>? _kittyGraphicsResponse(List<int> bytes) {
  final text = String.fromCharCodes(bytes);
  final start = text.indexOf('\x1B_G');
  if (start == -1) return null;
  final end = text.indexOf('\x1B\\', start + 3);
  if (end == -1) return null;

  final body = text.substring(start + 3, end);
  final separator = body.indexOf(';');
  if (separator == -1) {
    return <String, Object?>{'raw': body};
  }
  return <String, Object?>{
    'control': body.substring(0, separator),
    'message': body.substring(separator + 1),
  };
}

String _escapedResponse(List<int> bytes) {
  if (bytes.isEmpty) return '';
  final buffer = StringBuffer();
  const maxBytes = 160;
  final limit = bytes.length < maxBytes ? bytes.length : maxBytes;
  for (var i = 0; i < limit; i += 1) {
    final byte = bytes[i];
    switch (byte) {
      case 0x07:
        buffer.write(r'\a');
      case 0x1B:
        buffer.write(r'\x1B');
      case 0x09:
        buffer.write(r'\t');
      case 0x0A:
        buffer.write(r'\n');
      case 0x0D:
        buffer.write(r'\r');
      default:
        if (byte >= 0x20 && byte <= 0x7E) {
          buffer.writeCharCode(byte);
        } else {
          buffer.write(r'\x');
          buffer.write(byte.toRadixString(16).padLeft(2, '0'));
        }
    }
  }
  if (bytes.length > maxBytes) {
    buffer.write('...');
  }
  return buffer.toString();
}

/// **Framework-internal.** Index just past the [n]-th Device-Attributes reply's `c` terminator in [buf],
/// or -1 if fewer than [n] are present yet. A DA reply is `ESC [` then CSI
/// parameter/intermediate bytes (0x20–0x3F) then the final byte `c` (0x63).
/// Requiring valid CSI bytes before the `c` stops a stray 0x63 in unrelated
/// content (or a user keystroke that leaked in) from being mistaken for the
/// terminator. Counting to [n] keeps the probe-completion sentinel unambiguous
/// across a multi-probe startup sequence: the wait and the post-probe replay
/// both key off the LAST owed reply, not an earlier probe's straggler. [n] <= 0
/// returns 0 (nothing owed → the whole buffer is real input).
int daReplyEndN(List<int> buf, int n) {
  if (n <= 0) return 0;
  var seen = 0;
  for (var i = 0; i + 1 < buf.length; i++) {
    if (buf[i] != 0x1B || buf[i + 1] != 0x5B) continue; // ESC [
    var j = i + 2;
    while (j < buf.length && buf[j] >= 0x20 && buf[j] <= 0x3F) {
      j++; // CSI parameter / intermediate bytes
    }
    if (j >= buf.length) return -1; // final byte not arrived yet
    if (buf[j] == 0x63) {
      // 'c' final byte → Device Attributes.
      seen++;
      if (seen >= n) return j + 1;
    }
    i = j; // step past this CSI final byte and keep scanning
  }
  return -1;
}
