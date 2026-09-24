import 'dart:async';

import '../terminal/terminal_driver.dart';
import 'framework.dart';

/// The terminal session an app runs in — the one thing `runApp` owns that an
/// app sometimes needs to borrow: the terminal itself, for a child process.
///
/// Read it with [TerminalSession.of]. `runApp` installs a [TerminalSessionScope]
/// above the app root. A served or embedded session has no terminal to hand
/// off ([supportsHandoff] is false) and [runWithHandoff] simply runs the
/// operation; the browser runtime installs no scope at all, so code that runs
/// on both surfaces reads [maybeOf].
///
/// Why this exists: `runApp` captures the process's stdout and stderr (stray
/// output lands in the log buffer, not on the screen), so a child process that
/// inherits stdio outside [runWithHandoff] inherits the CAPTURE PIPES, not the
/// terminal — `$EDITOR` draws into the log buffer while eating raw keystrokes
/// and the app looks frozen. Before this scope, the driver was unreachable
/// from a default `runApp`, so that was the only outcome.
final class TerminalSession {
  const TerminalSession(this.driver);

  /// The session's driver — the single owner of the terminal, read-only.
  /// Pass it to helpers that take one: `editTextInExternalEditor`,
  /// `setTerminalTitle`, `ringTerminalBell`, `notifyTerminal`.
  final TerminalDriver driver;

  /// Whether [driver] can hand the terminal to a child at all.
  bool get supportsHandoff => driver is TerminalHandoffDriver;

  /// Whether this native session owns an inline region.
  bool get isInline =>
      driver is InlineTerminalDriver &&
      (driver as InlineTerminalDriver).isInline;

  /// Resizes a live inline region. Call from an interaction or lifecycle
  /// callback, not while building. Full-screen and remote sessions retain
  /// their host's size and reject this operation.
  /// During suspend or subprocess handoff, the request takes effect on return.
  Future<void> resizeInline(int rows) {
    if (!isInline) {
      throw StateError('This session does not own an inline terminal region.');
    }
    return (driver as InlineTerminalDriver).resizeInline(rows);
  }

  /// Runs [operation] with the terminal handed to it: cooked input, main
  /// screen, mouse off, frame writes suppressed, and `runApp`'s stray-output
  /// capture paused so a child that inherits stdio gets the real descriptors.
  /// The session re-enters afterwards and repaints in full.
  ///
  /// Any child that needs the terminal — an editor, a pager, an interactive
  /// `git` — must run inside this.
  Future<T> runWithHandoff<T>(FutureOr<T> Function() operation) =>
      withTerminalHandoff(driver, operation);

  /// The nearest session, or null on a surface without one (the browser).
  static TerminalSession? maybeOf(BuildContext context) =>
      dependOnScope<TerminalSession>(context);

  /// The nearest session; throws when there is none.
  static TerminalSession of(BuildContext context) {
    final session = maybeOf(context);
    if (session == null) {
      throw StateError(
        'TerminalSession.of: no TerminalSessionScope ancestor. Run under '
        'runApp (which installs one), wrap the subtree in a '
        'TerminalSessionScope, or use TerminalSession.maybeOf on a surface '
        'without a terminal.',
      );
    }
    return session;
  }
}

/// Provides a [TerminalSession] to a subtree. `runApp` installs one above the
/// app root; tests and hosts with their own driver can install their own.
final class TerminalSessionScope extends Scope<TerminalSession> {
  const TerminalSessionScope({
    super.key,
    required this.session,
    required super.child,
  }) : super(session);

  final TerminalSession session;

  @override
  bool updateShouldNotify(TerminalSessionScope oldWidget) =>
      !identical(oldWidget.session.driver, session.driver);
}
