// The damage tracker's frame phases: which invalidations this frame covers
// and which owe the next frame.

import 'package:fleury/src/rendering/render_object.dart';
import 'package:test/test.dart';

void main() {
  group('RenderDamageTracker phases', () {
    test('during build and layout an invalidation is absorbed', () {
      final tracker = RenderDamageTracker();
      var requests = 0;
      tracker.onInvalidate = () => requests++;
      for (final phase in [RenderFramePhase.build, RenderFramePhase.layout]) {
        tracker.phase = phase;
        tracker.recordVisualChange();
        tracker.recordLayoutOrConservativePaint();
      }
      expect(requests, 0, reason: "this frame's paint covers them");
      expect(tracker.hasVisualChange, isTrue);
    });

    test('between frames an invalidation asks for a frame', () {
      final tracker = RenderDamageTracker();
      var requests = 0;
      tracker.onInvalidate = () => requests++;
      tracker.phase = RenderFramePhase.idle;
      tracker.recordVisualChange();
      expect(requests, 1);
      tracker.recordLayoutOrConservativePaint();
      expect(requests, 2);
    });

    test('during paint an invalidation asks for a frame and survives the '
        'take that closes this one', () {
      // The frame loop consumes both flags right after paint. What landed
      // during paint belongs to the next frame, not to nothing.
      final tracker = RenderDamageTracker();
      var requests = 0;
      tracker.onInvalidate = () => requests++;
      tracker.phase = RenderFramePhase.paint;
      tracker.recordVisualChange();
      expect(requests, 1);
      expect(tracker.takeVisualChange(), isTrue, reason: 'this frame');
      expect(tracker.hasVisualChange, isTrue, reason: 'carried');
      expect(tracker.takeVisualChange(), isTrue, reason: 'the next frame');
      expect(tracker.hasVisualChange, isFalse);

      tracker.recordLayoutOrConservativePaint();
      expect(tracker.takeRequiresFullDiff(), isTrue);
      expect(
        tracker.takeRequiresFullDiff(),
        isFalse,
        reason: 'only the visual-change flag carries; damage is a buffer diff',
      );
    });

    test('reset drops the carry', () {
      final tracker = RenderDamageTracker();
      tracker.phase = RenderFramePhase.paint;
      tracker.recordVisualChange();
      tracker.reset();
      expect(tracker.takeVisualChange(), isFalse);
      expect(tracker.takeVisualChange(), isFalse);
    });
  });

  group('paint-pass retraction is a one-shot owned by the sweep', () {
    test('an unpublished participant is retracted once, not every pass', () {
      final tracker = RenderDamageTracker();
      final participant = _CountingParticipant();
      tracker.registerPaintPassParticipant(participant);
      for (var pass = 0; pass < 3; pass++) {
        tracker.beginPaintPass();
        tracker.endPaintPass();
      }
      expect(
        participant.retractions,
        1,
        reason:
            'a participant that stays mounted without painting is '
            'unpublished on every later pass; asking it to retract each '
            'time is what made every frame request the next one',
      );
    });

    test('a fresh publish re-arms the retraction', () {
      final tracker = RenderDamageTracker();
      final participant = _CountingParticipant();
      tracker.registerPaintPassParticipant(participant);
      tracker.beginPaintPass();
      tracker.endPaintPass();
      expect(participant.retractions, 1);
      participant.published = tracker.beginPaintPass(); // painted this pass
      tracker.endPaintPass();
      expect(participant.retractions, 1);
      tracker.beginPaintPass(); // and not this one
      tracker.endPaintPass();
      expect(participant.retractions, 2);
    });

    test('reset also returns the phase to idle', () {
      final tracker = RenderDamageTracker()..phase = RenderFramePhase.layout;
      tracker.reset();
      expect(tracker.phase, RenderFramePhase.idle);
    });
  });
}

final class _CountingParticipant implements PaintPassParticipant {
  int published = -1;
  int retractions = 0;

  @override
  int get publishedPaintPass => published;

  @override
  void retractPaintFacts() {
    retractions++;
  }
}
