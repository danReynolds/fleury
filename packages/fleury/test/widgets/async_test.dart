import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

String _render(FleuryTester tester) =>
    tester.renderToString(size: const CellSize(16, 1)).trim();

Widget _view<T>(AsyncSnapshot<T> snap) {
  if (snap.connectionState == ConnectionState.waiting) {
    return const Text('loading');
  }
  if (snap.hasError) return Text('error:${snap.error}');
  if (snap.hasData) return Text('data:${snap.data}');
  return const Text('none');
}

void main() {
  group('FutureBuilder', () {
    testWidgets('waiting → data', (tester) async {
      final completer = Completer<int>();
      tester.pumpWidget(
        FutureBuilder<int>(
          future: completer.future,
          builder: (_, snap) => _view(snap),
        ),
      );
      expect(_render(tester), 'loading');

      completer.complete(42);
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      expect(_render(tester), 'data:42');
    });

    testWidgets('waiting → error', (tester) async {
      final completer = Completer<int>();
      tester.pumpWidget(
        FutureBuilder<int>(
          future: completer.future,
          builder: (_, snap) => _view(snap),
        ),
      );
      completer.completeError('boom');
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      expect(_render(tester), 'error:boom');
    });

    testWidgets('initialData shows before the future resolves', (tester) async {
      tester.pumpWidget(
        FutureBuilder<int>(
          future: Completer<int>().future, // never completes
          initialData: 7,
          builder: (_, snap) =>
              Text('${snap.connectionState.name}:${snap.data}'),
        ),
      );
      expect(_render(tester), 'waiting:7');
    });

    testWidgets('a stale future does not overwrite a newer one', (
      tester,
    ) async {
      final slow = Completer<int>();
      final fast = Completer<int>();
      tester.pumpWidget(
        FutureBuilder<int>(
          future: slow.future,
          builder: (_, snap) => _view(snap),
        ),
      );
      // Swap to a different future before the first resolves.
      tester.pumpWidget(
        FutureBuilder<int>(
          future: fast.future,
          builder: (_, snap) => _view(snap),
        ),
      );
      fast.complete(2);
      slow.complete(1); // resolves later but is stale — must be ignored
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      expect(_render(tester), 'data:2');
    });
  });

  group('StreamBuilder', () {
    testWidgets('waiting → events → done', (tester) async {
      final controller = StreamController<int>();
      tester.pumpWidget(
        StreamBuilder<int>(
          stream: controller.stream,
          builder: (_, snap) =>
              Text('${snap.connectionState.name}:${snap.data ?? '-'}'),
        ),
      );
      expect(_render(tester), 'waiting:-');

      controller.add(1);
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      expect(_render(tester), 'active:1');

      controller.add(2);
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      expect(_render(tester), 'active:2');

      await controller.close();
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      expect(_render(tester), 'done:2', reason: 'last value retained on close');
    });

    testWidgets('surfaces stream errors', (tester) async {
      final controller = StreamController<int>();
      tester.pumpWidget(
        StreamBuilder<int>(
          stream: controller.stream,
          builder: (_, snap) => _view(snap),
        ),
      );
      controller.addError('nope');
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      expect(_render(tester), 'error:nope');
    });

    testWidgets('cancels its subscription on unmount', (tester) async {
      final controller = StreamController<int>();
      tester.pumpWidget(
        StreamBuilder<int>(
          stream: controller.stream,
          builder: (_, snap) => _view(snap),
        ),
      );
      tester.pumpWidget(const Text('gone')); // unmounts the StreamBuilder
      // If the subscription weren't cancelled, this would push to a
      // disposed State and throw on the next pump.
      controller.add(99);
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      expect(_render(tester), 'gone');
      expect(controller.hasListener, isFalse, reason: 'subscription cancelled');
    });
  });
}
