// One scenario drives both dart test and the guide's visible test runner.
import 'package:fleury/fleury_core.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart' show Matcher;

import '../../lib/testing_guide.dart';

enum PreferencesTestStep {
  mounted(
    'Start with two fresh forms',
    'tester.pumpWidget(preferencesPair());',
  ),
  filled('Fill Work name with Ada', "await work.field('Name').fill('Ada');"),
  checked(
    'Check Work email updates',
    "await work.checkbox('Email updates').check();",
  ),
  workName(
    'Work name is Ada',
    "expect(work.field('Name'), hasValue('Ada'));",
    assertion: true,
  ),
  workChecked(
    'Work updates are checked',
    "expect(work.checkbox('Email updates'), isChecked);",
    assertion: true,
  ),
  personalName(
    'Personal name is still empty',
    "expect(personal.field('Name'), hasValue(''));",
    assertion: true,
  ),
  personalUnchecked(
    'Personal updates are still off',
    "expect(personal.checkbox('Email updates'), isUnchecked);",
    assertion: true,
  );

  const PreferencesTestStep(this.label, this.code, {this.assertion = false});
  final String label;
  final String code;
  final bool assertion;
}

/// Yields only after the real action or assertion succeeds. The browser adds
/// pauses between yields; command-line tests consume the same scenario at once.
Stream<PreferencesTestStep> runPreferencesTest(
  FleuryTester tester, {
  required void Function(Object?, Matcher) expect,
}) async* {
  // #docregion preferences-test
  tester.pumpWidget(preferencesPair());
  final work = tester.target(type: Preferences, key: const ValueKey('work'));
  yield PreferencesTestStep.mounted;

  await work.field('Name').fill('Ada');
  yield PreferencesTestStep.filled;
  await work.checkbox('Email updates').check();
  yield PreferencesTestStep.checked;

  expect(work.field('Name'), hasValue('Ada'));
  yield PreferencesTestStep.workName;
  expect(work.checkbox('Email updates'), isChecked);
  yield PreferencesTestStep.workChecked;
  final personal = tester.target(key: const ValueKey('personal'));
  expect(personal.field('Name'), hasValue(''));
  yield PreferencesTestStep.personalName;
  expect(personal.checkbox('Email updates'), isUnchecked);
  yield PreferencesTestStep.personalUnchecked;
  // #enddocregion preferences-test
}
