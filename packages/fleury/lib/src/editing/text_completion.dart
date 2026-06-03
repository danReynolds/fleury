import '../foundation/change_notifier.dart';
import 'text_editing.dart';

/// One completion candidate for an editable text field.
final class TextCompletionOption {
  const TextCompletionOption({
    required this.label,
    String? replacement,
    this.detail,
    this.id,
  }) : replacement = replacement ?? label;

  /// Text shown to users.
  final String label;

  /// Text inserted into the active completion range.
  final String replacement;

  /// Optional secondary description for UI surfaces.
  final String? detail;

  /// Optional stable identifier for semantic/test adapters.
  final Object? id;

  @override
  bool operator ==(Object other) =>
      other is TextCompletionOption &&
      other.label == label &&
      other.replacement == replacement &&
      other.detail == detail &&
      other.id == id;

  @override
  int get hashCode => Object.hash(label, replacement, detail, id);

  @override
  String toString() => 'TextCompletionOption($label)';
}

/// Immutable completion state for one editable field.
final class TextCompletionState {
  const TextCompletionState._({
    required this.active,
    required this.range,
    required this.query,
    required this.options,
    required this.selectedIndex,
  });

  static const inactive = TextCompletionState._(
    active: false,
    range: TextRange.empty,
    query: '',
    options: <TextCompletionOption>[],
    selectedIndex: null,
  );

  factory TextCompletionState.open({
    required TextRange range,
    String query = '',
    Iterable<TextCompletionOption> options = const <TextCompletionOption>[],
    int? selectedIndex,
  }) {
    final optionList = List<TextCompletionOption>.unmodifiable(options);
    return TextCompletionState._(
      active: true,
      range: range,
      query: query,
      options: optionList,
      selectedIndex: _normalizeSelectedIndex(
        selectedIndex ?? 0,
        optionList.length,
      ),
    );
  }

  final bool active;
  final TextRange range;
  final String query;
  final List<TextCompletionOption> options;
  final int? selectedIndex;

  bool get hasOptions => options.isNotEmpty;

  TextCompletionOption? get selectedOption {
    final index = selectedIndex;
    if (index == null || index < 0 || index >= options.length) return null;
    return options[index];
  }

  /// Applies the selected completion to [value].
  ///
  /// Returns null when completion is inactive or no option is selected.
  TextEditingValue? apply(
    TextEditingValue value, {
    TextCompletionOption? option,
    bool singleLine = false,
  }) {
    final selected = option ?? selectedOption;
    if (!active || selected == null) return null;
    return TextEditingModel.replaceRange(
      value,
      range,
      selected.replacement,
      singleLine: singleLine,
    );
  }
}

/// Editing-aware completion state controller.
///
/// This owns query/range/options/selection state only. Suggestion providers and
/// popup rendering can be layered above it without changing the text model.
final class TextCompletionController extends ChangeNotifier {
  TextCompletionState _state = TextCompletionState.inactive;
  bool _disposed = false;

  TextCompletionState get state => _state;
  bool get isOpen => _state.active;
  int? get selectedIndex => _state.selectedIndex;
  TextCompletionOption? get selectedOption => _state.selectedOption;

  void open({
    required TextRange range,
    String query = '',
    Iterable<TextCompletionOption> options = const <TextCompletionOption>[],
    int? selectedIndex,
  }) {
    _checkNotDisposed();
    _setState(
      TextCompletionState.open(
        range: range,
        query: query,
        options: options,
        selectedIndex: selectedIndex,
      ),
    );
  }

  void update({
    TextRange? range,
    String? query,
    Iterable<TextCompletionOption>? options,
  }) {
    _checkNotDisposed();
    if (!_state.active) return;
    final optionList = options == null
        ? _state.options
        : List<TextCompletionOption>.unmodifiable(options);
    _setState(
      TextCompletionState.open(
        range: range ?? _state.range,
        query: query ?? _state.query,
        options: optionList,
        selectedIndex: _state.selectedIndex,
      ),
    );
  }

  void close() {
    _checkNotDisposed();
    if (!_state.active) return;
    _setState(TextCompletionState.inactive);
  }

  void select(int index) {
    _checkNotDisposed();
    if (!_state.active || _state.options.isEmpty) return;
    final nextIndex = _normalizeSelectedIndex(index, _state.options.length);
    if (nextIndex == _state.selectedIndex) return;
    _setSelectedIndex(nextIndex);
  }

  void moveSelection(int delta, {bool wrap = true}) {
    _checkNotDisposed();
    if (!_state.active || _state.options.isEmpty || delta == 0) return;
    final current = _state.selectedIndex ?? 0;
    final count = _state.options.length;
    final nextIndex = wrap
        ? (current + delta) % count
        : _clampInt(current + delta, 0, count - 1);
    if (nextIndex == _state.selectedIndex) return;
    _setSelectedIndex(nextIndex);
  }

  /// Applies the selected completion to [value] and closes the controller.
  ///
  /// Returns null when completion is inactive or no option is selected.
  TextEditingValue? accept(TextEditingValue value, {bool singleLine = false}) {
    _checkNotDisposed();
    final next = _state.apply(value, singleLine: singleLine);
    if (next == null) return null;
    close();
    return next;
  }

  void _setSelectedIndex(int? selectedIndex) {
    _setState(
      TextCompletionState._(
        active: _state.active,
        range: _state.range,
        query: _state.query,
        options: _state.options,
        selectedIndex: selectedIndex,
      ),
    );
  }

  void _setState(TextCompletionState state) {
    _checkNotDisposed();
    _state = state;
    notifyListeners();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('TextCompletionController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _state = TextCompletionState.inactive;
    super.dispose();
  }
}

int? _normalizeSelectedIndex(int? index, int optionCount) {
  if (optionCount <= 0) return null;
  if (index == null) return null;
  return _clampInt(index, 0, optionCount - 1);
}

int _clampInt(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}
