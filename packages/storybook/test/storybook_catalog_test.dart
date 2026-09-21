import 'dart:io';

import 'package:fleury_storybook/src/storybook_runner.dart';
import 'package:fleury_storybook/storybook.dart';
import 'package:test/test.dart';

void main() {
  test('catalog has stable unique story ids and useful metadata', () {
    expect(storybookStories, isNotEmpty);

    final ids = <String>{};
    for (final story in storybookStories) {
      expect(ids.add(story.id), isTrue, reason: 'duplicate id ${story.id}');
      expect(story.title.trim(), isNotEmpty);
      expect(story.category.trim(), isNotEmpty);
      expect(story.description.trim(), isNotEmpty);
      expect(story.widgets, isNotEmpty, reason: story.id);
      expect(story.widgets, hasLength(1), reason: story.id);
      expect(story.initialHeight, greaterThan(0), reason: story.id);

      final controlIds = <String>{};
      for (final control in story.controls) {
        expect(controlIds.add(control.id), isTrue, reason: story.id);
        expect(control.id.trim(), isNotEmpty, reason: story.id);
        expect(control.label.trim(), isNotEmpty, reason: story.id);
        expect(control.initialValue, isNotNull, reason: story.id);

        switch (control.type) {
          case StoryControlType.option:
          case StoryControlType.toggle:
            expect(
              control.options,
              isNotEmpty,
              reason: '${story.id}/${control.id}',
            );
            expect(
              control.initialIndex,
              inInclusiveRange(0, control.options.length - 1),
              reason: '${story.id}/${control.id}',
            );
          case StoryControlType.text:
          case StoryControlType.number:
            expect(
              control.options,
              isEmpty,
              reason: '${story.id}/${control.id}',
            );
        }
      }

      final variantIds = <String>{};
      for (final variant in story.variants) {
        expect(variantIds.add(variant.id), isTrue, reason: story.id);
        expect(variant.id.trim(), isNotEmpty, reason: story.id);
        expect(variant.label.trim(), isNotEmpty, reason: story.id);
        for (final controlId in variant.controlValues.keys) {
          expect(
            controlIds,
            contains(controlId),
            reason: '${story.id}/${variant.id}',
          );
        }
      }
    }
  });

  test('catalog covers the primary public widget families', () {
    final covered = <String>{
      for (final story in storybookStories) ...story.widgets,
    };

    const expected = <String>{
      'Button',
      'Checkbox',
      'Select',
      'MultiSelect',
      'TextInput',
      'TextArea',
      'DatePicker',
      'ColorPicker',
      'Menu',
      'CommandPalette',
      'Tabs',
      'Table',
      'DataTable',
      'Tree',
      'TreeTable',
      'Form',
      'FormField',
      'BarChart',
      'LineChart',
      'Canvas',
      'Image',
      'FileBrowser',
      'FilePicker',
      'SearchPanel',
      'LogRegion',
      'TerminalOutputRegion',
      'CodeView',
      'DiffView',
      'PatchReview',
      'JsonView',
      'MarkdownView',
      'ContextPanel',
      'MessageList',
      'ConversationNavigator',
      'ModelStatusBar',
      'TokenMeter',
      'ToolCallCard',
      'ApprovalPrompt',
      'TaskGraph',
      'TraceTimeline',
    };

    expect(covered, containsAll(expected));
  });

  test('per-widget stories open on widget-relevant control defaults', () {
    Story story(String id) =>
        storybookStories.singleWhere((story) => story.id == id);

    expect(
      story('content.source-documents.patch-review').defaultControlValues,
      containsPair('document', 2),
    );
    expect(
      story('logs.search.terminal-output-region').defaultControlValues,
      containsPair('view', 2),
    );
    expect(
      story('agent.context-messages.message-list').defaultControlValues,
      containsPair('view', 1),
    );
  });

  const stateApis = <String, String>{
    'Scope': 'state.tree.scope',
    'ScopeBuilder': 'state.tree.scope-builder',
    'Notifier': 'state.model.notifier',
    'NotifierBuilder': 'state.model.notifier-builder',
    'ValueNotifier': 'state.value.value-notifier',
  };

  test('core state APIs have dedicated stories and both consumer forms', () {
    for (final entry in stateApis.entries) {
      final story = storybookStories.singleWhere(
        (story) => story.id == entry.value,
      );
      expect(story.widgets, [entry.key]);
      expect(story.category, 'State');
      expect(story.usage, isNotEmpty);
      final readers = <Object?>{
        story.initialControlValues()['reader'],
        for (final variant in story.variants)
          story.initialControlValues(variant: variant)['reader'],
      };
      expect(readers, {0, 1}, reason: '${entry.key} needs both consumer forms');
    }
  });

  for (final api in stateApis.keys) {
    test('strict coverage detects a missing core $api story', () {
      final report = buildStorybookCoverageReport(
        stories: storybookStories
            .where((story) => !story.widgets.contains(api))
            .toList(),
        exportedLibrary: File('../fleury_widgets/lib/fleury_widgets.dart'),
      );

      expect(report.complete, isFalse);
      expect(report.missingWidgets, [api]);
      expect(report.exportedWidgets, containsAll(stateApis.keys));
      expect(report.exportedWidgets, isNot(contains('BuildOwner')));
      expect(report.exportedWidgets, isNot(contains('InheritedWidget')));
    });
  }
}
