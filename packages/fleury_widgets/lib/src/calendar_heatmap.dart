import 'package:fleury/fleury_core.dart';

/// Which day starts a week in a [CalendarHeatmap] row.
///
/// [sunday] matches the GitHub-contribution-graph canonical layout and
/// is the convention most users will recognize at a glance. [monday] is
/// the ISO-8601 default and the right pick for regions/teams that use
/// it.
enum CalendarWeekStart { sunday, monday }

/// A GitHub-contribution-graph-style calendar heatmap: each cell is one
/// day, columns are weeks, rows are days-of-week. Day intensity is
/// mapped to a five-step ladder (`·░▒▓█`) so recorded zero-activity
/// days stay visible as a dim dot, matching GitHub's "0 contributions"
/// tile semantics.
///
/// ```dart
/// CalendarHeatmap(
///   start: DateTime(2024, 1, 1),
///   end:   DateTime(2024, 12, 31),
///   values: {
///     DateTime(2024, 3, 15): 4,
///     DateTime(2024, 3, 16): 2,
///     // ...
///   },
/// )
/// ```
///
/// Months are labeled along the top row at the first week containing
/// each new month. Days are labeled in the left gutter (Mon/Wed/Fri by
/// default — every other row, the typical compact form).
///
/// Semantics: contributes one summary node (chart role, label, and data
/// state) by design. Terminal charts are announced and asserted as
/// summaries; per-element semantic children are intentionally omitted.
class CalendarHeatmap extends StatelessWidget {
  const CalendarHeatmap({
    super.key,
    required this.values,
    required this.start,
    required this.end,
    this.min,
    this.max,
    this.color,
    this.cellWidth = 2,
    this.weekStartsOn = CalendarWeekStart.sunday,
    this.showMonthLabels = true,
    this.showDayLabels = true,
    this.showLegend = false,
    this.semanticLabel = 'Calendar heatmap',
  }) : assert(cellWidth >= 1, 'cellWidth must be >= 1');

  /// Sparse map of date → intensity. Dates with no entry render empty
  /// (truly "no data"); entries with value 0 render as the dim dot.
  /// Time-of-day is ignored — entries are bucketed by calendar day.
  final Map<DateTime, num> values;

  /// First date to include (inclusive).
  final DateTime start;

  /// Last date to include (inclusive).
  final DateTime end;

  /// Low end of the intensity range. `null` autoscales to `values`.
  final num? min;

  /// High end. `null` autoscales.
  final num? max;

  /// Foreground for filled cells. Defaults to the theme's primary.
  final Color? color;

  /// Cells per day (≥ 1). `1` is the dense GitHub look; `2` reads more
  /// clearly at the cost of horizontal space.
  final int cellWidth;

  /// Which day starts a week. Defaults to [CalendarWeekStart.sunday] to
  /// match the GitHub contribution graph.
  final CalendarWeekStart weekStartsOn;

  /// Draw month abbreviations along the top row at month boundaries.
  final bool showMonthLabels;

  /// Draw day-of-week labels along the left gutter (Mon/Wed/Fri).
  final bool showDayLabels;

  /// When true, append a `· ░ ▒ ▓ █  less – more` scale strip below the grid.
  /// GitHub substitutes hover counts for the scale; a TUI can't hover, so the
  /// legend is the only way to map a glyph to its value.
  final bool showLegend;

  /// Label exposed through the semantic app graph.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedStart = _midnight(start);
    final normalizedEnd = _midnight(end);
    final normalizedValues = _normalizeCalendarValues(values);
    final stats = _calendarHeatmapStats(
      normalizedValues,
      start: normalizedStart,
      end: normalizedEnd,
      min: min,
      max: max,
      weekStartsOn: weekStartsOn,
    );
    final grid = _RawCalendarHeatmap(
      values: normalizedValues,
      start: normalizedStart,
      end: normalizedEnd,
      min: min,
      max: max,
      color: color ?? theme.colorScheme.primary,
      cellWidth: cellWidth,
      weekStartsOn: weekStartsOn,
      labelStyle: theme.mutedStyle,
      showMonthLabels: showMonthLabels,
      showDayLabels: showDayLabels,
    );
    return Semantics(
      role: SemanticRole.chart,
      label: semanticLabel,
      state: SemanticState({
        'chartType': 'calendarHeatmap',
        'chartRowCount': 7,
        'chartColumnCount': stats.weeks,
        'chartPointCount': stats.days,
        'chartRecordedPointCount': stats.recorded,
        'chartMinValue': stats.min,
        'chartMaxValue': stats.max,
        'chartStartDate': _dateLabel(normalizedStart),
        'chartEndDate': _dateLabel(normalizedEnd),
        'chartWeekStart': weekStartsOn.name,
      }),
      child: showLegend
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                grid,
                Text(
                  '·░▒▓█  less – more',
                  allowSelect: false, // chart legend, not selectable text
                  style: theme.mutedStyle,
                ),
              ],
            )
          : grid,
    );
  }
}

DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

/// The calendar date of [d] anchored at UTC midnight. The heatmap grid is a
/// pure calendar-date lattice, so anchoring it in UTC makes day-stepping
/// (`add(Duration(days:))`) and day-counting (`difference().inDays`) exact even
/// across a local DST transition, where a civil day is 23h or 25h long.
DateTime _utcDate(DateTime d) => DateTime.utc(d.year, d.month, d.day);

Map<DateTime, num> _normalizeCalendarValues(Map<DateTime, num> values) {
  if (values.isEmpty) return const <DateTime, num>{};
  return {
    for (final entry in values.entries) _midnight(entry.key): entry.value,
  };
}

String _dateLabel(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

({int days, int weeks, int recorded, num min, num max}) _calendarHeatmapStats(
  Map<DateTime, num> values, {
  required DateTime start,
  required DateTime end,
  required num? min,
  required num? max,
  required CalendarWeekStart weekStartsOn,
}) {
  final days = _calendarDayCount(start, end);
  final weeks = _calendarWeekCount(start, end, weekStartsOn: weekStartsOn);
  var recorded = 0;
  num? autoMin;
  num? autoMax;
  for (final entry in values.entries) {
    final date = _midnight(entry.key);
    if (date.isBefore(start) || date.isAfter(end)) continue;
    recorded += 1;
    final value = entry.value;
    if (autoMin == null || value < autoMin) autoMin = value;
    if (autoMax == null || value > autoMax) autoMax = value;
  }
  var resolvedMin = min ?? autoMin ?? 0;
  var resolvedMax = max ?? autoMax ?? 1;
  if (resolvedMax == resolvedMin) resolvedMax = resolvedMin + 1;
  return (
    days: days,
    weeks: weeks,
    recorded: recorded,
    min: resolvedMin,
    max: resolvedMax,
  );
}

int _calendarDayCount(DateTime start, DateTime end) {
  final s = _utcDate(start);
  final e = _utcDate(end);
  if (e.isBefore(s)) return 0;
  return e.difference(s).inDays + 1;
}

int _calendarWeekCount(
  DateTime start,
  DateTime end, {
  required CalendarWeekStart weekStartsOn,
}) {
  final days = _calendarDayCount(start, end);
  if (days <= 0) return 0;
  final firstAnchor = _utcDate(
    start,
  ).subtract(Duration(days: _backToCalendarWeekStart(start, weekStartsOn)));
  final daysFromAnchor = _utcDate(end).difference(firstAnchor).inDays;
  return (daysFromAnchor ~/ 7) + 1;
}

int _backToCalendarWeekStart(DateTime date, CalendarWeekStart weekStartsOn) {
  final weekday = date.weekday;
  if (weekStartsOn == CalendarWeekStart.monday) return weekday - 1;
  return weekday % 7;
}

class _RawCalendarHeatmap extends LeafRenderObjectWidget {
  const _RawCalendarHeatmap({
    required this.values,
    required this.start,
    required this.end,
    required this.min,
    required this.max,
    required this.color,
    required this.cellWidth,
    required this.weekStartsOn,
    required this.labelStyle,
    required this.showMonthLabels,
    required this.showDayLabels,
  });

  final Map<DateTime, num> values;
  final DateTime start;
  final DateTime end;
  final num? min;
  final num? max;
  final Color color;
  final int cellWidth;
  final CalendarWeekStart weekStartsOn;
  final CellStyle labelStyle;
  final bool showMonthLabels;
  final bool showDayLabels;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderCalendarHeatmap(
        values: values,
        start: start,
        end: end,
        min: min,
        max: max,
        color: color,
        cellWidth: cellWidth,
        weekStartsOn: weekStartsOn,
        labelStyle: labelStyle,
        showMonthLabels: showMonthLabels,
        showDayLabels: showDayLabels,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderCalendarHeatmap r,
  ) {
    r
      ..values = values
      ..start = start
      ..end = end
      ..min = min
      ..max = max
      ..color = color
      ..cellWidth = cellWidth
      ..weekStartsOn = weekStartsOn
      ..labelStyle = labelStyle
      ..showMonthLabels = showMonthLabels
      ..showDayLabels = showDayLabels;
  }
}

/// Render object behind [CalendarHeatmap]. See its docs.
class RenderCalendarHeatmap extends RenderObject {
  RenderCalendarHeatmap({
    required Map<DateTime, num> values,
    required DateTime start,
    required DateTime end,
    required num? min,
    required num? max,
    required Color color,
    required int cellWidth,
    required CalendarWeekStart weekStartsOn,
    required CellStyle labelStyle,
    required bool showMonthLabels,
    required bool showDayLabels,
  }) : _values = values,
       _start = start,
       _end = end,
       _min = min,
       _max = max,
       _color = color,
       _cellWidth = cellWidth,
       _weekStartsOn = weekStartsOn,
       _labelStyle = labelStyle,
       _showMonthLabels = showMonthLabels,
       _showDayLabels = showDayLabels;

  Map<DateTime, num> _values;
  set values(Map<DateTime, num> v) {
    if (identical(_values, v)) return;
    _values = v;
    markNeedsPaintOnly();
  }

  DateTime _start;
  set start(DateTime v) {
    if (_start == v) return;
    _start = v;
    markNeedsLayout();
  }

  DateTime _end;
  set end(DateTime v) {
    if (_end == v) return;
    _end = v;
    markNeedsLayout();
  }

  num? _min;
  set min(num? v) {
    if (_min == v) return;
    _min = v;
    markNeedsPaintOnly();
  }

  num? _max;
  set max(num? v) {
    if (_max == v) return;
    _max = v;
    markNeedsPaintOnly();
  }

  Color _color;
  set color(Color v) {
    if (_color == v) return;
    _color = v;
    markNeedsPaintOnly();
  }

  int _cellWidth;
  set cellWidth(int v) {
    final clamped = v < 1 ? 1 : v;
    if (_cellWidth == clamped) return;
    _cellWidth = clamped;
    markNeedsLayout();
  }

  CalendarWeekStart _weekStartsOn;
  set weekStartsOn(CalendarWeekStart v) {
    if (_weekStartsOn == v) return;
    _weekStartsOn = v;
    markNeedsLayout();
  }

  CellStyle _labelStyle;
  set labelStyle(CellStyle v) {
    if (_labelStyle == v) return;
    _labelStyle = v;
    markNeedsPaintOnly();
  }

  bool _showMonthLabels;
  set showMonthLabels(bool v) {
    if (_showMonthLabels == v) return;
    _showMonthLabels = v;
    markNeedsLayout();
  }

  bool _showDayLabels;
  set showDayLabels(bool v) {
    if (_showDayLabels == v) return;
    _showDayLabels = v;
    markNeedsLayout();
  }

  // Five-step intensity ladder. Index 0 is the dim "zero / out of range"
  // marker — peers (GitHub, Cal-Heatmap, Observable Plot) all render an
  // explicit empty-but-present tile rather than dropping zero-activity
  // days. The remaining four are the quartile fill steps.
  static const _glyphs = ['·', '░', '▒', '▓', '█'];
  static const _monthAbbrevs = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  // Labels for each row, given the current weekStartsOn. Mon-first
  // puts Mon at row 0; Sun-first puts Sun at row 0 (so Mon=1, Wed=3,
  // Fri=5 — the GitHub-canonical positions).
  static const _dayLabelsMonFirst = ['Mon', '', 'Wed', '', 'Fri', '', ''];
  static const _dayLabelsSunFirst = ['', 'Mon', '', 'Wed', '', 'Fri', ''];

  List<String> get _dayLabelsPattern =>
      _weekStartsOn == CalendarWeekStart.monday
      ? _dayLabelsMonFirst
      : _dayLabelsSunFirst;

  /// Days back from `d` to the start-of-week anchor.
  int _backToWeekStart(DateTime d) {
    final wd = d.weekday; // Dart: 1=Mon..7=Sun
    if (_weekStartsOn == CalendarWeekStart.monday) {
      return wd - 1; // Mon=0, Sun=6
    }
    return wd % 7; // Sun=0, Mon=1, ..., Sat=6
  }

  int get _dayLabelWidth {
    if (!_showDayLabels) return 0;
    return 4; // 'Mon ' / 'Wed ' / 'Fri '
  }

  int get _monthLabelHeight => _showMonthLabels ? 1 : 0;

  /// Number of week columns to render. Anchors the first week to the
  /// week-start day on or before [_start], so each column always
  /// contains a well-formed 7-day window. Shares the DST-safe calendar-date
  /// math with the semantics/stats path so layout and paint never disagree.
  int get _weekCount =>
      _calendarWeekCount(_start, _end, weekStartsOn: _weekStartsOn);

  @override
  CellSize performLayout(CellConstraints constraints) {
    final desiredW = _dayLabelWidth + _weekCount * _cellWidth;
    final desiredH = _monthLabelHeight + 7;
    final cols = constraints.hasBoundedWidth
        ? (desiredW < constraints.maxCols! ? desiredW : constraints.maxCols!)
        : desiredW;
    final rows = constraints.hasBoundedHeight
        ? (desiredH < constraints.maxRows! ? desiredH : constraints.maxRows!)
        : desiredH;
    return constraints.constrain(CellSize(cols, rows));
  }

  @override
  int computeMaxIntrinsicWidth(int? height) =>
      _dayLabelWidth + _weekCount * _cellWidth;
  @override
  int computeMaxIntrinsicHeight(int? width) => _monthLabelHeight + 7;

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    if (size.cols == 0 || size.rows == 0 || _weekCount == 0) return;

    // Resolve intensity range — autoscale falls back to the observed
    // values within [_start, _end].
    var lo = _min?.toDouble();
    var hi = _max?.toDouble();
    if (lo == null || hi == null) {
      double? autoLo, autoHi;
      for (final e in _values.entries) {
        final d = _midnight(e.key);
        if (d.isBefore(_start) || d.isAfter(_end)) continue;
        final v = e.value.toDouble();
        if (autoLo == null || v < autoLo) autoLo = v;
        if (autoHi == null || v > autoHi) autoHi = v;
      }
      lo ??= autoLo ?? 0;
      hi ??= autoHi ?? 1;
    }
    if (hi == lo) hi = lo + 1; // avoid /0

    final gridLeft = offset.col + _dayLabelWidth;
    final gridTop = offset.row + _monthLabelHeight;
    // Anchor the day grid in UTC: a UTC day is always 24h, so stepping it with
    // Duration arithmetic below lands on exactly one calendar date per cell,
    // even across a local DST fall-back/spring-forward. Compare cells against
    // the UTC-anchored range bounds for the same reason.
    final startDate = _utcDate(_start);
    final endDate = _utcDate(_end);
    final firstAnchor = startDate.subtract(
      Duration(days: _backToWeekStart(_start)),
    );

    // Day-of-week labels (every other row to avoid visual crowding).
    if (_showDayLabels) {
      for (var d = 0; d < 7; d++) {
        final row = gridTop + d;
        if (row < 0 || row >= buffer.size.rows) continue;
        final label = _dayLabelsPattern[d];
        if (label.isEmpty) continue;
        for (var i = 0; i < label.length && i < _dayLabelWidth - 1; i++) {
          final col = offset.col + i;
          if (col < 0 || col >= buffer.size.cols) continue;
          buffer.writeGrapheme(
            CellOffset(col, row),
            label[i],
            style: _labelStyle,
          );
        }
      }
    }

    // Cells.
    for (var w = 0; w < _weekCount; w++) {
      final weekStart = firstAnchor.add(Duration(days: w * 7));
      for (var d = 0; d < 7; d++) {
        final day = weekStart.add(Duration(days: d));
        if (day.isBefore(startDate) || day.isAfter(endDate)) continue;
        // Value keys are normalized to local midnight; map the UTC grid date
        // back to the same civil date for the lookup.
        final raw = _values[DateTime(day.year, day.month, day.day)];
        if (raw == null) continue; // no recorded data — leave empty
        // Clamp values outside the visible range to the nearest bucket
        // rather than dropping them (peer convention — GitHub clamps,
        // doesn't omit, when a value falls outside its 0..max scale).
        var t = ((raw.toDouble() - lo) / (hi - lo)).clamp(0.0, 1.0);
        // 5-step ladder: t==0 → `·` (recorded-zero dim dot),
        // (0, .25] → ░, (.25, .5] → ▒, (.5, .75] → ▓, (.75, 1] → █.
        final idx = t == 0 ? 0 : ((t * 4).ceil()).clamp(0, 4);
        final glyph = _glyphs[idx];
        final cellLeft = gridLeft + w * _cellWidth;
        for (var x = 0; x < _cellWidth; x++) {
          final col = cellLeft + x;
          if (col < 0 || col >= buffer.size.cols) continue;
          final row = gridTop + d;
          if (row < 0 || row >= buffer.size.rows) continue;
          buffer.writeGrapheme(
            CellOffset(col, row),
            glyph,
            style: CellStyle(foreground: _color),
          );
        }
      }

      // Month labels — anchored to the week containing the 1st of a
      // month, matching GitHub's convention. Skipped for any month
      // whose 1st falls outside the visible window, so a partial
      // previous-month prefix (e.g. Dec when start=Jan 1) doesn't
      // collide with the next month's label.
      if (_showMonthLabels &&
          offset.row >= 0 &&
          offset.row < buffer.size.rows) {
        for (var d = 0; d < 7; d++) {
          final day = weekStart.add(Duration(days: d));
          if (day.day != 1) continue;
          if (day.isBefore(startDate) || day.isAfter(endDate)) continue;
          final text = _monthAbbrevs[day.month - 1];
          final cellLeft = gridLeft + w * _cellWidth;
          for (var i = 0; i < text.length; i++) {
            final col = cellLeft + i;
            if (col < 0 || col >= buffer.size.cols) continue;
            buffer.writeGrapheme(
              CellOffset(col, offset.row),
              text[i],
              style: _labelStyle,
            );
          }
        }
      }
    }
  }
}
