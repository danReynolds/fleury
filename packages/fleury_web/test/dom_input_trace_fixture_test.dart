@TestOn('browser')
library;

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/input/dom_input_source.dart';
import 'package:fleury_web/src/metrics/cell_metrics.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'fixtures/browser_input_traces.dart';

void main() {
  group('browser input trace fixtures', () {
    for (final fixture in browserInputTraceFixtures) {
      test(fixture['name']! as String, () {
        final emitted = <TuiEvent>[];
        final host = web.document.createElement('div');
        final textArea =
            web.document.createElement('textarea') as web.HTMLTextAreaElement;
        web.document.body!.appendChild(host);

        final source = DomInputSource(
          hostElement: host,
          textArea: textArea,
          cellMetrics: _FakeMetrics(_traceMeasurement),
        );
        addTearDown(() {
          source.dispose();
          host.parentNode?.removeChild(host);
        });

        source.start(emitted.add);

        for (final event in _traceMaps(fixture, 'browserEvents')) {
          _dispatchTraceEvent(host: host, textArea: textArea, event: event);
        }

        expect(
          _serializeEvents(emitted),
          equals(_traceMaps(fixture, 'expectedFleuryEvents')),
        );
        expect(textArea.value, isEmpty);
      });
    }
  });
}

const _traceMeasurement = MeasuredCellBox(
  cssCellWidth: 10,
  cssCellHeight: 20,
  cssCanvasWidth: 80,
  cssCanvasHeight: 60,
  cssCanvasLeft: 10,
  cssCanvasTop: 20,
  devicePixelRatio: 1,
  cols: 8,
  rows: 3,
);

void _dispatchTraceEvent({
  required web.Element host,
  required web.HTMLTextAreaElement textArea,
  required TraceMap event,
}) {
  final target = _string(event, 'target') == 'host' ? host : textArea;
  switch (_string(event, 'event')) {
    case 'keydown':
      target.dispatchEvent(
        web.KeyboardEvent(
          'keydown',
          web.KeyboardEventInit(
            key: _string(event, 'key'),
            ctrlKey: _bool(event, 'ctrlKey'),
            shiftKey: _bool(event, 'shiftKey'),
            altKey: _bool(event, 'altKey'),
            metaKey: _bool(event, 'metaKey'),
            modifierAltGraph: _bool(event, 'modifierAltGraph'),
            repeat: _bool(event, 'repeat'),
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
    case 'input':
      target.dispatchEvent(
        web.InputEvent(
          'input',
          web.InputEventInit(
            data: event['data'] as String?,
            inputType: event['inputType'] as String? ?? 'insertText',
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
    case 'paste':
      final clipboardData = web.DataTransfer()
        ..setData('text/plain', _string(event, 'text'));
      target.dispatchEvent(
        web.ClipboardEvent(
          'paste',
          web.ClipboardEventInit(
            clipboardData: clipboardData,
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
    case 'compositionstart':
      target.dispatchEvent(
        web.CompositionEvent(
          'compositionstart',
          web.CompositionEventInit(bubbles: true, cancelable: true),
        ),
      );
    case 'compositionupdate':
      target.dispatchEvent(
        web.CompositionEvent(
          'compositionupdate',
          web.CompositionEventInit(
            data: _string(event, 'data'),
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
    case 'compositionend':
      target.dispatchEvent(
        web.CompositionEvent(
          'compositionend',
          web.CompositionEventInit(
            data: event['data'] as String? ?? '',
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
    case 'pointerdown':
    case 'pointermove':
    case 'pointerup':
    case 'pointercancel':
    case 'lostpointercapture':
      target.dispatchEvent(
        web.PointerEvent(
          _string(event, 'event'),
          web.PointerEventInit(
            pointerId: _int(event, 'pointerId', 1),
            clientX: _int(event, 'clientX'),
            clientY: _int(event, 'clientY'),
            button: _int(event, 'button'),
            buttons: _int(event, 'buttons'),
            ctrlKey: _bool(event, 'ctrlKey'),
            shiftKey: _bool(event, 'shiftKey'),
            altKey: _bool(event, 'altKey'),
            metaKey: _bool(event, 'metaKey'),
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
    case 'wheel':
      target.dispatchEvent(
        web.WheelEvent(
          'wheel',
          web.WheelEventInit(
            clientX: _int(event, 'clientX'),
            clientY: _int(event, 'clientY'),
            deltaY: _num(event, 'deltaY'),
            ctrlKey: _bool(event, 'ctrlKey'),
            shiftKey: _bool(event, 'shiftKey'),
            altKey: _bool(event, 'altKey'),
            metaKey: _bool(event, 'metaKey'),
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
    default:
      fail('Unsupported browser trace event: ${event['event']}');
  }
}

List<TraceMap> _serializeEvents(List<TuiEvent> events) =>
    events.map(_serializeEvent).toList();

TraceMap _serializeEvent(TuiEvent event) => switch (event) {
  KeyEvent() => {
    'type': 'key',
    if (event.keyCode case final keyCode?) 'keyCode': keyCode.name,
    if (event.char case final char?) 'char': char,
    'keyEventType': event.type.name,
    'modifiers': _modifierNames(event.modifiers),
  },
  TextInputEvent() => {'type': 'text', 'text': event.text},
  SignalEvent() => {'type': 'signal', 'signal': event.signal.name},
  TextCompositionEvent() => {
    'type': 'composition',
    'kind': event.kind.name,
    if (event.text case final text?) 'text': text,
  },
  PasteEvent() => {'type': 'paste', 'text': event.text},
  MouseEvent() => {
    'type': 'mouse',
    'kind': event.kind.name,
    'button': event.button.name,
    'col': event.col,
    'row': event.row,
    'modifiers': _modifierNames(event.modifiers),
  },
  ResizeEvent() => {
    'type': 'resize',
    'cols': event.size.cols,
    'rows': event.size.rows,
  },
};

List<String> _modifierNames(Set<KeyModifier> modifiers) =>
    modifiers.map((modifier) => modifier.name).toList()..sort();

List<TraceMap> _traceMaps(TraceMap trace, String key) =>
    (trace[key]! as List).cast<TraceMap>();

String _string(TraceMap event, String key) => event[key]! as String;

bool _bool(TraceMap event, String key) => event[key] as bool? ?? false;

int _int(TraceMap event, String key, [int fallback = 0]) =>
    (event[key] as num?)?.toInt() ?? fallback;

num _num(TraceMap event, String key, [num fallback = 0]) =>
    event[key] as num? ?? fallback;

final class _FakeMetrics implements CellMetrics {
  const _FakeMetrics(this.box);

  final MeasuredCellBox box;

  @override
  MeasuredCellBox? get cachedMeasurement => box;

  @override
  MeasuredCellBox measure() => box;

  @override
  void startObserving(void Function() onMetricsDirty) {}

  @override
  void markDirty() {}

  @override
  CellOffset cellForPoint(double x, double y) {
    final col = (x / box.cssCellWidth).floor().clamp(0, box.cols - 1).toInt();
    final row = (y / box.cssCellHeight).floor().clamp(0, box.rows - 1).toInt();
    return CellOffset(col, row);
  }

  @override
  CellOffset? cellForViewportPoint(double clientX, double clientY) {
    if (box.cols <= 0 || box.rows <= 0) return null;
    return cellForPoint(
      clientX - box.cssCanvasLeft,
      clientY - box.cssCanvasTop,
    );
  }

  @override
  void dispose() {}
}
