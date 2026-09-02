// RFC 0020 §5.6 — wiring the sampled keyboard latch to its two clocks.
//
// One function, used by every host (terminal `runApp`, browser
// `runTuiSurface`, and the FleuryTester harness), so "how the latch is
// published" cannot diverge between production and tests. It diverged once
// already: the harness published from `TickerScheduler.onFrameStart` while
// production published from the FrameDriver, which made a whole corpus of
// sampled-input tests agree with a contract the runtime did not implement.

import '../animation/ticker_scheduler.dart';
import 'keyboard_state.dart';

/// Installs both latch clocks on [session] and returns the frame-clock
/// publisher a host hands to `FrameDriver.onLatchInput`.
///
/// After this call:
///
///  * `scheduler.onFrameStart` publishes on [KeyboardLatchClock.ticker],
///    ahead of every tick callback, so all sampling consumers in one tick
///    agree and edges expire on the clock that reads them;
///  * the returned callback publishes on [KeyboardLatchClock.frame], and is
///    live only while no ticker is registered;
///  * [KeyboardSession.hasActiveTickers] reads [TickerScheduler.isActive], so
///    the handover between the two follows ticker registration with no flag
///    to keep in sync.
///
/// Both are always wired; the session decides which one publishes. Calling a
/// host's own `publishLatch` in addition to these is the double-publisher
/// defect — don't.
void Function() installKeyboardLatch({
  required KeyboardSession session,
  required TickerScheduler scheduler,
}) {
  session.hasActiveTickers = () => scheduler.isActive;
  scheduler.onFrameStart = () =>
      session.publishLatch(KeyboardLatchClock.ticker);
  return () => session.publishLatch(KeyboardLatchClock.frame);
}
