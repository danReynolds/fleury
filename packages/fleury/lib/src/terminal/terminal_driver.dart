import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import 'capabilities.dart';
import 'events.dart';

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
  /// redirected stream. `runTui` refuses to start in that case by default.
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
}
