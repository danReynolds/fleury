import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';

import 'story.dart';
import 'storybook_options.dart';

final class StorybookToolException implements Exception {
  const StorybookToolException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class StorybookTarget {
  const StorybookTarget({
    required this.story,
    required this.variant,
    required this.values,
  });

  final Story story;
  final StoryVariant? variant;
  final Map<String, Object?> values;

  String get id => variant == null ? story.id : '${story.id}:${variant!.id}';

  String get snapshotFileName {
    final suffix = variant == null ? 'default' : variant!.id;
    return '${_fileSafe(story.id)}__$suffix.txt';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'storyId': story.id,
    'title': story.title,
    'category': story.category,
    'variantId': variant?.id ?? 'default',
    'variantLabel': variant?.label ?? 'Default',
    'controls': values,
  };
}

final class StorybookRenderResult {
  const StorybookRenderResult({
    required this.target,
    required this.size,
    required this.output,
    required this.semantics,
    required this.actions,
  });

  final StorybookTarget target;
  final CellSize size;
  final String output;
  final SemanticInspectionSnapshot semantics;
  final List<StoryAction> actions;

  Map<String, Object?> toJson({bool includeOutput = false}) {
    return <String, Object?>{
      ...target.toJson(),
      'cols': size.cols,
      'rows': size.rows,
      'renderedCells': output.trimRight().length,
      'semanticNodeCount': semantics.nodeCount,
      'focusedNodeId': semantics.focusedNodeId,
      'semanticActionCount': semantics.actionCount,
      'roleCounts': semantics.roleCounts,
      'recordedActions': [
        for (final action in actions)
          <String, Object?>{
            'sequence': action.sequence,
            'storyId': action.storyId,
            'name': action.name,
            'data': action.data,
          },
      ],
      if (includeOutput) 'output': output,
    };
  }
}

final class StorybookVerifyReport {
  const StorybookVerifyReport({
    required this.results,
    required this.failures,
    required this.size,
  });

  final List<StorybookRenderResult> results;
  final List<StorybookVerifyFailure> failures;
  final CellSize size;

  bool get passed => failures.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'passed': passed,
    'targetCount': results.length + failures.length,
    'passedCount': results.length,
    'failedCount': failures.length,
    'cols': size.cols,
    'rows': size.rows,
    'results': [for (final result in results) result.toJson()],
    'failures': [for (final failure in failures) failure.toJson()],
  };
}

final class StorybookVerifyFailure {
  const StorybookVerifyFailure({
    required this.target,
    required this.message,
    required this.stackTrace,
  });

  final StorybookTarget target;
  final String message;
  final String? stackTrace;

  Map<String, Object?> toJson() => <String, Object?>{
    ...target.toJson(),
    'message': message,
    if (stackTrace != null) 'stackTrace': stackTrace,
  };
}

final class StorybookCoverageReport {
  const StorybookCoverageReport({
    required this.exportedWidgets,
    required this.coveredWidgets,
    required this.missingWidgets,
    required this.extraCatalogWidgets,
    required this.storiesByWidget,
  });

  final List<String> exportedWidgets;
  final List<String> coveredWidgets;
  final List<String> missingWidgets;
  final List<String> extraCatalogWidgets;
  final Map<String, List<String>> storiesByWidget;

  bool get complete => missingWidgets.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'complete': complete,
    'exportedWidgetCount': exportedWidgets.length,
    'coveredWidgetCount': coveredWidgets.length,
    'missingWidgetCount': missingWidgets.length,
    'exportedWidgets': exportedWidgets,
    'coveredWidgets': coveredWidgets,
    'missingWidgets': missingWidgets,
    'extraCatalogWidgets': extraCatalogWidgets,
    'storiesByWidget': storiesByWidget,
  };
}

