/// Shared cache accounting for remote inline-image hosts.
///
/// Image bytes are shipped ahead of the presentation plan that references
/// them. The app-side sender and browser-side blob cache must therefore make
/// identical eviction decisions or the sender can incorrectly believe an
/// evicted image is still available. This ledger keeps that policy in one
/// platform-neutral place.
final class InlineImageCachePolicy {
  const InlineImageCachePolicy({
    this.maxEntries = 512,
    this.maxBytes = 32 * 1024 * 1024,
  }) : assert(maxEntries > 0),
       assert(maxBytes > 0);

  /// Maximum number of cached content-hash ids.
  final int maxEntries;

  /// Maximum total encoded bytes for stale and placed images combined.
  ///
  /// Producers must bound each plan's placed working set to this limit;
  /// consumers drop excess or malformed additions rather than exceeding it.
  final int maxBytes;
}

/// The production cache policy shared by the remote sender and browser host.
const defaultInlineImageCachePolicy = InlineImageCachePolicy();

/// Insertion-ordered inline-image cache accounting.
///
/// This tracks encoded byte lengths, not decoded pixels. [evictStale] removes
/// the oldest unplaced entries until both policy bounds are met.
final class InlineImageCacheLedger {
  InlineImageCacheLedger([this.policy = defaultInlineImageCachePolicy]);

  final InlineImageCachePolicy policy;
  final Map<String, int> _byteLengths = <String, int>{};
  int _totalBytes = 0;

  int get entryCount => _byteLengths.length;
  int get totalBytes => _totalBytes;

  bool contains(String id) => _byteLengths.containsKey(id);

  /// Records a newly cached id. Returns false when it was already present.
  bool add(String id, int byteLength) {
    if (byteLength < 0) {
      throw ArgumentError.value(
        byteLength,
        'byteLength',
        'must be non-negative',
      );
    }
    if (_byteLengths.containsKey(id)) return false;
    _byteLengths[id] = byteLength;
    _totalBytes += byteLength;
    return true;
  }

  /// Whether the current cache plus a prospective addition fits the policy.
  bool canFit({int additionalEntries = 0, int additionalBytes = 0}) {
    if (additionalEntries < 0 || additionalBytes < 0) {
      throw ArgumentError('prospective cache additions must be non-negative');
    }
    return entryCount + additionalEntries <= policy.maxEntries &&
        _totalBytes + additionalBytes <= policy.maxBytes;
  }

  /// Evicts the oldest ids not in [placed] until a prospective addition fits.
  ///
  /// The returned ids are in eviction order. If [placed] itself plus the
  /// prospective addition exceeds the policy, every stale entry is removed and
  /// [canFit] remains false; callers can then drop the excess new content.
  List<String> evictStaleToFit(
    Set<String> placed, {
    int additionalEntries = 0,
    int additionalBytes = 0,
  }) {
    if (canFit(
      additionalEntries: additionalEntries,
      additionalBytes: additionalBytes,
    )) {
      return const <String>[];
    }

    final evicted = <String>[];
    for (final entry in _byteLengths.entries.toList(growable: false)) {
      if (canFit(
        additionalEntries: additionalEntries,
        additionalBytes: additionalBytes,
      )) {
        break;
      }
      if (placed.contains(entry.key)) continue;
      _byteLengths.remove(entry.key);
      _totalBytes -= entry.value;
      evicted.add(entry.key);
    }
    return evicted;
  }

  /// Evicts the oldest ids not in [placed], returning them in eviction order.
  List<String> evictStale(Set<String> placed) => evictStaleToFit(placed);

  void clear() {
    _byteLengths.clear();
    _totalBytes = 0;
  }
}
