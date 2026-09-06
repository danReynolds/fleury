part of 'fleury_tester.dart';

/// Matches the current count of widgets or published semantic nodes.
pkg_test.Matcher hasCount(int count) => _TargetCountMatcher(count);

const pkg_test.Matcher isEnabled = _TargetStateMatcher('enabled');
const pkg_test.Matcher isDisabled = _TargetStateMatcher('disabled');
const pkg_test.Matcher isChecked = _TargetStateMatcher('checked');
const pkg_test.Matcher isUnchecked = _TargetStateMatcher('unchecked');
const pkg_test.Matcher isFocused = _TargetStateMatcher('focused');

/// Matches a control's published value, using an ordinary value or matcher.
/// Redacted values fail without printing either the actual or expected secret;
/// assert fixture-owned persistence callbacks for those controls instead.
pkg_test.Matcher hasValue(Object? expected) => _TargetValueMatcher(expected);

final class _TargetCountMatcher extends pkg_test.Matcher {
  const _TargetCountMatcher(this.expected);
  final int expected;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) {
    if (item is! FleuryTarget) return false;
    final count = item.count;
    matchState['count'] = count;
    return count == expected;
  }

  @override
  pkg_test.Description describe(pkg_test.Description description) =>
      description.add('a target with $expected matches');

  @override
  pkg_test.Description describeMismatch(
    Object? item,
    pkg_test.Description description,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) => description.add('had ${matchState['count']} matches');
}

final class _TargetStateMatcher extends pkg_test.Matcher {
  const _TargetStateMatcher(this.state);
  final String state;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) {
    if (item is! FleuryTarget) return false;
    // Resolution/precondition errors throw, including under isNot().
    final node = item.snapshot;
    if ((state == 'checked' || state == 'unchecked') && node.checked == null) {
      item._fail(
        'Cannot assert $state: target has no checked state.',
        node: node,
      );
    }
    final actual = switch (state) {
      'enabled' => node.enabled,
      'disabled' => !node.enabled,
      'checked' => node.checked!,
      'unchecked' => !node.checked!,
      'focused' => node.focused,
      _ => false,
    };
    matchState['actual'] = actual;
    return actual;
  }

  @override
  pkg_test.Description describe(pkg_test.Description description) =>
      description.add('one $state semantic control');

  @override
  pkg_test.Description describeMismatch(
    Object? item,
    pkg_test.Description description,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) => description.add('was not $state');
}

final class _TargetValueMatcher extends pkg_test.Matcher {
  _TargetValueMatcher(Object? expected)
    : matcher = pkg_test.wrapMatcher(expected);
  final pkg_test.Matcher matcher;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) {
    if (item is! FleuryTarget) return false;
    final node = item.snapshot;
    if (node.state.redactedValue == true ||
        node.state.obscureText == true ||
        node.state.clipboardRedacted == true) {
      item._fail(
        'Value is redacted. Assert a fixture-owned callback instead.',
        node: node,
      );
    }
    matchState['valueObserved'] = true;
    matchState['value'] = node.value;
    final nested = <Object?, Object?>{};
    matchState['nested'] = nested;
    return matcher.matches(node.value, nested);
  }

  @override
  pkg_test.Description describe(pkg_test.Description description) =>
      description.add('one semantic control with the expected value');

  @override
  pkg_test.Description describeMismatch(
    Object? item,
    pkg_test.Description description,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    // package:matcher may call this after matches throws, including for a
    // redacted node or an unresolved scope. Never print expectations then.
    if (matchState['valueObserved'] != true) {
      return description.add('value unavailable; see the target error');
    }
    description
        .add('value ')
        .addDescriptionOf(matchState['value'])
        .add('; expected ');
    return matcher.describe(description);
  }
}
