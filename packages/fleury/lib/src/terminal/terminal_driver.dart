import 'dart:async' show FutureOr;

import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import '../input/events.dart';
import '../input/keyboard_state.dart';
import '../rendering/surface_capabilities.dart';
import '../runtime/remote_surface_sink.dart';
import 'capabilities.dart';

/// The presentation path selected for one entered terminal session.
sealed class TerminalPresentation {
  const TerminalPresentation();
}

/// ANSI byte presentation, with the terminal-specific mechanisms its
/// presenter needs. Widgets consume [TerminalSessionProfile.surface] instead.
@immutable
final class AnsiTerminalPresentation extends TerminalPresentation {
  const AnsiTerminalPresentation(
    this.capabilities, {
    this.synchronizedOutput = false,
    this.pointerShapes = false,
  });

  final TerminalCapabilities capabilities;

  /// Whether frame output uses DEC synchronized-update markers.
  final bool synchronizedOutput;

  /// OSC 22 pointer shapes, actively confirmed by the native terminal driver.
  /// The driver owns the matching shape-stack push/pop across terminal leases.
  final bool pointerShapes;
}

/// Structured frame presentation to a negotiated remote surface.
@immutable
final class StructuredTerminalPresentation extends TerminalPresentation {
  const StructuredTerminalPresentation(this.sink);

  final RemoteSurfaceSink sink;
}

/// Immutable truth returned by a successful [TerminalDriver.enter].
///
/// The profile separates semantic behavior used by apps from the concrete
/// presentation mechanism used by the host. It remains valid until restore;
/// live keyboard contradiction repair may still demote the dispatcher's copy.
@immutable
final class TerminalSessionProfile {
  const TerminalSessionProfile({
    required this.surface,
    required this.keyboard,
    required this.presentation,
  });

  factory TerminalSessionProfile.ansi({
    required TerminalCapabilities terminal,
    KeyboardCapabilities keyboard = KeyboardCapabilities.legacy,
    SurfaceCapabilities? surface,
    bool synchronizedOutput = false,
    bool pointerShapes = false,
  }) => TerminalSessionProfile(
    surface: surface ?? terminal.toSurfaceCapabilities(),
    keyboard: keyboard,
    presentation: AnsiTerminalPresentation(
      terminal,
      synchronizedOutput: synchronizedOutput,
      pointerShapes: pointerShapes,
    ),
  );

  factory TerminalSessionProfile.structured({
    required SurfaceCapabilities surface,
    required KeyboardCapabilities keyboard,
    required RemoteSurfaceSink sink,
  }) => TerminalSessionProfile(
    surface: surface,
    keyboard: keyboard,
    presentation: StructuredTerminalPresentation(sink),
  );

  final SurfaceCapabilities surface;
  final KeyboardCapabilities keyboard;
  final TerminalPresentation presentation;
}

/// Reads the explicit synchronized-output policy for an ANSI session.
///
/// `null` means negotiate DEC mode 2026 when the transport can query its peer.
/// Drivers without a query channel treat `null` conservatively as disabled.
/// This is deliberately a tri-state override rather than terminal-name
/// detection: `FLEURY_SYNC_OUTPUT=1` is an explicit operator assertion, while
/// the default remains evidence-driven.
bool? synchronizedOutputOverrideFromEnvironment(
  Map<String, String> environment,
) {
  switch (environment['FLEURY_SYNC_OUTPUT']?.toLowerCase().trim()) {
    case '1' || 'true' || 'yes' || 'on':
      return true;
    case '0' || 'false' || 'no' || 'off':
      return false;
    default:
      return null;
  }
}

/// How much of the Kitty keyboard protocol a session negotiates
/// (RFC 0020 §8).
///
/// Each tier is a *request*; what a terminal actually honours is confirmed
/// by querying and reported through `KeyboardCapabilities`. Nothing here
/// promises a capability — a terminal that ignores the push silently stays
/// at whatever it already did.
enum KeyboardProtocolMode {
  /// Push nothing. Strict legacy behaviour, for debugging or a terminal
  /// known to mishandle the protocol.
  legacy(0),

