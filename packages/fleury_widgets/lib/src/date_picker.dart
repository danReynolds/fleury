import 'package:fleury/fleury.dart';

import 'calendar_heatmap.dart' show CalendarWeekStart;

/// A month-at-a-time date picker. Renders a header (`< January 2024 >`),
/// the day-of-week row, and a 7-column day grid. The current selection
/// (`value`) is highlighted; cursor navigation moves it.
///
/// Keys when focused:
/// - `← / →`        move by one day
/// - `↑ / ↓`        move by one week
/// - `PageUp / PageDown`  previous / next month
/// - `Home / End`   first / last day of the visible month
/// - `Enter`        consume (selection already committed on each move)
///
/// `[` and `]` (with no modifier) page by year — handy on terminals
/// that swallow shift+page combos.
///
/// Controlled — hold the value yourself and update it from [onChanged].
/// Days outside `[firstDate, lastDate]` (when provided) are dimmed and
/// the cursor skips them. Passing null for [onChanged] disables the picker.
///
/// ```dart
/// DatePicker(
///   value: today,
///   firstDate: DateTime(2020, 1, 1),
///   lastDate: DateTime(2030, 12, 31),
///   onChanged: (d) => setState(() => today = d),
/// )
/// ```
class DatePicker extends StatefulWidget {
  const DatePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.weekStartsOn = CalendarWeekStart.sunday,
    this.label,
    this.focusNode,
    this.autofocus = false,
  });

  /// Currently-selected day (only the y/m/d portion is read).
  final DateTime value;

  /// Called with the new day on each cursor move and on Enter.
  final void Function(DateTime date)? onChanged;

  /// Lower bound (inclusive). Days before this are dimmed and skipped.
  final DateTime? firstDate;

  /// Upper bound (inclusive). Days after this are dimmed and skipped.
  final DateTime? lastDate;

  /// Which day starts a week — drives the day-of-week header order and
  /// the column layout. Defaults to Sunday (matches CalendarHeatmap).
  final CalendarWeekStart weekStartsOn;

  /// Optional label exposed through the semantic app graph.
  final String? label;

  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<DatePicker> createState() => _DatePickerState();
}

class _DatePickerState extends State<DatePicker> implements TextInputClaimant {
  late FocusNode _node;
  bool _owns = false;

  bool get _enabled => widget.onChanged != null;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _dayLabelsSunFirst = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
  static const _dayLabelsMonFirst = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode(debugLabel: 'date-picker');
    _node.textInputClaimant = this;
    _owns = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(DatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _node.textInputClaimant = null;
      if (_owns) _node.dispose();
      _node = widget.focusNode ?? FocusNode(debugLabel: 'date-picker');
      _node.textInputClaimant = this;
      _owns = widget.focusNode == null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Focus.maybeOf(context); // rebuild on focus change
  }

  @override
  void dispose() {
    _node.textInputClaimant = null;
    if (_owns) _node.dispose();
    super.dispose();
  }

