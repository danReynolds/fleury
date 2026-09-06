import 'dart:collection';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/rendering/render_object.dart'
    show RenderDamageTracker;
import 'package:fleury/src/widgets/rich_text.dart' show RenderRichText;
import 'package:test/test.dart';

void main() {
  test('repeated length and range queries reuse current layout length', () {
    final lines = _CountingLines(['abc', '', '漢👩‍💻']);
    final render = _LinesText(lines);
    expect(render.contentLength, 11);
    expect(lines.reads, 3);
    render.layout(const CellConstraints(maxCols: 20));
    render.paint(CellBuffer(const CellSize(20, 3)), CellOffset.zero);
    render.dispatchSelectionEvent(
      const SelectionGranularEvent(granularity: SelectionGranularity.all),
    );
    lines.reads = 0;
    for (var i = 0; i < 100; i++) {
      expect(render.contentLength, 11);
      expect(render.getSelectionRange(), (start: 0, end: 11));
    }
    expect(lines.reads, 0);

    final replacement = _CountingLines(['x', '']);
    render.lines = replacement;
    expect(
      render.contentLength,
      2,
      reason: 'replacement is visible before paint',
    );
    expect(replacement.reads, 2);
    expect(render.getSelectionRange(), (start: 0, end: 2));
    render.dispatchSelectionEvent(const SelectionClearEvent());
    render.lines = _CountingLines([]);
    render.paint(CellBuffer(const CellSize(20, 3)), CellOffset.zero);
    expect(render.contentLength, 0);
    expect(render.getSelectionRange(), isNull);
  });
  for (final rich in [false, true]) {
    test('empty and zero-sized paints still refresh selection, rich=$rich', () {
      var reads = 0;
      final RenderObject render = rich
          ? _RangeCountingRichText('', () => reads++)
          : _RangeCountingText('', () => reads++);
      render.layout(const CellConstraints(maxCols: 20));
      render.paint(CellBuffer(const CellSize(20, 3)), CellOffset.zero);
      expect(reads, 1);
      if (render is RenderRichText) {
        render.setSpan(const TextSpan(text: 'abc'), CellStyle.none);
      } else {
        (render as RenderText).text = 'abc';
      }
      render.layout(CellConstraints.tight(CellSize.zero));
      reads = 0;
      render.paint(CellBuffer(const CellSize(20, 3)), CellOffset.zero);
      expect(reads, 1);
    });

    test('partial copy preserves line separators and Unicode, rich=$rich', () {
      const content = 'a漢\n\nb👩‍💻c';
      final RenderObject render = rich
          ? RenderRichText(
              span: const TextSpan(text: content),
              base: CellStyle.none,
            )
          : RenderText(text: content);
      _Framed(render, const CellConstraints(maxCols: 20));
      render.paint(CellBuffer(const CellSize(20, 3)), CellOffset.zero);
      final selectable = render as Selectable;
      const points = [
        (CellOffset(0, 0), 0),
        (CellOffset(1, 0), 1),
        (CellOffset(3, 0), 2),
        (CellOffset(0, 1), 3),
        (CellOffset(0, 2), 4),
        (CellOffset(1, 2), 5),
        (CellOffset(3, 2), 10),
        (CellOffset(4, 2), 11),
      ];
      for (final a in points) {
        for (final b in points) {
          selectable.dispatchSelectionEvent(
            SelectionEdgeUpdateEvent(globalPosition: a.$1, isStart: true),
          );
          selectable.dispatchSelectionEvent(
            SelectionEdgeUpdateEvent(globalPosition: b.$1, isStart: false),
          );
          final start = a.$2 < b.$2 ? a.$2 : b.$2;
          final end = a.$2 < b.$2 ? b.$2 : a.$2;
          expect(
            selectable.getSelectedContent()?.plainText,
            start == end ? null : content.substring(start, end),
          );
        }
      }
    });
  }
  for (final rich in [false, true]) {
    test('highlight cells share immutable styles, rich=$rich', () {
      const base = CellStyle(foreground: AnsiColor(3), inverse: false);
      final RenderObject render = rich
          ? RenderRichText(
              span: const TextSpan(text: 'ab漢\ncd字'),
              base: base,
            )
          : RenderText(text: 'ab漢\ncd字', style: base);
      render.layout(const CellConstraints(maxCols: 8));
      final buffer = CellBuffer(const CellSize(8, 2));
      render.paint(buffer, CellOffset.zero);
      (render as Selectable).dispatchSelectionEvent(
        const SelectionGranularEvent(granularity: SelectionGranularity.all),
      );
      buffer.clear();
      render.paint(buffer, CellOffset.zero);
      for (var row = 0; row < 2; row++) {
        final style = buffer.atColRow(0, row).style;
        expect(style, const CellStyle(foreground: AnsiColor(3), inverse: true));
        for (var col = 1; col < 4; col++) {
          expect(identical(buffer.atColRow(col, row).style, style), isTrue);
        }
      }
      expect(
        base.inverse,
        isFalse,
        reason: 'highlighting must not mutate source styles',
      );
    });

    test('selection range resolves once per paint, rich=$rich', () {
      var reads = 0;
      final content = List.filled(1000, 'a漢b').join('\n');
      final RenderObject render = rich
          ? _RangeCountingRichText(content, () => reads++)
          : _RangeCountingText(content, () => reads++);
      render.layout(const CellConstraints(maxCols: 10));
      final selectable = render as Selectable;
      final buffer = CellBuffer(const CellSize(10, 3));
      render.paint(buffer, const CellOffset(0, -400));
      selectable.dispatchSelectionEvent(
        const SelectionGranularEvent(granularity: SelectionGranularity.all),
      );
      reads = 0;
      buffer.clear();
      render.paint(buffer, const CellOffset(0, -400));
      expect(reads, 1);
      expect(buffer.atColRow(0, 0).style.inverse, isTrue);
      expect(buffer.atColRow(2, 2).style.inverse, isTrue);
      expect(selectable.getSelectedContent()?.plainText, content);

      for (final row in [-1000, 3]) {
        reads = 0;
        buffer.clear();
        render.paint(buffer, CellOffset(0, row));
        expect(reads, 1, reason: 'resolve selection even when fully clipped');
        expect(buffer.atColRow(0, 0), const Cell.empty());
        expect(selectable.getSelectedContent()?.plainText, content);
      }

      selectable.dispatchSelectionEvent(const SelectionClearEvent());
      reads = 0;
      buffer.clear();
      render.paint(buffer, const CellOffset(0, -400));
      expect(reads, 1);
      expect(buffer.atColRow(0, 0).style.inverse, isFalse);
    });
  }
  test('paint measures only rows intersecting the buffer', () {
    final resolver = _CountingResolver();
    final render = RenderText(
      text: List.filled(1000, 'a漢👩‍💻').join('\n'),
      widthResolver: resolver,
    );
    _Framed(
      render,
      const CellConstraints(maxCols: 20),
      offset: const CellOffset(10, 20),
    );
    for (final row in [0, -400, -997]) {
      resolver.calls = 0;
      render.paint(CellBuffer(const CellSize(20, 3)), CellOffset(0, row));
      expect(
        resolver.calls,
        9,
        reason: 'three graphemes on three visible rows',
      );
    }
    for (final row in [3, -1000]) {
      resolver.calls = 0;
      render.paint(CellBuffer(const CellSize(20, 3)), CellOffset(0, row));
      expect(resolver.calls, 0);
      expect(
        render.cellBounds,
        CellRect.fromLTWH(10, 20, render.size.cols, 1000),
        reason: 'geometry is layout state; a hidden paint does not change it',
      );
    }
  });

  for (final rich in [false, true]) {
    test('viewport paint equals full-paint crop with selection, rich=$rich', () {
      const content = 'first a漢\n─ wide 👩‍💻 text\n\nlast e\u0301 characters';
      for (final policy in [
        TextPresentationPolicy.spec,
        const TextPresentationPolicy(widths: CellWidthPolicy.cjk),
      ]) {
        for (final wrap in [true, false]) {
          for (final align in rich ? [TextAlign.left] : TextAlign.values) {
            for (final overflow in TextOverflow.values) {
              for (final maxLines in <int?>[null, 2]) {
                final RenderObject render = rich
                    ? RenderRichText(
                        span: const TextSpan(
                          text: 'first a漢\n',
                          children: [
                            TextSpan(
                              text: '─ wide 👩‍💻 text\n\n',
                              style: CellStyle(bold: true),
                            ),
                            TextSpan(
                              text: 'last e\u0301 characters',
                              style: CellStyle(inverse: false),
                            ),
                          ],
                        ),
                        base: const CellStyle(foreground: AnsiColor(3)),
                        textPolicy: policy,
                        softWrap: wrap,
                        overflow: overflow,
                        maxLines: maxLines,
                      )
                    : RenderText(
                        text: content,
                        textPolicy: policy,
                        softWrap: wrap,
                        textAlign: align,
                        overflow: overflow,
                        maxLines: maxLines,
                        style: const CellStyle(foreground: AnsiColor(3)),
                      );
                const screen = CellOffset(10, 20);
                final framed = _Framed(
                  render,
                  const CellConstraints(maxCols: 8),
                  offset: screen,
                );
                final selectable = render as Selectable;
                for (final selected in [false, true]) {
                  final full = CellBuffer(const CellSize(8, 40));
                  render.paint(full, CellOffset.zero);
                  if (selected) {
                    selectable.dispatchSelectionEvent(
                      const SelectionEdgeUpdateEvent(
                        globalPosition: CellOffset(11, 21),
                        isStart: true,
                      ),
                    );
                    selectable.dispatchSelectionEvent(
                      const SelectionEdgeUpdateEvent(
                        globalPosition: CellOffset(13, 23),
                        isStart: false,
                      ),
                    );
                    full.clear();
                    render.paint(full, CellOffset.zero);
                  }
                  for (var top = -2; top <= render.size.rows + 1; top++) {
                    final actual = CellBuffer(const CellSize(8, 2));
                    // Buffer and screen coordinates intentionally differ: a
                    // scroll scratch must not use the screen clip as its grid.
                    final clip = CellRect.fromLTWH(10, 20 + top, 8, 2);
                    framed.clip = clip;
                    render.paint(actual, CellOffset(0, -top));
                    for (var row = 0; row < 2; row++) {
                      for (var col = 0; col < 8; col++) {
                        final sourceRow = top + row;
                        final expected = sourceRow < 0 || sourceRow >= 40
                            ? const Cell.empty()
                            : full.atColRow(col, sourceRow);
                        expect(
                          actual.atColRow(col, row),
                          expected,
                          reason:
                              '$policy wrap=$wrap align=$align $overflow '
                              'maxLines=$maxLines selected=$selected '
                              'top=$top cell=($col,$row)',
                        );
                      }
                    }
                    expect(
                      selectable.cellBounds,
                      CellRect(offset: screen, size: render.size),
                    );
                    expect(
                      selectable.visibleBounds,
                      selectable.cellBounds!.intersect(clip),
                    );
                  }
                  selectable.dispatchSelectionEvent(
                    const SelectionClearEvent(),
                  );
                }
              }
            }
          }
        }
      }
    });
  }
}

