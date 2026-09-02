import 'dart:collection' show Queue;

import 'package:characters/characters.dart';

import '../input/events.dart';

/// Policy for deciding when paste should be applied over multiple frames.
final class TextPastePolicy {
  const TextPastePolicy({
    this.largePasteThreshold = 8192,
    this.chunkSize = 2048,
  }) : assert(largePasteThreshold >= 0),
       assert(chunkSize > 0);

  /// Pasted text longer than this many Dart string code units is chunked.
  final int largePasteThreshold;

  /// Maximum approximate chunk size in Dart string code units.
  ///
  /// Chunks never split extended grapheme clusters, so an individual chunk may
  /// exceed this value when one grapheme is larger than [chunkSize].
  ///
  /// This is the *smallest* amount of text one frame applies, not the largest:
  /// [TextPasteDriver] batches whole chunks up to the current document length
  /// before touching the model, because each model edit copies the whole
  /// string. See [TextPasteSession.nextBatch].
  final int chunkSize;

  bool shouldChunk(String text) => text.length > largePasteThreshold;

  Iterable<String> chunks(String text) sync* {
    if (text.isEmpty) return;
    if (!shouldChunk(text)) {
      yield text;
      return;
    }

    var buffer = StringBuffer();
    var size = 0;
    for (final grapheme in text.characters) {
      final nextSize = size + grapheme.length;
      if (size > 0 && nextSize > chunkSize) {
        yield buffer.toString();
        buffer = StringBuffer();
        size = 0;
      }
      buffer.write(grapheme);
      size += grapheme.length;
    }
    if (size > 0) yield buffer.toString();
  }
}

/// Progress for an active chunked paste session.
final class TextPasteProgress {
  const TextPasteProgress({
    required this.active,
    required this.insertedLength,
    required this.totalLength,
  });

  static const inactive = TextPasteProgress(
    active: false,
    insertedLength: 0,
    totalLength: 0,
  );

  final bool active;
  final int insertedLength;
  final int totalLength;

  double get fraction {
    if (totalLength <= 0) return active ? 0 : 1;
    return insertedLength / totalLength;
  }
}

/// Mutable iterator over one paste operation.
final class TextPasteSession {
  TextPasteSession({required String text, required TextPastePolicy policy})
    : _text = text,
      totalLength = text.length,
      _chunks = policy.chunks(text).iterator;

  final String _text;
  final int totalLength;
  final Iterator<String> _chunks;
  int _insertedLength = 0;
  bool _complete = false;

  int get insertedLength => _insertedLength;
  bool get isComplete => _complete;

  TextPasteProgress get progress => _complete
      ? TextPasteProgress.inactive
      : TextPasteProgress(
          active: true,
          insertedLength: _insertedLength,
          totalLength: totalLength,
        );

  /// Takes the next batch of unapplied text — at least [minimumCodeUnits] code
  /// units, or the whole remainder when less is left. Null once complete.
  ///
  /// A batch is always a whole number of policy chunks, so it never splits an
  /// extended grapheme cluster, and never fewer than one chunk so a caller
  /// passing `0` still makes progress.
  ///
  /// Batching is what keeps a frame-chunked paste linear. Applying text to the
  /// model costs one copy of the *whole* document per edit, so N chunks cost
  /// O(N x document): a 512 KiB paste in 2 KiB chunks copied 64 MiB. Callers
  /// grow [minimumCodeUnits] with the document, which pays that fixed cost
  /// O(log n) times over the paste instead of once per chunk.
  String? nextBatch(int minimumCodeUnits) {
    if (_complete) return null;
    final start = _insertedLength;
    var taken = 0;
    do {
      if (!_chunks.moveNext()) {
        _complete = true;
        break;
      }
      taken += _chunks.current.length;
    } while (taken < minimumCodeUnits);
    if (taken == 0) return null;
    _insertedLength = start + taken;
    if (_insertedLength >= totalLength) _complete = true;
    // Chunks are contiguous slices of [_text] in order, so the batch is
    // exactly this range — one substring instead of re-joining the chunks.
    return _text.substring(start, _insertedLength);
  }

  /// Takes all unapplied text as one bulk chunk.
  ///
  /// Normal progress remains frame-chunked. Queue-pressure and ordering
  /// barriers use this escape hatch to avoid hundreds of synchronous
  /// whole-string edits while preserving every code unit already accepted.
  String? takeRemaining() {
    if (_complete) return null;
    final remaining = _text.substring(_insertedLength);
    _insertedLength = totalLength;
    _complete = true;
    return remaining.isEmpty ? null : remaining;
  }
}