  /// Flags 1|2 — disambiguate escape codes, and report event types.
  ///
  /// The safe tier: what a lifecycle request falls back to when the
  /// terminal cannot honour full lifecycle transactionally, and what the
  /// automatic upgrade stops at inside a terminal multiplexer (tmux/screen),
  /// where a raw query is not a reliable statement about the host terminal.
  /// Flag 1 makes otherwise-ambiguous chords distinct (lone
  /// Esc, Ctrl+I vs Tab, Ctrl+M vs Enter, super/meta). Flag 2 adds
  /// press/repeat/release tags to keys that are ALREADY escape-coded —
  /// chords, arrows, function keys — which is what lets a binding fire once
  /// per physical press instead of once per auto-repeat.
  ///
  /// Text is untouched: printable presses and repeats still arrive as
  /// ordinary bytes. Their RELEASES do become escape reports (the spec
  /// exempts only Enter, Tab and Backspace), which the parser drops and
  /// which §8.5's spawn bracket keeps out of child processes.
  disambiguated(1 | 2),

  /// Flags 1|2|4|8|16 — the full lifecycle: every key as an escape code,
  /// with alternate/base-layout identities and associated text.
  ///
  /// The default request (RFC 0020 §26.1): `runApp` asks drivers for full
  /// lifecycle and capable drivers negotiate down transactionally, committing
  /// only when
  /// the terminal confirms 2, 8 AND 16 (§8.3) — flag 8 stops the terminal
  /// sending text, and flag 16 is what re-supplies it, so honouring one
  /// without the other would leave the session with no text input at all.
  /// `FLEURY_KEYBOARD=disambiguated|legacy` overrides the request for a
  /// terminal where the negotiation itself misbehaves.
  lifecycle(1 | 2 | 4 | 8 | 16);

  const KeyboardProtocolMode(this.requestedFlags);

  /// The progressive-enhancement bitset this tier pushes.
  final int requestedFlags;
}

/// The set of terminal modes the driver should enable for a TUI session.
///
/// Choose a full-screen workspace or a bounded inline region.
/// [TerminalMode] defaults to [TerminalMode.fullScreen]. Both constructors
/// configure input and terminal cleanup; only [TerminalMode.inline] takes rows.
@immutable
final class TerminalMode {
  const TerminalMode({
    bool rawInput = true,
    bool hideCursor = true,
    bool resetStyleOnExit = true,
    bool bracketedPaste = true,
    KeyboardProtocolMode keyboardProtocol = KeyboardProtocolMode.lifecycle,
    bool focusReporting = true,
    bool mouse = false,
    bool mouseMotion = false,
  }) : this.fullScreen(
         rawInput: rawInput,
         hideCursor: hideCursor,
         resetStyleOnExit: resetStyleOnExit,
         bracketedPaste: bracketedPaste,
         keyboardProtocol: keyboardProtocol,
         focusReporting: focusReporting,
         mouse: mouse,
         mouseMotion: mouseMotion,
       );

  /// Uses the terminal viewport and restores the previous screen on exit.
  const TerminalMode.fullScreen({
    this.rawInput = true,
    this.hideCursor = true,
    this.resetStyleOnExit = true,
    this.bracketedPaste = true,
    this.keyboardProtocol = KeyboardProtocolMode.lifecycle,
    this.focusReporting = true,
    this.mouse = false,
    this.mouseMotion = false,
  }) : inlineRows = null;

  /// A bounded region in the main terminal buffer, beneath the command.
  ///
  /// Earlier output remains in the main buffer and may move into scrollback
  /// as space is reserved. [rows] is clamped to the terminal height; content
  /// scrolls inside that viewport using ordinary widgets.
  /// The live region is cleared on exit, ready for the command's final output.
  /// Requires a POSIX terminal with cursor-position reporting. Remote hosts
  /// keep their own viewport; native Windows does not yet support this mode.
  const TerminalMode.inline({
    required int rows,
    this.hideCursor = true,
    this.resetStyleOnExit = true,
    this.bracketedPaste = true,
    this.keyboardProtocol = KeyboardProtocolMode.lifecycle,
    this.focusReporting = true,
    this.mouse = false,
    this.mouseMotion = false,
  }) : assert(rows > 0, 'inline rows must be positive'),
       inlineRows = rows,
       rawInput = true;

  /// Requested initial height, or null for an ordinary terminal session.
  final int? inlineRows;

  bool get isInline => inlineRows != null;
  bool get isFullScreen => !isInline;

  /// The standard interactive TUI mode.
  static const TerminalMode interactive = TerminalMode.fullScreen();