List<StorybookTarget> storybookTargets({
  required List<Story> stories,
  String? storyId,
  String? variantId,
  bool includeVariants = true,
  Map<String, Object?> controlOverrides = const <String, Object?>{},
}) {
  final selectedStories = storyId == null
      ? stories
      : stories.where((story) => story.id == storyId).toList(growable: false);
  if (selectedStories.isEmpty) {
    throw StorybookToolException('Unknown story: $storyId');
  }
  if (controlOverrides.isNotEmpty && selectedStories.length != 1) {
    throw const StorybookToolException(
      '--control requires --story so control ids are unambiguous.',
    );
  }

  final targets = <StorybookTarget>[];
  for (final story in selectedStories) {
    if (variantId != null) {
      if (variantId == 'default') {
        targets.add(
          StorybookTarget(
            story: story,
            variant: null,
            values: story.initialControlValues(overrides: controlOverrides),
          ),
        );
        continue;
      }
      final variant = story.variants
          .where((variant) => variant.id == variantId)
          .firstOrNull;
      if (variant == null) {
        throw StorybookToolException(
          'Unknown variant for ${story.id}: $variantId',
        );
      }
      targets.add(
        StorybookTarget(
          story: story,
          variant: variant,
          values: story.initialControlValues(
            variant: variant,
            overrides: controlOverrides,
          ),
        ),
      );
      continue;
    }

    targets.add(
      StorybookTarget(
        story: story,
        variant: null,
        values: story.initialControlValues(overrides: controlOverrides),
      ),
    );
    if (!includeVariants) continue;
    for (final variant in story.variants) {
      targets.add(
        StorybookTarget(
          story: story,
          variant: variant,
          values: story.initialControlValues(variant: variant),
        ),
      );
    }
  }
  return targets;
}

Map<String, Object?> parseControlOverrides(
  Story story,
  Iterable<String> specs,
) {
  final values = <String, Object?>{};
  for (final spec in specs) {
    final separator = spec.indexOf('=');
    if (separator <= 0) {
      throw StorybookToolException(
        'Invalid control override "$spec"; expected control=value.',
      );
    }
    final id = spec.substring(0, separator);
    final raw = spec.substring(separator + 1);
    final control = story.controls
        .where((control) => control.id == id)
        .firstOrNull;
    if (control == null) {
      throw StorybookToolException('Unknown control for ${story.id}: $id');
    }
    values[id] = parseControlValue(control, raw);
  }
  return values;
}

Object? parseControlValue(StoryControl control, String raw) {
  return switch (control.type) {
    StoryControlType.option => _parseOptionControl(control, raw),
    StoryControlType.toggle => _parseToggleControl(control, raw),
    StoryControlType.text => raw,
    StoryControlType.number => _parseNumberControl(control, raw),
  };
}