/// Applies one editable widget's bracketed-paste content to its model, spread
/// over frames so a large paste never blocks the isolate.
///
/// [TextInput] and [TextArea] drove byte-identical copies of this state
/// machine; it lives here so the frame budget below is defined once.
///
/// ### Why a paste is applied in growing steps
///
/// Every model edit rebuilds the whole string ([String.replaceRange]) and
/// produces one full frame, so an edit's cost is dominated by the *document*
/// size, not by how much text the edit carries. Applying a fixed 2 KiB chunk
/// per frame therefore made a paste quadratic in its own size — 512 KiB cost
/// 256 whole-document copies and 256 frames (~12 s end to end).
///
/// Each step instead applies at least as many code units as the document
/// currently holds ([TextPastePolicy.chunkSize] while it is still small). That
/// is the standard amortization: the fixed per-edit cost is never allowed to
/// exceed the payload it carries, so the document grows geometrically, a paste
/// costs O(log n) edits and frames, and total work is linear in the pasted
/// size. It also keeps the first step small, so the leading text appears
/// immediately, and the event loop still turns between steps — input, signals
/// and Ctrl+C are observed while the paste is in flight.
final class TextPasteDriver {
  TextPasteDriver({
    required TextPastePolicy Function() policy,
    required int Function() documentLength,
    required void Function(String text, {required bool coalesce}) applyEdit,
    required bool Function() isAttached,
    required void Function() onProgressChanged,
    required void Function(void Function() callback) schedulePostFrame,
  }) : _policy = policy,
       _documentLength = documentLength,
       _applyEdit = applyEdit,
       _isAttached = isAttached,
       _onProgressChanged = onProgressChanged,
       _schedulePostFrame = schedulePostFrame;

  /// Ceiling on parser segments accepted but not yet applied. A synchronous
  /// [TuiEventSink] cannot signal backpressure, so the queue is drained in
  /// bulk once it passes these bounds.
  static const int _maxQueuedCodeUnits = 64 * 1024;
  static const int _maxQueuedSegments = 256;

  final TextPastePolicy Function() _policy;
  final int Function() _documentLength;
  final void Function(String text, {required bool coalesce}) _applyEdit;
  final bool Function() _isAttached;
  final void Function() _onProgressChanged;
  final void Function(void Function() callback) _schedulePostFrame;

  TextPasteSession? _session;
  final Queue<({String text, bool isFinal})> _queuedSegments =
      Queue<({String text, bool isFinal})>();
  int _queuedCodeUnits = 0;
  bool _active = false;
  bool _finalReceived = false;
  bool _transactionStarted = false;
  bool _currentSegmentIsFinal = false;
  bool _stepScheduled = false;
  int? _activePasteId;
  int _insertedLength = 0;
  int _totalLength = 0;
  TextPasteProgress _progress = TextPasteProgress.inactive;
  int _generation = 0;

  /// Progress of the paste in flight, for semantics and progress indicators.
  TextPasteProgress get progress => _progress;

  /// Whether a paste is accepted but not yet fully applied.
  bool get isActive => _active;

  /// Drops the paste in flight without applying its tail.
  ///
  /// Only for a state change that invalidates the destination itself — a
  /// swapped controller, a field turned read-only, disposal. Every ordinary
  /// interruption uses [finish].
  void discard() {
    _generation++;
    _session = null;
    _queuedSegments.clear();
    _queuedCodeUnits = 0;
    _active = false;
    _finalReceived = false;
    _transactionStarted = false;
    _currentSegmentIsFinal = false;
    _stepScheduled = false;
    _activePasteId = null;
    _insertedLength = 0;
    _totalLength = 0;
    _progress = TextPasteProgress.inactive;
  }

  /// Finishes an accepted paste before the next editing transaction.
  ///
  /// Frame chunking is a responsiveness policy, not permission to discard the
  /// unapplied tail when a second paste or key action arrives.
  void finish() {
    if (!_active) {
      discard();
      return;
    }
    final pending = StringBuffer();
    final session = _session;
    if (session != null) {
      final remaining = session.takeRemaining();
      if (remaining != null) pending.write(remaining);
    }
    while (_queuedSegments.isNotEmpty) {
      pending.write(_queuedSegments.removeFirst().text);
    }
    final text = pending.toString();
    if (text.isNotEmpty) _applyBulk(text);
    _complete();
  }