  final bool rawInput;
  final bool hideCursor;
  final bool resetStyleOnExit;

  /// Enable bracketed paste (DEC 2004) so pasted text — including its
  /// newlines — arrives as one or more consecutive [PasteEvent] segments
  /// instead of line-by-line Enter chords. On by default; it's harmless and
  /// only helps.
  final bool bracketedPaste;

  /// Ask the terminal to report window focus changes (DECSET 1004).
  ///
  /// On by default and harmless where unsupported (the sequence is
  /// ignored). Focus-out is what tells the runtime to release keys the user
  /// is holding, since those releases will land in whatever window took
  /// focus and this terminal will never report them.
  final bool focusReporting;

  /// How much of the Kitty keyboard protocol to negotiate (RFC 0020 §8).
  final KeyboardProtocolMode keyboardProtocol;

  /// Whether any Kitty keyboard flags are pushed at all.
  bool get kittyKeyboard => keyboardProtocol != KeyboardProtocolMode.legacy;

  /// Enable SGR mouse reporting (clicks, drags, wheel). Off by default:
  /// capturing the mouse takes over the terminal's own text selection,
  /// which many users rely on, so it's strictly opt-in.
  final bool mouse;

  /// Also report bare pointer motion (no button held), enabling hover
  /// (`MouseRegion`). Implies [mouse]. Off by default since motion
  /// reporting is chatty — only turn it on if you use hover.
  final bool mouseMotion;
}

/// The input half of a [TerminalMode]: which reports the terminal sends
/// (mouse, pastes, focus changes) and how much of the Kitty keyboard protocol
/// encodes keys.
///
/// It is what a terminal the app does not own needs in order to stand in for
/// the app's own: an app attached to `fleury shell` declares it in the
/// handshake, and the shell's terminal then reports exactly that. Like the
/// mode it comes from, it is fixed for the session. The other half (the
/// screen, the cursor, raw input) belongs to whoever owns the terminal.
@immutable
final class TerminalInputModes {
  const TerminalInputModes({
    required this.mouse,
    required this.mouseMotion,
    required this.bracketedPaste,
    required this.focusReporting,
    required this.keyboardProtocol,
  });

  /// [mode]'s input half.
  TerminalInputModes.of(TerminalMode mode)
    : mouse = mode.mouse,
      mouseMotion = mode.mouseMotion,
      bracketedPaste = mode.bracketedPaste,
      focusReporting = mode.focusReporting,
      keyboardProtocol = mode.keyboardProtocol;

  /// [TerminalMode.mouse].
  final bool mouse;

  /// [TerminalMode.mouseMotion]; implies [mouse].
  final bool mouseMotion;

  /// [TerminalMode.bracketedPaste].
  final bool bracketedPaste;

  /// [TerminalMode.focusReporting].
  final bool focusReporting;

  /// [TerminalMode.keyboardProtocol].
  final KeyboardProtocolMode keyboardProtocol;

  @override
  bool operator ==(Object other) =>
      other is TerminalInputModes &&
      other.mouse == mouse &&
      other.mouseMotion == mouseMotion &&
      other.bracketedPaste == bracketedPaste &&
      other.focusReporting == focusReporting &&
      other.keyboardProtocol == keyboardProtocol;

  @override
  int get hashCode => Object.hash(
    mouse,
    mouseMotion,
    bracketedPaste,
    focusReporting,
    keyboardProtocol,
  );

  @override
  String toString() =>
      'TerminalInputModes(mouse: $mouse, mouseMotion: $mouseMotion, '
      'bracketedPaste: $bracketedPaste, focusReporting: $focusReporting, '
      'keyboardProtocol: ${keyboardProtocol.name})';
}

/// Returns [mode] with its input half replaced by [input]; its screen half
/// (full screen or inline, the cursor, raw input) is kept.
///
/// Kept out of the public barrel API, like
/// [terminalModeWithKeyboardProtocol].
TerminalMode terminalModeWithInput(
  TerminalMode mode,
  TerminalInputModes input,
) => mode.inlineRows != null
    ? TerminalMode.inline(
        rows: mode.inlineRows!,
        hideCursor: mode.hideCursor,
        resetStyleOnExit: mode.resetStyleOnExit,
        bracketedPaste: input.bracketedPaste,
        keyboardProtocol: input.keyboardProtocol,
        focusReporting: input.focusReporting,
        mouse: input.mouse,
        mouseMotion: input.mouseMotion,
      )
    : TerminalMode.fullScreen(
        rawInput: mode.rawInput,
        hideCursor: mode.hideCursor,
        resetStyleOnExit: mode.resetStyleOnExit,
        bracketedPaste: input.bracketedPaste,
        keyboardProtocol: input.keyboardProtocol,
        focusReporting: input.focusReporting,
        mouse: input.mouse,
        mouseMotion: input.mouseMotion,
      );