  @override
  KeyEventResult onTextInput(String text) {
    if (!_enabled) return KeyEventResult.ignored;
    if (text == '[') {
      _shiftMonth(-12);
      return KeyEventResult.handled;
    }
    if (text == ']') {
      _shiftMonth(12);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  KeyEventResult onPaste(String text) => KeyEventResult.ignored;

  DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  String _formatDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  String _formatMonth(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    return '${d.year}-$m';
  }

  bool _inBounds(DateTime d) {
    final m = _midnight(d);
    if (widget.firstDate != null && m.isBefore(_midnight(widget.firstDate!))) {
      return false;
    }
    if (widget.lastDate != null && m.isAfter(_midnight(widget.lastDate!))) {
      return false;
    }
    return true;
  }

  /// Days back from `d` to the start-of-week column. Matches the helper
  /// in CalendarHeatmap so layouts agree.
  int _backToWeekStart(DateTime d) {
    final wd = d.weekday;
    return widget.weekStartsOn == CalendarWeekStart.monday ? wd - 1 : wd % 7;
  }

  void _move(Duration delta) {
    if (!_enabled) return;
    var next = _midnight(widget.value).add(delta);
    if (!_inBounds(next)) return; // clamp by ignoring
    widget.onChanged!(next);
  }

  void _shiftMonth(int delta) {
    if (!_enabled) return;
    final v = widget.value;
    // Use day 1 to avoid Feb 31 etc., then re-clamp the day.
    final targetYear = v.year + ((v.month - 1 + delta) ~/ 12);
    final targetMonth = ((v.month - 1 + delta) % 12 + 12) % 12 + 1;
    final lastDayOfTarget = DateTime(targetYear, targetMonth + 1, 0).day;
    final day = v.day > lastDayOfTarget ? lastDayOfTarget : v.day;
    final next = DateTime(targetYear, targetMonth, day);
    if (!_inBounds(next)) return;
    widget.onChanged!(next);
  }

  void _jumpInMonth(int day) {
    if (!_enabled) return;
    final v = widget.value;
    final lastDay = DateTime(v.year, v.month + 1, 0).day;
    final next = DateTime(v.year, v.month, day.clamp(1, lastDay));
    if (!_inBounds(next)) return;
    widget.onChanged!(next);
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (!_enabled) return KeyEventResult.ignored;
    // Boundary escape: the calendar is a grid, so an arrow that would step off
    // its edge is returned *unhandled* and bubbles to the enclosing directional
    // focus traversal — that's how you leave the calendar with the same arrow
    // keys you navigate it with (Tab/Shift+Tab and Esc also leave). Month
    // paging stays on PageUp/PageDown and the ‹ › header buttons.
    final value = _midnight(widget.value);
    final column = _backToWeekStart(value); // 0 = first column of the week
    final lastDay = DateTime(value.year, value.month + 1, 0).day;
    switch (event.keyCode) {
      case KeyCode.arrowLeft:
        if (column == 0 || value.day == 1) return KeyEventResult.ignored;
        _move(const Duration(days: -1));
        return KeyEventResult.handled;
      case KeyCode.arrowRight:
        if (column == 6 || value.day == lastDay) return KeyEventResult.ignored;
        _move(const Duration(days: 1));
        return KeyEventResult.handled;
      case KeyCode.arrowUp:
        if (value.day - 7 < 1) return KeyEventResult.ignored;
        _move(const Duration(days: -7));
        return KeyEventResult.handled;
      case KeyCode.arrowDown:
        if (value.day + 7 > lastDay) return KeyEventResult.ignored;
        _move(const Duration(days: 7));
        return KeyEventResult.handled;
      case KeyCode.pageUp:
        _shiftMonth(-1);
        return KeyEventResult.handled;
      case KeyCode.pageDown:
        _shiftMonth(1);
        return KeyEventResult.handled;
      case KeyCode.home:
        _jumpInMonth(1);
        return KeyEventResult.handled;
      case KeyCode.end:
        _jumpInMonth(31); // clamped to last day
        return KeyEventResult.handled;
      case KeyCode.enter:
        // Selection already committed on each move; Enter just consumes.
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
    // Year paging via `[` / `]` is handled in [onTextInput] — those
    // characters arrive as text input, not key events.
  }

  List<String> get _dayLabels => widget.weekStartsOn == CalendarWeekStart.monday
      ? _dayLabelsMonFirst
      : _dayLabelsSunFirst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _enabled;
    final focused = enabled && _node.hasFocus;
    final disabledStyle = theme.mutedStyle;
    final v = widget.value;
    final firstOfMonth = DateTime(v.year, v.month, 1);
    final lastDay = DateTime(v.year, v.month + 1, 0).day;
    final leadingBlanks = _backToWeekStart(firstOfMonth);
    final canDecrement =
        enabled && _inBounds(_midnight(v).subtract(const Duration(days: 1)));
    final canIncrement =
        enabled && _inBounds(_midnight(v).add(const Duration(days: 1)));

    // Build the 7-column day grid as rows. Each row is a List<Widget>
    // of cells (blank, in-bounds day, or out-of-bounds dimmed day).
    final rows = <List<Widget>>[];
    var row = <Widget>[];
    for (var i = 0; i < leadingBlanks; i++) {
      row.add(const _Cell('   '));
    }
    for (var d = 1; d <= lastDay; d++) {
      final day = DateTime(v.year, v.month, d);
      final selected = d == v.day;
      final inB = _inBounds(day);
      final label = d.toString().padLeft(2, ' ');
      final cellText = ' $label';
      if (selected) {
        row.add(
          _Cell(
            cellText,
            style: !enabled
                ? disabledStyle
                : focused
                ? theme.focusedStyle
                : theme.selectionStyle,
          ),
        );
      } else if (!inB) {
        row.add(_Cell(cellText, style: const CellStyle(dim: true)));
      } else if (!enabled) {
        row.add(_Cell(cellText, style: disabledStyle));
      } else {
        row.add(_Cell(cellText));
      }
      if (row.length == 7) {
        rows.add(row);
        row = <Widget>[];
      }
    }
    if (row.isNotEmpty) {
      while (row.length < 7) {
        row.add(const _Cell('   '));
      }
      rows.add(row);
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header: `< January 2024 >`. Left-anchored so flex layout
        // can't push children to negative columns at tight widths.
        Row(
          children: [
            Text('< ', style: enabled ? theme.mutedStyle : disabledStyle),
            Text(
              '${_months[v.month - 1]} ${v.year}',
              style: !enabled
                  ? disabledStyle
                  : focused
                  ? theme.focusedStyle
                  : const CellStyle(bold: true),
            ),
            Text(' >', style: enabled ? theme.mutedStyle : disabledStyle),
          ],
        ),
        // Day-of-week labels.
        Row(
          children: [
            for (final label in _dayLabels)
              _Cell(
                ' $label',
                style: enabled ? theme.mutedStyle : disabledStyle,
              ),
          ],
        ),
        // The day grid.
        for (final r in rows) Row(children: r),
      ],
    );

    if (!enabled) {
      return Semantics(
        role: SemanticRole.datePicker,
        label: widget.label,
        value: _formatDate(v),
        enabled: false,
        state: SemanticState({
          'selectedDate': _formatDate(v),
          'visibleMonth': _formatMonth(v),
          'visibleYear': v.year,
          'weekStartsOn': widget.weekStartsOn.name,
          if (widget.firstDate != null)
            'firstDate': _formatDate(_midnight(widget.firstDate!)),
          if (widget.lastDate != null)
            'lastDate': _formatDate(_midnight(widget.lastDate!)),
          'canIncrement': false,
          'canDecrement': false,
        }),
        child: body,
      );
    }

    return Semantics(
      role: SemanticRole.datePicker,
      label: widget.label,
      value: _formatDate(v),
      focused: focused,
      actions: {
        SemanticAction.focus,
        if (canIncrement) SemanticAction.increment,
        if (canDecrement) SemanticAction.decrement,
      },
      state: SemanticState({
        'selectedDate': _formatDate(v),
        'visibleMonth': _formatMonth(v),
        'visibleYear': v.year,
        'weekStartsOn': widget.weekStartsOn.name,
        if (widget.firstDate != null)
          'firstDate': _formatDate(_midnight(widget.firstDate!)),
        if (widget.lastDate != null)
          'lastDate': _formatDate(_midnight(widget.lastDate!)),
        'canIncrement': canIncrement,
        'canDecrement': canDecrement,
      }),
      onAction: (action) {
        switch (action) {
          case SemanticAction.focus:
            _node.requestFocus();
            return;
          case SemanticAction.increment:
            _node.requestFocus();
            if (canIncrement) _move(const Duration(days: 1));
            return;
          case SemanticAction.decrement:
            _node.requestFocus();
            if (canDecrement) _move(const Duration(days: -1));
            return;
          case _:
            return;
        }
      },
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        onKey: _onKey,
        child: GestureDetector(onTap: () => _node.requestFocus(), child: body),
      ),
    );
  }
}

/// A fixed-width 3-column cell used for the day grid and the day-of-week
/// header so columns line up regardless of which days have one or two
/// digits.
class _Cell extends StatelessWidget {
  const _Cell(this.text, {this.style = CellStyle.empty});
  final String text;
  final CellStyle style;
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 3, child: Text(text, style: style));
}
