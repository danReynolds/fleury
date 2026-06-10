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
      'FormPanel',
      'FormWizard',
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
      'ProcessPanel',
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
    expect(
      story('workflow.process-trace.process-panel').defaultControlValues,
      containsPair('view', 2),
    );
  });
}
