// The child half of the dev supervisor's signal handshake.
//
// Deliberately tiny and dependency-free (dart:io + dart:developer): the
// terminal driver is the only place that knows a process-termination signal
// actually reached this process, and that fact has to travel to the
// supervisor without dragging the supervisor's machinery into the driver.
import 'dart:developer' as developer;
import 'dart:io';

/// The `postEvent` kind a supervised app posts when SIGINT/SIGTERM lands on
/// it. Payload: `{'signal': 'SIGINT'}`.
///
/// It answers the one thing the supervisor cannot observe: whether a signal
/// it received was a tty-generated one (the line discipline signalled the
/// whole foreground group, so the app got its own copy) or a direct
/// `kill <supervisor-pid>` (the app got nothing and the supervisor must
/// forward, or the session outlives the kill). Without it the supervisor can
/// only guess by waiting, and a guess short enough to keep `kill` responsive
/// is short enough to cut a real teardown short. One constant — the match is
/// a silent string compare, so a drifted literal turns the ack into a no-op
/// with no error anywhere.
const String kDevSignalAckEvent = 'fleury.signalAck';

/// Tells a listening dev supervisor that [signal] was delivered to THIS
/// process, so it does not have to forward its own copy.
///
/// Fire-and-forget and free when nobody is listening (no VM service, or no
/// supervisor): posting is what the app already does for hot-restart
/// requests. Called once per delivered signal, i.e. at most a handful of
/// times in a process's life.
void postDevSignalAck(ProcessSignal signal) {
  try {
    developer.postEvent(kDevSignalAckEvent, {'signal': signal.name});
  } catch (_) {
    // Never let dev tooling interfere with shutdown: without the ack the
    // supervisor falls back to its forward backstop, which is exactly the
    // pre-ack behaviour.
  }
}