final class _CountingResolver implements WidthResolver {
  var calls = 0;
  @override
  int widthOfGrapheme(String grapheme, CellWidthPolicy policy) {
    calls++;
    return const DefaultWidthResolver().widthOfGrapheme(grapheme, policy);
  }

  @override
  int widthOfText(String text, CellWidthPolicy policy) =>
      const DefaultWidthResolver().widthOfText(text, policy);
}

class _RangeCountingText extends RenderText {
  _RangeCountingText(String text, this.onRead) : super(text: text);
  final void Function() onRead;
  @override
  ({int start, int end})? getSelectionRange() {
    onRead();
    return super.getSelectionRange();
  }
}

class _RangeCountingRichText extends RenderRichText {
  _RangeCountingRichText(String text, this.onRead)
    : super(
        span: TextSpan(text: text),
        base: CellStyle.none,
      );
  final void Function() onRead;
  @override
  ({int start, int end})? getSelectionRange() {
    onRead();
    return super.getSelectionRange();
  }
}

class _CountingLines extends ListBase<String> {
  _CountingLines(this.values);
  final List<String> values;
  int reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('read-only');
  @override
  String operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('read-only');
}

class _LinesText extends RenderText {
  _LinesText(this.lines) : super(text: 'abc\n\n漢👩‍💻');
  List<String> lines;
  @override
  List<String> get selectionLines => lines;
}

