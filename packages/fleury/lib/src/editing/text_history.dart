import '../foundation/change_notifier.dart';
import 'text_editing.dart';

/// Command/submission history layered above [TextEditingValue].
///
/// This controller is intentionally separate from undo/redo history. Undo
/// tracks editing transactions inside one value; submission history stores
/// previously accepted field values for REPLs, command inputs, and agent
/// composers.
final class TextHistoryController extends ChangeNotifier {
  TextHistoryController({
    Iterable<String> entries = const <String>[],
    this.maxEntries = 200,
    this.storeDuplicateConsecutiveEntries = false,
  }) : assert(maxEntries > 0, 'maxEntries must be positive') {
    _entries.addAll(entries);
    _trimToMaxEntries();
  }

  final int maxEntries;
  final bool storeDuplicateConsecutiveEntries;

  final List<String> _entries = <String>[];
  String? _draft;
  int? _selectedIndex;
  bool _disposed = false;

  List<String> get entries => List.unmodifiable(_entries);
  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;
  bool get isNotEmpty => _entries.isNotEmpty;

  /// The selected history entry while browsing, or null for the current draft.
  int? get selectedIndex => _selectedIndex;

  /// Whether navigation is currently showing a history entry.
  bool get isBrowsing => _selectedIndex != null;

  /// The draft captured before entering history browsing.
  String? get draft => _draft;

  bool get canNavigatePrevious =>
      _entries.isNotEmpty && (_selectedIndex == null || _selectedIndex! > 0);

  bool get canNavigateNext => _selectedIndex != null;

  /// Stores an accepted field value.
  ///
  /// Empty values are skipped by default. Consecutive duplicate entries are
  /// skipped unless [storeDuplicateConsecutiveEntries] is true.
  void commit(String text, {bool skipEmpty = true}) {
    _checkNotDisposed();
    var changed = false;
    if (!(skipEmpty && text.isEmpty) &&
        (storeDuplicateConsecutiveEntries ||
            _entries.isEmpty ||
            _entries.last != text)) {
      _entries.add(text);
      _trimToMaxEntries();
      changed = true;
    }
    changed = _clearBrowsingState() || changed;
    if (changed) notifyListeners();
  }

  /// Removes all entries and any captured draft state.
  void clear() {
    _checkNotDisposed();
    final hadEntries = _entries.isNotEmpty;
    final browsingChanged = _clearBrowsingState();
    _entries.clear();
    if (hadEntries || browsingChanged) notifyListeners();
  }

  /// Replaces all history entries.
  void replaceAll(Iterable<String> entries) {
    _checkNotDisposed();
    _entries
      ..clear()
      ..addAll(entries);
    _trimToMaxEntries();
    _clearBrowsingState();
    notifyListeners();
  }

  /// Moves toward older entries and returns the value to display.
  ///
  /// The first call captures `current.text` as the draft so navigating forward
  /// past the newest history entry can restore it.
  TextEditingValue? navigatePrevious(TextEditingValue current) {
    _checkNotDisposed();
    if (_entries.isEmpty) return null;

    if (_selectedIndex == null) {
      _draft = current.text;
      _selectedIndex = _entries.length - 1;
      notifyListeners();
      return _valueFor(_entries[_selectedIndex!]);
    }

    if (_selectedIndex! > 0) {
      _selectedIndex = _selectedIndex! - 1;
      notifyListeners();
    }
    return _valueFor(_entries[_selectedIndex!]);
  }

  /// Moves toward newer entries, restoring the captured draft at the end.
  TextEditingValue? navigateNext() {
    _checkNotDisposed();
    final index = _selectedIndex;
    if (index == null) return null;

    if (index < _entries.length - 1) {
      _selectedIndex = index + 1;
      notifyListeners();
      return _valueFor(_entries[_selectedIndex!]);
    }

    final draft = _draft ?? '';
    _clearBrowsingState();
    notifyListeners();
    return _valueFor(draft);
  }

  /// Leaves history browsing without changing stored entries.
  void resetBrowsing() {
    _checkNotDisposed();
    if (_clearBrowsingState()) notifyListeners();
  }

  TextEditingValue _valueFor(String text) => TextEditingValue(text: text);

  bool _clearBrowsingState() {
    if (_draft == null && _selectedIndex == null) return false;
    _draft = null;
    _selectedIndex = null;
    return true;
  }

  void _trimToMaxEntries() {
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('TextHistoryController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearBrowsingState();
    super.dispose();
  }
}