/// Returns [mode] with only its keyboard protocol request changed.
///
/// Kept out of the public barrel API: native drivers use this when policy or
/// negotiation selects an effective tier without rebuilding modes ad hoc.
TerminalMode terminalModeWithKeyboardProtocol(
  TerminalMode mode,
  KeyboardProtocolMode keyboardProtocol,
) => terminalModeWithInput(
  mode,
  TerminalInputModes(
    mouse: mode.mouse,
    mouseMotion: mode.mouseMotion,
    bracketedPaste: mode.bracketedPaste,
    focusReporting: mode.focusReporting,
    keyboardProtocol: keyboardProtocol,
  ),
);

/// The keyboard tier this session actually pushes, from what the app asked for
/// and what the environment says.
///
/// Two rules, both about *pushing* rather than about the verdict — the flags
/// have to be capped before they go out, not after:
///
///  * `FLEURY_KEYBOARD=legacy|disambiguated|lifecycle` wins outright. It is the
///    lever a support channel can pull on a deployed binary, and the one a bug
///    report can be asked to set.
///  * Otherwise the default (`lifecycle`) is capped to the safe tier inside a
///    MULTIPLEXER. A raw query is not a reliable statement about the host
///    terminal there — the same reasoning the image probe uses — and tmux may
///    answer for itself, forward to a host that answers differently, or accept
///    the flags and fail to translate the enhanced input back. Lifecycle is the
///    one tier where being wrong costs the user their ability to type, so the
///    automatic upgrade holds back. An app that knows its deployment handles
///    the protocol can still force it through the env var.
///
/// An app attached to `fleury shell` applies it too, before it declares its
/// input to the shell, so it asks the shell for what its own native driver
/// would push in the same environment.
KeyboardProtocolMode resolveKeyboardTier({
  required KeyboardProtocolMode requested,
  required Map<String, String> environment,
}) {
  final override = switch (environment['FLEURY_KEYBOARD']?.toLowerCase()) {
    'legacy' || 'off' || 'none' => KeyboardProtocolMode.legacy,
    'disambiguated' || 'default' => KeyboardProtocolMode.disambiguated,
    'lifecycle' || 'full' => KeyboardProtocolMode.lifecycle,
    _ => null,
  };
  if (override != null) return override;
  if (requested == KeyboardProtocolMode.lifecycle &&
      detectTerminalMultiplexerFromEnvironment(environment)) {
    return KeyboardProtocolMode.disambiguated;
  }
  return requested;
}

/// Typed record of the terminal state a native driver actually owns.
///
/// [effectiveMode] is the mode Fleury emitted after policy and transactional
/// fallback, not merely what the app requested. The ownership booleans record
/// which mutation paths Fleury entered (including a potentially partial
/// platform attempt), so restore and handoff never infer cleanup from a request.
final class ActiveTerminalState {
  ActiveTerminalState({
    required this.requestedMode,
    required this.effectiveMode,
    this.rawInputOwned = false,
    this.outputModesOwned = false,
  });

  final TerminalMode requestedMode;
  TerminalMode effectiveMode;
  bool rawInputOwned;
  bool outputModesOwned;
}

/// The single I/O boundary between the framework and a real terminal.
///
/// All bytes that ever reach stdout come through [write]; widget code
/// never gets a reference to this. Input events arrive via [events]
/// as typed [TuiEvent]s — the byte-level escape-sequence parsing is
/// internal to the driver's implementation.
///
/// The contract:
///
///   - [enter] is called once at startup. It puts the terminal into
///     the configured [TerminalMode] (raw input, alt screen, etc.) and
///     hooks resize / signal handlers.
///   - [restore] is called once at shutdown. It MUST be safe to call
///     in a `finally` block after an exception; the driver tracks what
///     it actually changed and only undoes those changes.
///     Successful restoration is an ownership barrier: pending startup or
///     handoff work must not subsequently reacquire modes, input, or output.
///     Fence or finish those operations before reporting success. Throw if
///     terminal ownership cannot be safely released.
///   - [write] is the single output path. Implementations buffer at
///     their own discretion; the framework calls it from the renderer
///     and expects bytes to land before the next frame is asked for.
///   - [events] is a broadcast stream. Multiple subscribers (focus
///     dispatcher, dev tools, debug overlay) can listen.
abstract interface class TerminalDriver {
  /// Current terminal size in cells. Reflects the most recent resize.
  CellSize get size;

