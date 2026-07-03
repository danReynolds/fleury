import 'dart:async';

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

/// Actively measures whether the terminal renders East-Asian *Ambiguous*-width
/// glyphs as one column or two.
///
/// Writes a single ambiguous glyph at the home cell, then a Cursor Position
/// Report query (`ESC [ 6 n`): the reported column tells us how far the cursor
/// advanced — 2 (one column past home) means the terminal drew it narrow, 3
/// means wide. The glyph is erased and a Device Attributes query appended so the
/// transport stops as soon as the reply lands. Returns null when the terminal
/// doesn't answer, so the caller keeps its safe (defensive) default. This is the
/// same cursor-measurement trick vim's `t_u7` uses to auto-set `ambiwidth`.
///
/// Must run on the alternate screen (the probe writes to the home cell); the
/// caller erases it and the first frame repaints over it regardless.
Future<AmbiguousCharWidth?> probeAmbiguousWidth(
  TerminalProbeTransport transport, {
  Duration timeout = const Duration(milliseconds: 150),
}) async {
  final List<int> response;
  try {
    response = await transport.request(
      _ambiguousWidthQuery,
      timeout: timeout,
    );
  } on Object {
    return null;
  }
  final column = _cursorReportColumn(response);
  if (column == null) return null;
  // The glyph occupied home (column 1). The cursor now rests at the next free
  // column: 2 when the terminal advanced one cell (narrow), 3 when it advanced
  // two (wide). Anything below 2 is anomalous (0-width) — treat as narrow.
  return column >= 3 ? AmbiguousCharWidth.wide : AmbiguousCharWidth.narrow;
}

/// Home, one ambiguous glyph (box-drawing horizontal, UAX #11 Ambiguous),
/// a Cursor Position Report request, then erase the glyph and re-home. The
/// trailing Device Attributes query is the transport's stop sentinel.
const _ambiguousWidthQuery =
    '\x1B[H─\x1B[6n\x1B[H\x1B[K$_deviceAttributesQuery';

/// The column from a Cursor Position Report (`ESC [ row ; col R`) in
/// [responseBytes], or null if none is present. Scans past any other CSI reply
/// (e.g. the trailing Device Attributes `c`) that shares the buffer.
int? _cursorReportColumn(List<int> responseBytes) {
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
    if (j >= responseBytes.length) return null; // final byte not arrived
    if (responseBytes[j] == 0x52) {
      // 'R' → Cursor Position Report. Parameters are `row;col`.
      final parts = String.fromCharCodes(
        responseBytes.sublist(start, j),
      ).split(';');
      if (parts.length == 2) {
        final col = int.tryParse(parts[1]);
        if (col != null) return col;
      }
    }
    i = j; // some other CSI final byte — keep scanning past it
  }
  return null;
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
const _kittyKeyboardQuery = '\x1B[?u$_deviceAttributesQuery';
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
    request: _kittyKeyboardQuery,
    parse: _parseKittyKeyboardStatus,
  ),
  _ProbeDefinition(
    id: 'kittyGraphicsQuery',
    label: 'Kitty graphics query',
    feature: TerminalFeature.imageKitty,
    request: _kittyGraphicsQuery,
    parse: _parseKittyGraphicsQuery,
  ),
];

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
