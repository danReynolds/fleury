import '../rendering/border.dart';
import '../rendering/cell.dart';
import '../rendering/render_flex.dart' show CrossAxisAlignment, MainAxisSize;
import '../rendering/render_objects.dart' show TextOverflow;
import '../runtime/output_capture.dart';
import 'align.dart';
import 'basic.dart';
import 'framework.dart';
import 'inherited_notifier.dart';
import 'layout_builder.dart';
import 'listenable_builder.dart';
import 'theme.dart';

/// Shares a [LogBuffer] with descendants. `runApp` installs one above the
/// app so [LogView] / [LogConsole] (including in floating overlays) can find
/// the captured output without it being threaded through constructors.
class LogBufferScope extends InheritedNotifier<LogBuffer> {
  const LogBufferScope({
    super.key,
    required LogBuffer buffer,
    required super.child,
  }) : super(notifier: buffer);

  LogBuffer get buffer => notifier;

  static LogBuffer? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LogBufferScope>()?.notifier;

  static LogBuffer of(BuildContext context) {
    final buffer = maybeOf(context);
    if (buffer == null) {
      throw StateError(
        'LogBufferScope.of: no LogBufferScope ancestor. Provide a [buffer] to '
        'the widget directly, or run under runApp (which installs one).',
      );
    }
    return buffer;
  }
}

/// Renders captured output as a list of lines, newest at the bottom. When
/// there are more lines than fit the available height it tails — showing the
/// most recent that fit — so it behaves like `tail -f`. stderr lines take
/// [errorStyle] (the theme's error color by default).
///
/// Reads its [LogBuffer] from [buffer] if given, otherwise from the nearest
/// [LogBufferScope]. Rebuilds as new lines arrive.
class LogView extends StatelessWidget {
  const LogView({super.key, this.buffer, this.style, this.errorStyle});

  final LogBuffer? buffer;
  final CellStyle? style;
  final CellStyle? errorStyle;

  @override
  Widget build(BuildContext context) {
    final explicit = buffer;
    if (explicit != null) {
      return ListenableBuilder(
        listenable: explicit,
        builder: (context, _) => _list(context, explicit),
      );
    }
    // Reading through the scope establishes a dependency, so the view
    // rebuilds when the buffer notifies.
    return _list(context, LogBufferScope.of(context));
  }

  Widget _list(BuildContext context, LogBuffer logs) {
    final theme = Theme.of(context);
    final normalStyle = style ?? theme.textStyle;
    final stderrStyle =
        errorStyle ?? CellStyle(foreground: theme.colorScheme.error);
    return LayoutBuilder(
      builder: (context, constraints) {
        final lines = logs.lines;
        final maxRows = constraints.maxRows;
        final visible = (maxRows != null && lines.length > maxRows)
            ? lines.sublist(lines.length - maxRows)
            : lines;
        if (visible.isEmpty) return const EmptyBox();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in visible)
              Text(
                line.text,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: line.source == LogSource.stderr
                    ? stderrStyle
                    : normalStyle,
              ),
          ],
        );
      },
    );
  }
}

/// The floating dev-tool console `runApp` toggles: a bordered, **opaque**
/// log panel pinned to the bottom, [height] rows tall (clamped to fit).
///
/// Every cell it covers is painted, so it stays legible over a busy screen
/// (unlike a bare [LogView], which only paints its glyphs). It reads the
/// captured output from the nearest [LogBufferScope] and dresses it up: an
/// accent-colored frame, a reversed header bar with a line count, a
/// source-tagged body (stderr in the error color), and a footer key hint.
class LogConsole extends StatelessWidget {
  const LogConsole({
    super.key,
    this.height = 12,
    this.title = 'console',
    this.toggleHint,
  });

  /// Rows the panel occupies, clamped to the available height.
  final int height;
  final String title;

  /// A key hint shown in the footer, e.g. `'F12'`. Omitted when null.
  final String? toggleHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logs = LogBufferScope.of(context); // dependency → rebuilds on output

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxCols ?? 80;
        final rows = constraints.maxRows ?? 24;
        final panelH = rows < height ? rows : height;
        if (panelH < 3 || cols < 4) return const EmptyBox();

        final innerW = cols - 2; // inside the border
        final innerH = panelH - 2;
        final hasFooter = innerH >= 3 && toggleHint != null;
        final logRows = innerH - 1 - (hasFooter ? 1 : 0);

        final children = <Widget>[
          // Reversed header bar: a left accent block, the title, and a count.
          _bar(
            _between(
              '▌ $title',
              '${logs.length} ${logs.length == 1 ? 'line' : 'lines'}',
              innerW,
            ),
            const CellStyle(inverse: true, bold: true),
            innerW,
          ),
          ..._body(theme, logs.lines, logRows, innerW),
          if (hasFooter)
            _bar(
              _rightAlign('$toggleHint to hide ', innerW),
              theme.mutedStyle,
              innerW,
            ),
        ];

        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: cols,
            height: panelH,
            child: Container(
              border: BoxBorder(
                style: theme.borderStyle,
                cellStyle: CellStyle(foreground: theme.colorScheme.primary),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _body(
    ThemeData theme,
    List<LogLine> lines,
    int logRows,
    int innerW,
  ) {
    if (logRows <= 0) return const [];
    if (lines.isEmpty) {
      return [
        for (var i = 0; i < logRows; i++)
          _bar(
            i == logRows ~/ 2 ? _center('no output yet', innerW) : '',
            theme.mutedStyle,
            innerW,
          ),
      ];
    }
    final shown = lines.length <= logRows
        ? lines
        : lines.sublist(lines.length - logRows);
    return [
      // Pad above so the newest line sits at the bottom, like a terminal.
      for (var i = 0; i < logRows - shown.length; i++)
        _bar('', theme.textStyle, innerW),
      for (final line in shown)
        _bar(
          '${line.source == LogSource.stderr ? '●' : '·'} ${line.text}',
          line.source == LogSource.stderr
              ? CellStyle(foreground: theme.colorScheme.error)
              : theme.textStyle,
          innerW,
        ),
    ];
  }

  // One opaque, full-width row (padded/truncated so every cell is painted).
  static Widget _bar(String text, CellStyle style, int width) => Text(
    _fit(text, width),
    style: style,
    maxLines: 1,
    overflow: TextOverflow.clip,
  );

  static String _fit(String s, int w) =>
      s.length >= w ? s.substring(0, w) : s.padRight(w);

  static String _between(String left, String right, int w) {
    final gap = w - left.length - right.length;
    return gap < 1 ? _fit(left, w) : '$left${' ' * gap}$right';
  }

  static String _rightAlign(String s, int w) =>
      s.length >= w ? _fit(s, w) : '${' ' * (w - s.length)}$s';

  static String _center(String s, int w) {
    if (s.length >= w) return _fit(s, w);
    return _fit('${' ' * ((w - s.length) ~/ 2)}$s', w);
  }
}
