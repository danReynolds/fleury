// RFC 0020 §5.6/§6/§7 — the session regularizer's repair table, the frame
// latch contract, and consume() liveness. Headless: the session is a pure
// model.

import 'package:fleury/fleury_core.dart';
import 'package:fleury/src/input/key_dispatch.dart';
import 'package:fleury/src/input/keyboard_state.dart';
import 'package:test/test.dart';

KeyEvent _down(String c, {KeyPosition? position}) =>
    KeyEvent(KeyCode.char(c), position: position);
KeyEvent _up(String c, {KeyPosition? position}) =>
    KeyEvent(KeyCode.char(c), type: KeyEventType.up, position: position);
KeyEvent _repeat(String c) =>
    KeyEvent(KeyCode.char(c), type: KeyEventType.repeat);

void main() {
  _phaseViolationRecovery();
  group('capability gating (the legacy/test-harness profile)', () {
    test('a release-less source is never "repaired"', () {
      final session = KeyboardSession(); // legacy default
      // Two fresh downs of the same key: on legacy that IS two presses.
      expect(session.ingest(_down('a')).events, [_down('a')]);
      expect(session.ingest(_down('a')).events, [_down('a')]);
      // Repeat-without-down passes through unrepaired.
      expect(session.ingest(_repeat('j')).events, [_repeat('j')]);
    });

    test('sampled state stays empty without held-state support', () {
      final session = KeyboardSession();
      session.ingest(_down('a'));
      final snap = session.publishLatch();
      expect(snap.pressed, isEmpty);
      expect(snap.isHeld(KeyCode.a), isFalse);
      expect(snap.wasPressed(KeyCode.a), isFalse);
    });
  });

  group('repair table (§6, held-state profile)', () {
    KeyboardSession full() =>
        KeyboardSession(capabilities: KeyboardCapabilities.full);

    test('down / up maintain records and edges', () {
      final session = full();
      session.ingest(_down('w', position: KeyPosition.w));
      var snap = session.publishLatch();
      expect(snap.isHeld(KeyPosition.w), isTrue);
      expect(snap.wasPressed(KeyPosition.w), isTrue);
      expect(snap.wasReleased(KeyPosition.w), isFalse);

      session.ingest(_up('w', position: KeyPosition.w));
      snap = session.publishLatch();
      expect(snap.isHeld(KeyPosition.w), isFalse);
      expect(snap.wasReleased(KeyPosition.w), isTrue);
    });

    test('duplicate down while held demotes to repeat', () {
      final session = full();
      session.ingest(_down('a'));
      final regularized = session.ingest(_down('a'));
      expect(regularized.events.single.type, KeyEventType.repeat);
      // Still exactly one held record.
      expect(session.publishLatch().pressed, {KeyCode.a});
    });

    test('repeat without down synthesizes a command-eligible down', () {
      final session = full();
      final regularized = session.ingest(_repeat('a'));
      expect(regularized.events, hasLength(2));
      expect(regularized.events[0].type, KeyEventType.down);
      expect(regularized.events[0].synthesized, isTrue);
      expect(regularized.events[1], _repeat('a'));
      expect(session.publishLatch().isHeld(KeyCode.a), isTrue);
    });

    test('an unheld up is observable but corrupts nothing', () {
      final session = full();
      final regularized = session.ingest(_up('q'));
      expect(regularized.events.single.type, KeyEventType.up);
      final snap = session.publishLatch();
      expect(snap.pressed, isEmpty);
      expect(snap.wasReleased(KeyCode.q), isFalse);
    });

    test('repeats touch neither edge set', () {
      final session = full();
      session.ingest(_down('a'));
      session.publishLatch();
      session.ingest(_repeat('a'));
      final snap = session.publishLatch();
      // The repeat dirtied nothing: held unchanged, no edges. The latch is
      // the edge-free view.
      expect(snap.isHeld(KeyCode.a), isTrue);
      expect(snap.wasPressed(KeyCode.a), isFalse);
      expect(snap.wasReleased(KeyCode.a), isFalse);
    });
  });

  group('frame latch contract (§5.6)', () {
    KeyboardSession full() =>
        KeyboardSession(capabilities: KeyboardCapabilities.full);

    test('a sub-frame tap is visible to wasPressed exactly once', () {
      final session = full();
      session.ingest(_down(' '));
      session.ingest(_up(' '));
      final snap = session.publishLatch();
      expect(snap.isHeld(KeyCode.space), isFalse);
      expect(snap.wasPressed(KeyCode.space), isTrue);
      expect(snap.wasReleased(KeyCode.space), isTrue);
      // Next latch: the edges have expired.
      final next = session.publishLatch();
      expect(next.wasPressed(KeyCode.space), isFalse);
      expect(next.wasReleased(KeyCode.space), isFalse);
    });

    test('down→up→down in one frame: both edges AND held', () {
      final session = full();
      session.ingest(_down('a'));
      session.ingest(_up('a'));
      session.ingest(_down('a'));
      final snap = session.publishLatch();
      expect(snap.isHeld(KeyCode.a), isTrue);
      expect(snap.wasPressed(KeyCode.a), isTrue);
      expect(snap.wasReleased(KeyCode.a), isTrue);
    });

    test('the latch is stable and allocation-free when quiet', () {
      final session = full();
      session.ingest(_down('a'));
      final edgeful = session.publishLatch();
      final quiet1 = session.publishLatch(); // expires edges (new instance)
      final quiet2 = session.publishLatch(); // fully quiet: cached
      expect(identical(quiet1, quiet2), isTrue);
      expect(quiet1.isHeld(KeyCode.a), isTrue);
      // Different content ⇒ different ordinal: a consumer memoizing
      // "already handled frame N" must not mistake the expired successor
      // for the edgeful snapshot.
      expect(quiet1.frameNumber, isNot(edgeful.frameNumber));
    });

    test('a paused consumer gets no backlog', () {
      final session = full();
      session.ingest(_down('a'));
      session.ingest(_up('a'));
      session.publishLatch(); // frame the consumer missed
      session.ingest(_down('b'));
      session.ingest(_up('b'));
      session.publishLatch(); // another missed frame
      final resumed = session.publishLatch();
      expect(resumed.wasPressed(KeyCode.a), isFalse);
      expect(resumed.wasPressed(KeyCode.b), isFalse);
    });
  });

  group('per-press identity matching (§13.3)', () {
    test('a positional press matches position-first, never twin-fallback', () {
      final session = KeyboardSession(capabilities: KeyboardCapabilities.full);
      // AZERTY: the QWERTY-W spot types 'z'.
      session.ingest(_down('z', position: KeyPosition.w));
      final snap = session.publishLatch();
      expect(snap.isHeld(KeyPosition.w), isTrue);
      expect(snap.isHeld(const KeyCode.char('z')), isTrue);
      expect(snap.isHeld(KeyPosition.z), isFalse);
      expect(snap.positionsPressed, {KeyPosition.w});
    });

    test('uneven position reporting still closes the press it opened', () {
      // Position is optional PER EVENT even on a confirmed surface (§4:
      // flag 4 is "can send"; the DOM reports 'Unidentified'). A down with
      // a position closed by an up without one — and the reverse — must
      // not split into two records and wedge the key as held.
      final session = KeyboardSession(capabilities: KeyboardCapabilities.full);
      session.ingest(_down('w', position: KeyPosition.w));
      session.ingest(_up('w')); // same key, position omitted
      var snap = session.publishLatch();
      expect(snap.pressed, isEmpty, reason: 'positionless up closed it');
      expect(snap.isHeld(KeyPosition.w), isFalse);

      session.ingest(_down('a'));
      session.ingest(_up('a', position: KeyPosition.a)); // reverse mismatch
      snap = session.publishLatch();
      expect(snap.pressed, isEmpty);
    });

    test('a positionless duplicate down does not open a second record', () {
      final session = KeyboardSession(capabilities: KeyboardCapabilities.full);
      session.ingest(_down('w', position: KeyPosition.w));
      final regularized = session.ingest(_down('w')); // no position
      expect(regularized.events.single.type, KeyEventType.repeat);
      session.ingest(_up('w', position: KeyPosition.w));
      expect(session.publishLatch().pressed, isEmpty);
    });

    test('a positionless press degrades one-way to the US twin', () {
      final session = KeyboardSession(capabilities: KeyboardCapabilities.full);
      session.ingest(_down('w'));
      final snap = session.publishLatch();
      expect(snap.isHeld(KeyPosition.w), isTrue); // twin degradation
      expect(snap.isHeld(KeyCode.w), isTrue);
      expect(snap.positionsPressed, isEmpty);
    });
  });

  group('authority loss and session replacement (§6)', () {
    KeyboardSession full() =>
        KeyboardSession(capabilities: KeyboardCapabilities.full);

    test('loseAuthority synthesizes one release per held key', () {
      final session = full();
      session.ingest(_down('w', position: KeyPosition.w));
      session.ingest(_down('a'));
      final releases = session.loseAuthority();
      expect(releases, hasLength(2));
      expect(releases.every((e) => e.type == KeyEventType.up), isTrue);
      expect(releases.every((e) => e.synthesized), isTrue);
      final snap = session.publishLatch();
      expect(snap.pressed, isEmpty);
      expect(snap.wasReleased(KeyPosition.w), isTrue);
    });

    test('replaceSession bumps the generation and drops pending edges', () {
      final session = full();
      session.ingest(_down('a'));
      final before = session.sessionGeneration;
      session.replaceSession();
      expect(session.sessionGeneration, before + 1);
      final snap = session.publishLatch();
      expect(snap.sessionGeneration, before + 1);
      expect(snap.pressed, isEmpty);
      expect(snap.wasPressed(KeyCode.a), isFalse); // dropped, not replayed
    });

    test('a capability downgrade recovers held keys', () {
      final session = full();
      session.ingest(_down('a'));
      final releases = session.updateCapabilities(KeyboardCapabilities.legacy);
      expect(releases, hasLength(1));
      expect(session.publishLatch().pressed, isEmpty);
    });
  });

  group('consume() liveness (§17.2)', () {
    test('outside any dispatch: debug error', () {
      expect(
        () => const KeyEvent(KeyCode.enter).consume(),
        throwsA(isA<AssertionError>()),
      );
    });

    test('inside a non-entitled frame: debug error', () {
      expect(
        () => KeyDispatchContext.run(
          () => const KeyEvent(KeyCode.enter).consume(),
          entitled: false,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('inside an entitled frame: consumes, reported by run()', () {
      final consumed = KeyDispatchContext.run(
        () => const KeyEvent(KeyCode.enter).consume(),
        entitled: true,
      );
      expect(consumed, isTrue);
    });

    test('nested frames are independent', () {
      final outer = KeyDispatchContext.run(() {
        final inner = KeyDispatchContext.run(
          () => const KeyEvent(KeyCode.enter).consume(),
          entitled: true,
        );
        expect(inner, isTrue);
      }, entitled: true);
      expect(outer, isFalse);
    });
  });
}

void _phaseViolationRecovery() {
  group('phase-violation suspicion is retired by positive evidence', () {
    test('two dropped releases, hours apart, must NOT demote', () {
      // The counter used to be a one-way ratchet: any two duplicate-downs
      // across a whole session demoted a perfectly honest terminal, with no
      // path back. A real `:2` or `:3` in between proves the surface DOES
      // implement phases, which is exactly the evidence that should clear it.
      final session = KeyboardSession(capabilities: KeyboardCapabilities.full);
      const a = KeyEvent(KeyCode.a, position: KeyPosition.a);

      // Strike one: a release went missing, so this down lands while held.
      session.ingest(a);
      session.ingest(a);
      expect(session.capabilities.supportsHeldState, isTrue);

      // The terminal then demonstrates it really does report phases.
      session.ingest(
        const KeyEvent(
          KeyCode.a,
          position: KeyPosition.a,
          type: KeyEventType.up,
        ),
      );

      // Strike two, much later. On a ratcheting counter this demotes.
      session.ingest(a);
      session.ingest(a);
      expect(
        session.capabilities.supportsHeldState,
        isTrue,
        reason:
            'an honest terminal that proved itself between two dropped '
            'releases must not be demoted',
      );
    });

    test('a real `:2` repeat is positive evidence too', () {
      // The repeat branch needs its own case: a terminal can prove it honours
      // phases by marking auto-repeats without ever dropping a release, and
      // the first version of this fix left that path uncovered.
      final session = KeyboardSession(capabilities: KeyboardCapabilities.full);
      const a = KeyEvent(KeyCode.a, position: KeyPosition.a);
      session.ingest(a);
      session.ingest(a); // strike one
      session.ingest(
        const KeyEvent(
          KeyCode.a,
          position: KeyPosition.a,
          type: KeyEventType.repeat,
        ),
      );
      session.ingest(a); // would be strike two on a ratcheting counter
      expect(session.capabilities.supportsHeldState, isTrue);
    });

    test('an unbroken run of duplicate downs still demotes', () {
      // The recovery path must not disarm the detector: Warp emits bare
      // presses for every auto-repeat and never a phase, so nothing ever
      // clears the count.
      final session = KeyboardSession(capabilities: KeyboardCapabilities.full);
      const a = KeyEvent(KeyCode.a, position: KeyPosition.a);
      session.ingest(a);
      session.ingest(a);
      session.ingest(a);
      expect(session.capabilities.supportsHeldState, isFalse);
    });
  });

  test('the liar detector re-arms after a capability re-upgrade', () {
    // After a demotion the violation counter rests at 2. A later re-grant of
    // held state (reconnect, driver swap, renegotiation) must reset it: with
    // an exact `== 2` demotion check, the next violation would move the
    // counter PAST 2 and the detector would never fire again — keys sticking
    // down forever on exactly the surfaces that lie about phases.
    final session = KeyboardSession(capabilities: KeyboardCapabilities.full);
    const w = KeyEvent(KeyCode.w, position: KeyPosition.w);
    session.ingest(w);
    session.ingest(w); // strike one
    session.ingest(w); // strike two: demoted
    expect(session.capabilities.supportsHeldState, isFalse);

    session.updateCapabilities(KeyboardCapabilities.full); // fresh trust
    expect(session.capabilities.supportsHeldState, isTrue);
    session.ingest(w);
    session.ingest(w); // strike one (fresh)
    expect(
      session.capabilities.supportsHeldState,
      isTrue,
      reason: 'one violation under fresh trust is not enough',
    );
    session.ingest(w); // strike two: must demote AGAIN
    expect(
      session.capabilities.supportsHeldState,
      isFalse,
      reason: 'the detector must re-arm after re-upgrade',
    );
  });
}