  /// Accepts one paste event's already-normalized [text].
  void start(PasteEvent event, String text) {
    final continuesActivePaste =
        _active &&
        !event.isFirst &&
        !_finalReceived &&
        event.pasteId == _activePasteId;
    if (!continuesActivePaste) {
      finish();
      _active = true;
      _activePasteId = event.pasteId;
    }

    _queuedSegments.addLast((text: text, isFinal: event.isFinal));
    _queuedCodeUnits += text.length;
    _totalLength += text.length;
    if (event.isFinal) _finalReceived = true;

    final generation = _generation;
    if (_session == null) _applyNextStep(generation);
    _drainQueuedToBound(generation);
    _updateProgress();
    if (_isAttached()) _onProgressChanged();
    _scheduleNextStep(generation);
  }

  bool get _hasPendingWork => _session != null || _queuedSegments.isNotEmpty;

  bool get _queueIsOverBound =>
      _queuedCodeUnits > _maxQueuedCodeUnits ||
      _queuedSegments.length > _maxQueuedSegments;

  /// Code units one step applies: at least one policy chunk, and at least the
  /// current document length. See the class doc — the fixed cost of an edit is
  /// a whole-document copy, so a step must never carry less than that.
  int get _stepCodeUnits {
    final chunk = _policy().chunkSize;
    final document = _documentLength();
    return document > chunk ? document : chunk;
  }

  void _drainQueuedToBound(int generation) {
    // TuiEventSink is synchronous, so it cannot signal parser backpressure.
    // Collapse only the active tail under pressure, in one controller edit,
    // then promote a queued parser segment to the separately bounded active
    // slot. This avoids hundreds of synchronous 2 KiB edits per segment.
    while (_queueIsOverBound && generation == _generation && _active) {
      if (_session == null && !_activateNextSegment(generation)) break;
      if (!_queueIsOverBound || generation != _generation) break;
      final session = _session!;
      final remaining = session.takeRemaining();
      if (remaining != null) _applyBulk(remaining);
      _session = null;
      if (_currentSegmentIsFinal) _complete();
    }
  }

  bool _activateNextSegment(int generation) {
    while (_session == null && _active && generation == _generation) {
      if (_queuedSegments.isEmpty) return false;
      final segment = _queuedSegments.removeFirst();
      _queuedCodeUnits -= segment.text.length;
      _currentSegmentIsFinal = segment.isFinal;
      if (segment.text.isEmpty) {
        if (segment.isFinal) _complete();
        continue;
      }
      _session = TextPasteSession(text: segment.text, policy: _policy());
    }
    return _session != null;
  }

  void _applyBulk(String text) {
    _applyEdit(text, coalesce: _transactionStarted);
    _transactionStarted = true;
    _insertedLength += text.length;
    _updateProgress();
  }

  bool _applyNextStep(int generation) {
    if (!_isAttached() || generation != _generation || !_active) return false;

    // Skip empty phase markers iteratively. A paste whose last data segment
    // lands exactly on the parser byte cap ends with an empty `end` event that
    // must close (not add to) the undo transaction.
    while (_active && generation == _generation) {
      if (_session == null && !_activateNextSegment(generation)) return false;
      if (!_active || generation != _generation) return false;

      final session = _session!;
      final batch = session.nextBatch(_stepCodeUnits);
      if (batch == null) {
        _session = null;
        if (_currentSegmentIsFinal) _complete();
        continue;
      }

      _applyEdit(batch, coalesce: _transactionStarted);
      _transactionStarted = true;
      _insertedLength += batch.length;
      if (session.isComplete) {
        _session = null;
        if (_currentSegmentIsFinal) _complete();
      }
      _updateProgress();
      return true;
    }
    return false;
  }

  void _complete() {
    _generation++;
    _session = null;
    _queuedSegments.clear();
    _queuedCodeUnits = 0;
    _active = false;
    _finalReceived = false;
    _transactionStarted = false;
    _currentSegmentIsFinal = false;
    _stepScheduled = false;
    _activePasteId = null;
    _insertedLength = 0;
    _totalLength = 0;
    _progress = TextPasteProgress.inactive;
  }

  void _updateProgress() {
    _progress = _active
        ? TextPasteProgress(
            active: true,
            insertedLength: _insertedLength,
            totalLength: _totalLength,
          )
        : TextPasteProgress.inactive;
  }

  void _scheduleNextStep(int generation) {
    if (generation != _generation ||
        !_active ||
        !_hasPendingWork ||
        _stepScheduled) {
      return;
    }
    _stepScheduled = true;
    _schedulePostFrame(() => _runScheduledStep(generation));
  }

  void _runScheduledStep(int generation) {
    if (!_isAttached() || generation != _generation) return;
    _stepScheduled = false;
    _applyNextStep(generation);
    _updateProgress();
    if (_isAttached()) _onProgressChanged();
    _scheduleNextStep(generation);
  }
}