  /// What the terminal can render — color depth, supported modes, etc.
  TerminalCapabilities get capabilities;

  /// Stream of typed input + resize events. Broadcast.
  Stream<TuiEvent> get events;

  /// Whether the driver is currently in interactive mode (between
  /// [enter] and [restore]).
  bool get isActive;

  /// Whether this driver is backed by an interactive terminal display —
  /// i.e. standard output is a real TTY rather than a pipe or file.
  ///
  /// When false, a visual TUI has nowhere meaningful to draw: emitting the
  /// cursor-positioning and screen-control sequences would just corrupt the
  /// redirected stream. `runApp` refuses to start in that case by default.
  /// (Input arriving from a pipe while output is still a terminal — scripted
  /// keystrokes — does not make a driver non-interactive.)
  bool get isInteractive;

  /// Puts the terminal into [mode] and returns the session facts established by
  /// setup/negotiation. Calling it on an already-entered driver is an error.
  Future<TerminalSessionProfile> enter(TerminalMode mode);

  /// Reverses everything [enter] configured. Safe to call after an
  /// exception. Idempotent — calling twice has no further effect.
  Future<void> restore();

  /// Writes raw bytes to the terminal's output stream. The framework
  /// guarantees these are pre-sanitized ANSI from the diff renderer —
  /// the driver does not re-validate.
  void write(String data);
}

/// Implemented by drivers whose output channel can back up — a remote
/// driver writing to a socket a slow peer drains. The frame program
/// defers frame PRODUCTION while [isOutputBacklogged] and resumes on
/// [outputDrained]: state keeps accumulating in the retained tree, the
/// diff base stays at the last frame the peer actually received, and the
/// resumed frame ships one coalesced patch. Local terminal drivers don't
/// implement this (a blocking stdout already applies backpressure).
abstract interface class OutputFlowControl {
  /// True while unsent output exceeds the channel's high-water mark.
  bool get isOutputBacklogged;

  /// Completes when the backlog drains — immediately when not
  /// backlogged, and always when the channel closes.
  Future<void> get outputDrained;
}

/// Optional terminal lifecycle hook for subprocesses, external editors, and
/// other workflows that need the user's terminal while a TUI is running.
///
/// Implementations restore the terminal-facing modes they own before running
/// [operation], then re-enter the previous TUI mode afterward. They should
/// suppress framework frame writes while the handoff is active and trigger a
/// repaint after resume.
abstract interface class TerminalHandoffDriver {
  Future<T> runWithTerminalHandoff<T>(FutureOr<T> Function() operation);
}

/// A native driver that can resize a live inline region.
abstract interface class InlineTerminalDriver {
  bool get isInline;

  /// Changes the requested row count, clamped to the physical terminal.
  /// Completes once the new region is reserved and a repaint is requested.
  /// While suspended or handed to a subprocess, stores the request instead;
  /// the new height takes effect when this session regains the terminal.
  Future<void> resizeInline(int rows);
}

/// A driver whose session can stop for the shell's job control: restore the
/// terminal, stop the job, and re-enter after `fg`.
///
/// `TerminalSession.supportsSuspend` and `TerminalSession.suspend` reach the
/// native POSIX driver through this, so the session stays free of `dart:io`.
/// Not exported: no other driver has job control.
@internal
abstract interface class TerminalSuspendDriver {
  /// See `TerminalSession.supportsSuspend`.
  bool get supportsSuspend;

  /// See `TerminalSession.suspend`.
  Future<bool> suspend();
}

