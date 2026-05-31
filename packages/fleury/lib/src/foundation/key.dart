import 'package:meta/meta.dart';

/// A token used by the widget framework to control element reuse during
/// reconciliation.
///
/// Two widgets at the same tree position reuse the same [Element] (and the
/// [State] it carries, for `StatefulWidget`s) when they share both
/// `runtimeType` and `Key`. See `Widget.canUpdate`.
@immutable
abstract class Key {
  const Key._();

  /// Constructor for [Key] subclasses defined outside this library (e.g.
  /// `GlobalKey`, which lives with the element machinery it indexes into).
  const Key.empty();
}

/// Base class for chords that are local to a parent's children list.
///
/// Local chords must compare equal across rebuilds when they identify the same
/// logical child. [GlobalKey] is the cross-tree counterpart.
@immutable
abstract class LocalKey extends Key {
  const LocalKey() : super._();
}

/// A key carrying a single value whose equality determines the key's
/// equality. The most common kind of key in application code.
@immutable
final class ValueKey<T> extends LocalKey {
  const ValueKey(this.value);

  final T value;

  @override
  bool operator ==(Object other) {
    if (other is! ValueKey<T>) return false;
    return other.value == value;
  }

  @override
  int get hashCode => Object.hash(ValueKey<T>, value);

  @override
  String toString() => 'ValueKey<$T>($value)';
}

/// A key that is equal only to itself.
///
/// Used when the only identity that matters is "this is a different child
/// from any other child" — for example to force a remount.
final class UniqueKey extends LocalKey {
  UniqueKey();

  @override
  String toString() => 'UniqueKey#${identityHashCode(this).toRadixString(16)}';
}
