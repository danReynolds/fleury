import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _Model extends Notifier {
  int count = 0;

  void increment() {
    count += 1;
    notify();
  }
}

class _MixedModel with Notifier {
  void publish() => notify();
}

class _OverriddenValue extends ValueNotifier<int> {
  _OverriddenValue() : super(0);

  int calls = 0;

  @override
  void notify() {
    calls += 1;
    super.notify();
  }
}

class _ObservedScrollController extends ScrollController {
  int notifications = 0;

  @override
  void notify() {
    notifications++;
    super.notify();
  }
}

class _ObservedRenderText extends RenderText {
  _ObservedRenderText() : super(text: 'select me');

  int notifications = 0;

  @override
  void notify() {
    notifications++;
    super.notify();
  }
}

void main() {
  group('Notifier', () {
    test('controller subclasses observe notifications through notify', () {
      final controller = _ObservedScrollController();
      addTearDown(controller.dispose);
      var calls = 0;
      controller.listen(() => calls++);

      controller.offset = 3;

      expect(controller.notifications, 1);
      expect(calls, 1);
    });

    test(
      'selection notifications route through a renderer notify override',
      () {
        final text = _ObservedRenderText();
        addTearDown(text.dispose);
        text.layout(const CellConstraints());
        text.paint(CellBuffer(const CellSize(12, 1)), CellOffset.zero);
        final before = text.notifications;
        var calls = 0;
        text.listen(() => calls++);

        text.dispatchSelectionEvent(
          const SelectionGranularEvent(granularity: SelectionGranularity.all),
        );

        expect(text.notifications, before + 1);
        expect(calls, 1);
      },
    );

    test(
      'a listener failure reaches its zone without skipping later listeners',
      () {
        final model = _Model();
        addTearDown(model.dispose);
        final failure = StateError('listener failed');
        final errors = <Object>[];
        final seen = <int>[];
        model.listen(() => throw failure);
        model.listen(() => seen.add(model.count));

        runZonedGuarded(model.increment, (error, stack) => errors.add(error));

        expect(errors, [same(failure)]);
        expect(seen, [1]);
      },
    );

    test('publishes ordinary field changes to subscribers', () {
      final model = _Model();
      addTearDown(model.dispose);
      final seen = <int>[];
      final cancel = model.listen(() => seen.add(model.count));

      model.increment();
      model.increment();
      cancel();
      model.increment();

      expect(seen, [1, 2]);
      expect(model.hasListeners, isFalse);
    });

    test(
      'cancellation is independent and idempotent for duplicate callbacks',
      () {
        final model = _Model();
        addTearDown(model.dispose);
        var calls = 0;
        void listener() => calls += 1;
        final cancelFirst = model.listen(listener);
        final cancelSecond = model.listen(listener);
        model.addListener(listener);

        cancelSecond();
        cancelSecond();
        model.increment();
        expect(calls, 2);

        // The subscription wrapper must not remove the direct registration.
        model.removeListener(listener);
        model.increment();
        expect(calls, 3);

        cancelFirst();
        expect(model.hasListeners, isFalse);
      },
    );

    test(
      'canceling a later subscription suppresses it during a notification',
      () {
        final model = _Model();
        addTearDown(model.dispose);
        late VoidCallback cancelLater;
        var laterCalls = 0;
        model.listen(() => cancelLater());
        cancelLater = model.listen(() => laterCalls += 1);

        model.increment();
        model.increment();

        expect(laterCalls, 0);
      },
    );

    test(
      'self cancellation stays canceled through a reentrant notification',
      () {
        final model = _Model();
        addTearDown(model.dispose);
        late VoidCallback cancel;
        var selfCalls = 0;
        var otherCalls = 0;
        cancel = model.listen(() {
          selfCalls += 1;
          cancel();
          model.increment();
        });
        model.listen(() => otherCalls += 1);

        model.increment();
        model.increment();

        expect(selfCalls, 1);
        expect(otherCalls, 3);
      },
    );

    test(
      'subscriptions added during a notification start on the next pass',
      () {
        final model = _Model();
        addTearDown(model.dispose);
        var added = false;
        var laterCalls = 0;
        model.listen(() {
          if (!added) {
            added = true;
            model.listen(() => laterCalls += 1);
          }
        });

        model.increment();
        expect(laterCalls, 0);
        model.increment();
        expect(laterCalls, 1);
      },
    );

    test('dispose during notification suppresses remaining subscriptions', () {
      final model = _Model();
      var laterCalls = 0;
      model.listen(model.dispose);
      final cancel = model.listen(() => laterCalls += 1);

      model.increment();

      expect(laterCalls, 0);
      expect(model.hasListeners, isFalse);
      expect(cancel, returnsNormally);
      expect(cancel, returnsNormally);
      expect(() => model.listen(() {}), throwsStateError);
      expect(model.increment, throwsStateError);
    });

    test('Notifier works directly, as a superclass, and as a mixin', () {
      final instances = <Notifier>[
        Notifier(),
        _Model(),
        _MixedModel(),
        ValueNotifier(0),
      ];
      var calls = 0;
      for (final notifier in instances) {
        addTearDown(notifier.dispose);
        notifier.listen(() => calls += 1);
        expect(notifier, isA<Listenable>());
      }

      (instances[1] as _Model).increment();
      (instances[2] as _MixedModel).publish();
      (instances[3] as ValueNotifier<int>).value = 1;

      expect(calls, 3);
    });

    test('value assignment routes through a notify override', () {
      final value = _OverriddenValue();
      addTearDown(value.dispose);
      final seen = <int>[];
      value.listen(() => seen.add(value.value));

      value.value = 1;
      value.value = 1;

      expect(seen, [1]);
      expect(value.calls, 1);
    });
  });
}