/// A root that gives a bare render object the screen geometry a tree would:
/// it places [child] at [offset], clips it to [clip] (both in screen cells,
/// the root sitting at the origin), and carries the frame tracker geometry is
/// memoized against. The child is laid out with [childConstraints]; the root
/// itself is never painted — tests paint the child straight into scratch
/// buffers, as a viewport would.
final class _Framed extends RenderObject
    implements RenderObjectWithSingleChild {
  _Framed(
    RenderObject child,
    this.childConstraints, {
    this.offset = CellOffset.zero,
  }) {
    attachFrameDamageTracker(
      RenderDamageTracker()..screenSize = const CellSize(400, 400),
    );
    this.child = child;
    layout(const CellConstraints());
  }

  final CellConstraints childConstraints;
  final CellOffset offset;

  CellRect? _clip;
  set clip(CellRect? value) {
    _clip = value;
    markNeedsPaintOnly(); // a new geometry epoch
  }

  RenderObject? _child;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) dropChild(_child!);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellOffset childOffsetOf(RenderObject child) => offset;

  @override
  CellRect? childClipOf(RenderObject child) => _clip;

  @override
  CellSize performLayout(CellConstraints constraints) {
    _child?.layout(childConstraints);
    return constraints.constrain(const CellSize(400, 400));
  }

  @override
  void performPaint(CellBuffer buffer, CellOffset offset) {}
}
