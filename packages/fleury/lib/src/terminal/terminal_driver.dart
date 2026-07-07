import 'dart:async' show FutureOr;

import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import '../input/events.dart';
import '../runtime/remote_surface_sink.dart';
import 'capabilities.dart';

/// The set of terminal modes the driver should enable for a TUI session.
///
/// Defaults to the standard interactive TUI configuration (raw input,
/// alternate screen, hidden cursor, style reset on exit). Callers can
/// opt out of individual modes — for example, debug tools may want to
/// run without alternate screen so output stays in scrollback.
@immutable
final class TerminalMode {
  const TerminalMode({
    this.rawInput = true,
    this.alternateScreen = true,
    this.hideCursor = true,
    this.resetStyleOnExit = true,
    this.bracketedPaste = true,
    this.kittyKeyboard = true,
    this.mouse = false,
    this.mouseMotion = false,
  });

  /// The standard interactive TUI mode.
  static const TerminalMode interactive = TerminalMode();

  /// Inline mode: no alternate screen, cursor visible, raw input still
  /// on. Useful for in-place output that should remain in the user's
  /// scrollback after exit.
  static const TerminalMode inline = TerminalMode(
    alternateScreen: false,
    hideCursor: false,
  );

  final bool rawInput;
  final bool alternateScreen;
  final bool hideCursor;
  final bool resetStyleOnExit;

  /// Enable bracketed paste (DEC 2004) so pasted text — including its
  /// newlines — arrives as one [PasteEvent] instead of line-by-line
  /// Enter chords. On by default; it's harmless and only helps.
  final bool bracketedPaste;

  /// Negotiate the Kitty keyboard protocol (CSI-u) by pushing the
  /// "disambiguate escape codes" flag on enter and popping it on exit.
  /// On by default: terminals that support it then report otherwise-
  /// ambiguous chords (lone Esc, Ctrl+I vs Tab, Ctrl+M vs Enter) and the
  /// super/meta modifiers unambiguously; terminals that don't silently
  /// ignore the unknown sequence, so it's safe everywhere.
  final bool kittyKeyboard;

  /// Enable SGR mouse reporting (clicks, drags, wheel). Off by default:
  /// capturing the mouse takes over the terminal's own text selection,
  /// which many users rely on, so it's strictly opt-in.
  final bool mouse;

  /// Also report bare pointer motion (no button held), enabling hover
  /// (`MouseRegion`). Implies [mouse]. Off by default since motion
  /// reporting is chatty — only turn it on if you use hover.
  final bool mouseMotion;
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

  /// Puts the terminal into [mode]. Must be called before any I/O
  /// happens. Idempotent — calling it twice on an already-entered
  /// driver is a programming error.
  Future<void> enter(TerminalMode mode);

  /// Reverses everything [enter] configured. Safe to call after an
  /// exception. Idempotent — calling twice has no further effect.
  Future<void> restore();

  /// Writes raw bytes to the terminal's output stream. The framework
  /// guarantees these are pre-sanitized ANSI from the diff renderer —
  /// the driver does not re-validate.
  void write(String data);

  /// The structured presentation sink this session negotiated, or null
  /// for byte (ANSI) presentation — the answer every driver owns.
  ///
  /// Negotiation rides the connection handshake, so the value is
  /// meaningful only after [enter] returns: a structured remote driver
  /// returns its sink once the peer declared a plan-capable protocol
  /// version, and null for a v1 byte peer. Ordinary terminals always
  /// return null. `runApp` builds the matching presenter around the
  /// answer (wire plans vs ANSI diff) — the driver never constructs
  /// presenters, which need host-owned services.
  RemoteSurfaceSink? get surfaceSink;
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

  /// Posts an OSC 9 desktop notification carrying [message] where the terminal
  /// supports it; silently ignored otherwise.
  void notify(String message);
}

/// Default OSC/BEL implementation of [TerminalAttentionDriver] for any driver
/// with a byte [write] channel. The payload is sanitized so a stray control
/// character (a BEL or ESC) can't terminate the escape sequence early and
/// corrupt the stream.
mixin TerminalAttentionSequences implements TerminalAttentionDriver {
  /// The driver's raw output path — satisfied by [TerminalDriver.write].
  void write(String data);

  @override
  void setTitle(String title) {
    final s = sanitizeTerminalString(title);
    write('\x1B]0;$s\x07\x1B]2;$s\x07');
  }

  @override
  void ringBell() => write('\x07');

  @override
  void notify(String message) =>
      write('\x1B]9;${sanitizeTerminalString(message)}\x07');
}

/// Replaces C0 control characters and DEL (including BEL and ESC) with spaces,
/// so a string is safe to embed inside an OSC escape sequence.
String sanitizeTerminalString(String s) => String.fromCharCodes(
  s.codeUnits.map((c) => (c < 0x20 || c == 0x7F) ? 0x20 : c),
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
