import 'dart:async';
import 'dart:typed_data';

import 'package:fleury/src/remote/buffered_browser_input.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('a post-listen burst cannot exceed the queued-byte cap', () async {
    final source = StreamController<dynamic>(sync: true);
    int? closeCode;
    String? closeReason;
    final input = BufferedBrowserInput.forStream(
      source.stream,
      maxMessageBytes: 10,
      maxQueuedBytes: 10,
      closeSource: (code, reason) async {
        closeCode = code;
        closeReason = reason;
      },
    );
    final errors = <Object>[];
    final subscription = input.stream.listen(
      (_) {},
      onError: (Object error) => errors.add(error),
    );

    // Both source events arrive synchronously before the async controller can
    // advance the first one downstream. The second would take retained input
    // above the cap even though the browser is already paired/listened.
    source
      ..add(Uint8List(6))
      ..add(Uint8List(6));
    await input.closed;
    await Future<void>.delayed(Duration.zero);

    expect(closeCode, 1009);
    expect(closeReason, 'input too large');
    expect(errors, hasLength(1));
    expect(errors.single, isA<RemoteProtocolException>());
    expect((errors.single as RemoteProtocolException).recoverable, isFalse);

    await subscription.cancel();
    await input.dispose();
    await source.close();
  });

  test('empty-message floods cannot bypass the byte cap', () async {
    final source = StreamController<dynamic>(sync: true);
    int? closeCode;
    final input = BufferedBrowserInput.forStream(
      source.stream,
      maxMessageBytes: 100,
      maxQueuedBytes: 100,
      maxQueuedMessages: 3,
      closeSource: (code, _) async => closeCode = code,
    );
    final errors = <Object>[];
    final subscription = input.stream.listen(
      (_) {},
      onError: (Object error) => errors.add(error),
    );

    source
      ..add(Uint8List(0))
      ..add(Uint8List(0))
      ..add(Uint8List(0))
      ..add(Uint8List(0));
    await input.closed;
    await Future<void>.delayed(Duration.zero);

    expect(closeCode, 1009);
    expect(errors, hasLength(1));
    expect(errors.single, isA<RemoteProtocolException>());

    await subscription.cancel();
    await input.dispose();
    await source.close();
  });

  test(
    'non-binary input is rejected and can be disposed before close settles',
    () async {
      var sourceCancels = 0;
      final source = StreamController<dynamic>(
        sync: true,
        onCancel: () => sourceCancels++,
      );
      final closeGate = Completer<void>();
      int? closeCode;
      String? closeReason;
      final input = BufferedBrowserInput.forStream(
        source.stream,
        closeSource: (code, reason) {
          closeCode = code;
          closeReason = reason;
          return closeGate.future;
        },
      );
      final errors = <Object>[];
      final subscription = input.stream.listen(
        (_) {},
        onError: (Object error) => errors.add(error),
      );

      source.add('not binary');
      await input.closed.timeout(const Duration(seconds: 1));
      expect(closeCode, 1003);
      expect(closeReason, 'binary input required');
      await input.dispose().timeout(const Duration(seconds: 1));
      expect(sourceCancels, 1);
      expect(errors, hasLength(1));

      closeGate.complete();
      await subscription.cancel();
      await source.close();
    },
  );

  test('bytes leave the budget when they advance downstream', () async {
    final source = StreamController<dynamic>();
    var closeCalls = 0;
    final input = BufferedBrowserInput.forStream(
      source.stream,
      maxMessageBytes: 6,
      maxQueuedBytes: 6,
      closeSource: (_, _) async => closeCalls++,
    );
    final received = <List<int>>[];
    final first = Completer<void>();
    final second = Completer<void>();
    final subscription = input.stream.listen((bytes) {
      received.add(bytes);
      if (received.length == 1) first.complete();
      if (received.length == 2) second.complete();
    });

    source.add(Uint8List.fromList([1, 2, 3, 4, 5, 6]));
    await first.future;
    source.add(Uint8List.fromList([7, 8, 9, 10, 11, 12]));
    await second.future;

    expect(received, hasLength(2));
    expect(
      closeCalls,
      0,
      reason: 'the cap is queued bytes, not lifetime bytes',
    );

    await subscription.cancel();
    await input.dispose();
    await source.close();
  });

  test('pause, resume, and cancel propagate to the source', () async {
    var pauses = 0;
    var resumes = 0;
    var cancels = 0;
    final source = StreamController<dynamic>(
      onPause: () => pauses++,
      onResume: () => resumes++,
      onCancel: () => cancels++,
    );
    final input = BufferedBrowserInput.forStream(
      source.stream,
      closeSource: (_, _) async {},
    );
    final first = Completer<void>();
    final subscription = input.stream.listen((_) => first.complete());
    source.add(Uint8List(1));
    await first.future;

    subscription.pause();
    await Future<void>.delayed(Duration.zero);
    expect(pauses, 1);

    subscription.resume();
    await Future<void>.delayed(Duration.zero);
    expect(resumes, 1);

    await subscription.cancel().timeout(
      const Duration(seconds: 1),
      onTimeout: () => throw StateError('downstream cancel did not settle'),
    );
    await input.closed.timeout(
      const Duration(seconds: 1),
      onTimeout: () => throw StateError('closed did not settle'),
    );
    expect(cancels, 1);

    await input.dispose().timeout(
      const Duration(seconds: 1),
      onTimeout: () => throw StateError('dispose did not settle'),
    );
    await source.close().timeout(
      const Duration(seconds: 1),
      onTimeout: () => throw StateError('source close did not settle'),
    );
  });

  test('dispose before pairing settles without a stream listener', () async {
    var cancels = 0;
    final source = StreamController<dynamic>(onCancel: () => cancels++);
    final input = BufferedBrowserInput.forStream(
      source.stream,
      closeSource: (_, _) async {},
    );

    await input.dispose().timeout(const Duration(seconds: 1));
    await input.closed.timeout(const Duration(seconds: 1));
    expect(cancels, 1);

    await source.close();
  });
}
