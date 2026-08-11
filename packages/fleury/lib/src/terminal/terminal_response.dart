import 'package:meta/meta.dart';

/// A terminal-originated control reply framed by [InputParser].
///
/// Responses are framework-internal. They are routed to the active query
/// exchange and never enter application input dispatch.
enum TerminalResponseKind {
  deviceAttributes,
  keyboardStatus,
  cursorPosition,
  modeReport,
  windowOperation,
  operatingSystemCommand,
  deviceControlString,
  applicationProgramCommand,
}

/// Which response forms a query exchange (or its late-reply quarantine) owns.
///
/// Private CSI replies such as Device Attributes and Kitty keyboard status are
/// unambiguous and are classified without opt-in; [privateCsiPrefix] only keeps
/// their fragmented prefixes alive across the ordinary key-idle flush. Cursor
/// Position Reports collide with the legacy modified-F3 encoding, while
/// OSC/DCS/APC prefixes collide with Alt key chords, so those forms are
/// classified only for the query that requested them.
@immutable
final class TerminalResponseExpectation {
  const TerminalResponseExpectation({
    this.privateCsiPrefix = false,
    this.cursorPosition = false,
    this.modeReport = false,
    this.windowOperation = false,
    this.operatingSystemCommand = false,
    this.deviceControlString = false,
    this.applicationProgramCommand = false,
  });

  static const none = TerminalResponseExpectation();

  final bool privateCsiPrefix;
  final bool cursorPosition;
  final bool modeReport;
  final bool windowOperation;
  final bool operatingSystemCommand;
  final bool deviceControlString;
  final bool applicationProgramCommand;

  bool get hasControlStrings =>
      operatingSystemCommand ||
      deviceControlString ||
      applicationProgramCommand;
}

/// One complete terminal reply, preserving its exact wire bytes so runtime
/// negotiation and opt-in diagnostics can share the same response codecs.
@immutable
final class TerminalResponse {
  TerminalResponse(this.kind, List<int> raw)
    : raw = List<int>.unmodifiable(raw);

  final TerminalResponseKind kind;
  final List<int> raw;

  bool get isDeviceAttributes => kind == TerminalResponseKind.deviceAttributes;

  @override
  String toString() => 'TerminalResponse(${kind.name}, ${raw.length} bytes)';
}

/// Sink used only inside terminal drivers and query tooling.
abstract interface class TerminalResponseSink {
  void addTerminalResponse(TerminalResponse response);
}