StorybookRenderResult renderStorybookTarget(
  StorybookTarget target, {
  required CellSize size,
  required StorybookThemeMode theme,
}) {
  final tester = FleuryTester(viewportSize: size);
  final actions = <StoryAction>[];
  var actionSequence = 0;
  try {
    tester.pumpWidget(
      Theme(
        data: storybookThemeFor(theme),
        child: FleuryApp(
          title: 'Fleury Storybook Snapshot',
          child: Navigator(
            home: CommandScope(
              label: 'Snapshot story commands',
              commands: const <AppCommand>[],
              child: target.story.builder(
                StoryBuildContext(
                  story: target.story,
                  variant: target.variant,
                  selectedWidgetName: target.story.widgets.isEmpty
                      ? target.story.title
                      : target.story.widgets.first,
                  values: target.values,
                  recordAction: (name, [data = const <String, Object?>{}]) {
                    actionSequence += 1;
                    actions.add(
                      StoryAction(
                        sequence: actionSequence,
                        storyId: target.story.id,
                        name: name,
                        data: Map<String, Object?>.unmodifiable(data),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    tester.pump();
    final output = tester.renderToString(size: size, emptyMark: ' ');
    final semantics = tester.semanticInspectionSnapshot();
    if (output.trim().isEmpty) {
      throw StateError('rendered output was empty');
    }
    return StorybookRenderResult(
      target: target,
      size: size,
      output: output,
      semantics: semantics,
      actions: List<StoryAction>.unmodifiable(actions),
    );
  } finally {
    tester.dispose();
  }
}

StorybookVerifyReport verifyStorybookTargets(
  List<StorybookTarget> targets, {
  required CellSize size,
  required StorybookThemeMode theme,
}) {
  final results = <StorybookRenderResult>[];
  final failures = <StorybookVerifyFailure>[];
  for (final target in targets) {
    try {
      final result = renderStorybookTarget(target, size: size, theme: theme);
      results.add(result);
    } catch (error, stackTrace) {
      failures.add(
        StorybookVerifyFailure(
          target: target,
          message: error.toString(),
          stackTrace: stackTrace.toString(),
        ),
      );
    }
  }
  return StorybookVerifyReport(
    results: results,
    failures: failures,
    size: size,
  );
}

List<File> writeStorybookSnapshots(
  List<StorybookRenderResult> results, {
  required Directory outputDirectory,
  required StorybookThemeMode theme,
}) {
  outputDirectory.createSync(recursive: true);
  final files = <File>[];
  for (final result in results) {
    final file = File(
      '${outputDirectory.path}/${result.target.snapshotFileName}',
    );
    final buffer = StringBuffer()
      ..writeln('# ${result.target.id}')
      ..writeln('story: ${result.target.story.title}')
      ..writeln('category: ${result.target.story.category}')
      ..writeln('variant: ${result.target.variant?.label ?? 'Default'}')
      ..writeln('theme: ${storybookThemeLabel(theme)}')
      ..writeln('size: ${result.size.cols}x${result.size.rows}')
      ..writeln('semanticNodes: ${result.semantics.nodeCount}')
      ..writeln()
      ..write(result.output.trimRight())
      ..writeln();
    file.writeAsStringSync(buffer.toString());
    files.add(file);
  }
  return files;
}

StorybookCoverageReport buildStorybookCoverageReport({
  required List<Story> stories,
  required File exportedLibrary,
}) {
  final exported = exportedWidgetSymbols(exportedLibrary);
  final storiesByWidget = <String, List<String>>{};
  for (final story in stories) {
    for (final widget in story.widgets) {
      storiesByWidget.putIfAbsent(widget, () => <String>[]).add(story.id);
    }
  }

  final coveredSet = storiesByWidget.keys.toSet();
  final exportedSet = exported.toSet();
  final covered = exported.where(coveredSet.contains).toList(growable: false);
  final missing = exported
      .where((name) => !coveredSet.contains(name))
      .toList(growable: false);
  final extra = coveredSet.where((name) => !exportedSet.contains(name)).toList()
    ..sort();
  final sortedStoriesByWidget = <String, List<String>>{
    for (final widget in storiesByWidget.keys.toList()..sort())
      widget: List<String>.unmodifiable(storiesByWidget[widget]!),
  };

  return StorybookCoverageReport(
    exportedWidgets: exported,
    coveredWidgets: covered,
    missingWidgets: missing,
    extraCatalogWidgets: extra,
    storiesByWidget: sortedStoriesByWidget,
  );
}

List<String> exportedWidgetSymbols(File libraryFile) {
  final text = libraryFile.readAsStringSync();
  final symbols = <String>{};
  final exportPattern = RegExp(
    r"export\s+'[^']+'\s+show\s+([^;]+);",
    multiLine: true,
    dotAll: true,
  );
  for (final match in exportPattern.allMatches(text)) {
    final body = match.group(1)!;
    for (final raw in body.split(',')) {
      final symbol = raw.trim();
      if (_looksLikeWidgetExport(symbol)) symbols.add(symbol);
    }
  }
  return symbols.toList()..sort();
}

String encodeJson(Object? value) {
  return const JsonEncoder.withIndent('  ').convert(value);
}

int _parseOptionControl(StoryControl control, String raw) {
  final index = int.tryParse(raw);
  if (index != null) {
    if (index < 0 || index >= control.options.length) {
      throw StorybookToolException(
        '${control.id} index $index is outside 0-${control.options.length - 1}.',
      );
    }
    return index;
  }
  final normalized = raw.toLowerCase();
  final found = control.options.indexWhere(
    (option) => option.toLowerCase() == normalized,
  );
  if (found < 0) {
    throw StorybookToolException(
      '${control.id} expected one of ${control.options.join(', ')}.',
    );
  }
  return found;
}

int _parseToggleControl(StoryControl control, String raw) {
  final normalized = raw.toLowerCase();
  return switch (normalized) {
    '1' || 'true' || 'yes' || 'on' || 'enabled' || 'enable' => 1,
    '0' || 'false' || 'no' || 'off' || 'disabled' || 'disable' => 0,
    _ => _parseOptionControl(control, raw),
  };
}

num _parseNumberControl(StoryControl control, String raw) {
  final value = num.tryParse(raw);
  if (value == null) {
    throw StorybookToolException('${control.id} expected a number.');
  }
  return control.normalizedNumber(value);
}

bool _looksLikeWidgetExport(String symbol) {
  if (symbol.isEmpty || !_isUppercase(symbol.codeUnitAt(0))) return false;
  const excludedSuffixes = <String>{
    'Builder',
    'Callback',
    'Controller',
    'Descriptor',
    'Direction',
    'Entry',
    'Format',
    'Formatter',
    'Health',
    'Info',
    'Kind',
    'Matcher',
    'Metrics',
    'Mode',
    'Options',
    'Provider',
    'Range',
    'Record',
    'Request',
    'Result',
    'Severity',
    'Source',
    'Status',
    'Type',
  };
  for (final suffix in excludedSuffixes) {
    if (symbol.endsWith(suffix)) return false;
  }
  const excludedNames = <String>{
    'ApprovalDecision',
    'ApprovalRequest',
    'Bar',
    'ButtonVariant',
    'CalendarWeekStart',
    'CanvasBounds',
    'CanvasContext',
    'CanvasMarker',
    'CodeDocument',
    'CodeLine',
    'Command',
    'ContextItemPriority',
    'DiffDocument',
    'DiffLine',
    'FileBrowserEntry',
    'FileBrowserEntityFilter',
    'FixedColumnWidth',
    'FleuryWidgetTheme',
    'FlexColumnWidth',
    'FormDefinition',
    'FormFieldAsyncValidator',
    'FormFieldSnapshot',
    'FormFieldSpec',
    'FormFieldValidator',
    'FormOption',
    'FormPanelLayout',
    'FormPrompt',
    'FormPromptSession',
    'FormSnapshot',
    'FormValues',
    'ImageFit',
    'ImageGlyph',
    'IntrinsicColumnWidth',
    'JsonViewDocument',
    'JsonViewRow',
    'LineSeries',
    'LogRegionSearchIndex',
    'MarkdownBlock',
    'MarkdownDocument',
    'MarkdownLink',
    'MenuEntry',
    'MenuSeparator',
    'MessageRole',
    'Palettes',
    'PatchReviewFile',
    'ReferenceLine',
    'ReferenceStyle',
    'SearchResult',
    'SearchResultIndex',
    'TableColumnWidth',
    'TaskGraphNode',
    'TextCompletionRequest',
    'TextCompletionRequestBuilder',
    'TickFormat',
    'ToastAction',
    'TokenUsage',
    'ToolCallRecord',
    'TreeNode',
    'TreeTableNode',
    'TreeTableRow',
    'TreeTableSearchIndex',
    'WorkflowSnapshot',
    'WorkflowSummary',
  };
  return !excludedNames.contains(symbol);
}

bool _isUppercase(int codeUnit) => codeUnit >= 65 && codeUnit <= 90;

String _fileSafe(String value) {
  return value.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]+'), '_');
}