/// Runs [operation] through [driver]'s handoff hook when supported.
///
/// Drivers that do not own terminal modes, such as remote render targets, can
/// simply skip [TerminalHandoffDriver]; callers still get a usable fallback.
Future<T> withTerminalHandoff<T>(
  TerminalDriver driver,
  FutureOr<T> Function() operation,
) {
  final handoff = driver;
  if (handoff is TerminalHandoffDriver) {
    return (handoff as TerminalHandoffDriver).runWithTerminalHandoff(operation);
  }
  return Future<T>.sync(operation);
}

/// Optional terminal-citizenship hook: set the window / tab title and raise
/// user attention. A driver mixes this in when its channel carries escape
/// sequences (local terminals do; a structured remote target may not), so the
/// driver's *presence* of this interface is the capability gate — callers go
/// through [setTerminalTitle] / [ringTerminalBell] / [notifyTerminal], which
/// no-op when the driver does not implement it.
///
/// The title (OSC 0/2) and bell (BEL) sequences are safe on every terminal (an
/// unsupported one ignores them); OSC 9 desktop notifications show only where
/// the terminal implements them, so [notify] is best-effort — pair it with
/// [ringBell] for a cue that always lands.
abstract interface class TerminalAttentionDriver {
  /// Sets the terminal window / tab title (OSC 0 *and* OSC 2, so both
  /// icon-name and window-title conventions are covered).
  void setTitle(String title);

  /// Rings the terminal bell (BEL) — a universal, always-delivered attention
  /// cue.
  void ringBell();

  /// Posts an OSC 9 desktop notification carrying [message] — best-effort and
  /// terminal-specific: iTerm2 (among others) shows it; terminals that don't
  /// implement OSC 9 ignore it. Note ConEmu / Windows Terminal treat part of
  /// the `OSC 9;` family as a progress/control channel, so a [message] starting
  /// with a digit-and-semicolon could be interpreted there rather than shown —
  /// pass human-readable text, and pair with [ringBell] for a cue that always
  /// lands.
  void notify(String message);
}

/// Default OSC/BEL implementation of [TerminalAttentionDriver] for any driver
/// with a byte [write] channel. The payload is sanitized so a stray control
/// character (a BEL or ESC) can't terminate the escape sequence early and
/// corrupt the stream.
mixin TerminalAttentionSequences implements TerminalAttentionDriver {
  /// The driver's raw output path — satisfied by [TerminalDriver.write].
  void write(String data);

  /// Whether output is a real terminal — satisfied by
  /// [TerminalDriver.isInteractive]. Attention sequences are suppressed when it
  /// is false, so raw OSC/BEL bytes never land in a redirected (piped / file)
  /// stdout — the same reason the enter/exit mode sequences are gated there.
  bool get isInteractive;

  @override
  void setTitle(String title) {
    if (!isInteractive) return;
    final s = sanitizeTerminalString(title);
    write('\x1B]0;$s\x07\x1B]2;$s\x07');
  }

  @override
  void ringBell() {
    if (!isInteractive) return;
    write('\x07');
  }

  @override
  void notify(String message) {
    if (!isInteractive) return;
    write('\x1B]9;${sanitizeTerminalString(message)}\x07');
  }
}

/// Replaces C0 controls, DEL, and C1 controls (`0x00-0x1F`, `0x7F-0x9F` —
/// including 7-bit BEL/ESC and 8-bit ST) with spaces, so a string is safe to
/// embed inside an OSC escape sequence. Multi-byte content (emoji, CJK,
/// surrogate halves) is all above `0x9F`, so it passes through intact.
String sanitizeTerminalString(String s) => String.fromCharCodes(
  s.codeUnits.map((c) => (c < 0x20 || (c >= 0x7F && c <= 0x9F)) ? 0x20 : c),
);

/// Sets the terminal title through [driver] when it supports it; no-op
/// otherwise.
void setTerminalTitle(TerminalDriver driver, String title) {
  if (driver is TerminalAttentionDriver) {
    (driver as TerminalAttentionDriver).setTitle(title);
  }
}

/// Rings the terminal bell through [driver] when it supports it; no-op
/// otherwise.
void ringTerminalBell(TerminalDriver driver) {
  if (driver is TerminalAttentionDriver) {
    (driver as TerminalAttentionDriver).ringBell();
  }
}

/// Posts an OSC 9 notification through [driver] when it supports it; no-op
/// otherwise.
void notifyTerminal(TerminalDriver driver, String message) {
  if (driver is TerminalAttentionDriver) {
    (driver as TerminalAttentionDriver).notify(message);
  }
}
