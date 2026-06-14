import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

import 'catalog.dart';
import 'story.dart';
import 'storybook_options.dart';

class StorybookApp extends StatefulWidget {
  StorybookApp({
    super.key,
    List<Story>? stories,
    this.initialStoryId,
    this.initialVariantId,
    this.initialControlValues = const <String, Object?>{},
    this.initialTheme = StorybookThemeMode.terminal,
    this.initialViewport = StorybookViewportPreset.fit,
  }) : stories = stories ?? storybookStories;

  final List<Story> stories;
  final String? initialStoryId;
  final String? initialVariantId;
  final Map<String, Object?> initialControlValues;
  final StorybookThemeMode initialTheme;
  final StorybookViewportPreset initialViewport;

  @override
  State<StorybookApp> createState() => _StorybookAppState();
}

class _StorybookAppState extends State<StorybookApp> {
  late int _selectedIndex;
  late String _selectedWidgetName;
  late StorybookThemeMode _themeMode;
  late StorybookViewportPreset _viewport;
  bool _showInspector = true;
  bool _compactPreview = false;
  int _resetGeneration = 0;
  int _actionSequence = 0;
  final Map<String, Map<String, Object?>> _controlValues = {};
  final Map<String, int> _variantIndexes = <String, int>{};
  final List<StoryAction> _actionLog = <StoryAction>[];

  Story get _selectedStory => widget.stories[_selectedIndex];

  StoryVariant? get _selectedVariant {
    final variants = _selectedStory.variants;
    if (variants.isEmpty) return null;
    final slot = _variantIndexes[_selectedStory.id] ?? 0;
    if (slot <= 0) return null;
    return variants[(slot - 1).clamp(0, variants.length - 1)];
  }

  Map<String, Object?> get _selectedControlValues {
    final story = _selectedStory;
    final variant = _selectedVariant;
    return _controlValues.putIfAbsent(_targetKey(story, variant), () {
      final selectedVariantId = variant?.id ?? 'default';
      final initialVariantId = widget.initialVariantId ?? 'default';
      final appliesInitialControls =
          widget.initialControlValues.isNotEmpty &&
          story.id == (widget.initialStoryId ?? widget.stories.first.id) &&
          initialVariantId == selectedVariantId;
      return story.initialControlValues(
        variant: variant,
        overrides: appliesInitialControls
            ? widget.initialControlValues
            : const <String, Object?>{},
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialTheme;
    _viewport = widget.initialViewport;
    final initialId = widget.initialStoryId;
    final initialIndex = initialId == null
        ? 0
        : widget.stories.indexWhere((story) => story.id == initialId);
    _selectedIndex = initialIndex < 0 ? 0 : initialIndex;
    _selectedWidgetName = _defaultWidgetName(widget.stories[_selectedIndex]);
    final initialVariantId = widget.initialVariantId;
    if (initialVariantId != null && widget.stories.isNotEmpty) {
      final story = widget.stories[_selectedIndex];
      if (initialVariantId == 'default') {
        _variantIndexes[story.id] = 0;
      } else {
        final variantIndex = story.variants.indexWhere(
          (variant) => variant.id == initialVariantId,
        );
        if (variantIndex >= 0) _variantIndexes[story.id] = variantIndex + 1;
      }
    }
  }

  void _selectStoryIndex(int index) {
    if (index < 0 || index >= widget.stories.length) return;
    setState(() {
      _selectedIndex = index;
      _selectedWidgetName = _defaultWidgetName(widget.stories[index]);
      _addAction('story.selected', <String, Object?>{
        'storyId': widget.stories[index].id,
      });
    });
  }

  void _selectWidget(int storyIndex, String widgetName) {
    if (storyIndex < 0 || storyIndex >= widget.stories.length) return;
    final story = widget.stories[storyIndex];
    if (!story.widgets.contains(widgetName)) return;
    setState(() {
      _selectedIndex = storyIndex;
      _selectedWidgetName = widgetName;
      _addAction('widget.selected', <String, Object?>{
        'storyId': story.id,
        'widget': widgetName,
      });
    });
  }

  void _moveStory(int delta) {
    final count = widget.stories.length;
    if (count == 0) return;
    _selectStoryIndex((_selectedIndex + delta) % count);
  }

  void _moveVariant(int delta) {
    final story = _selectedStory;
    final variants = story.variants;
    if (variants.isEmpty) return;
    setState(() {
      final count = variants.length + 1;
      final current = _variantIndexes[story.id] ?? 0;
      final next = (current + delta) % count;
      final resolved = next < 0 ? next + count : next;
      _variantIndexes[story.id] = resolved;
      _resetGeneration += 1;
      _addAction('variant.selected', <String, Object?>{
        'storyId': story.id,
        'variantId': resolved == 0 ? 'default' : variants[resolved - 1].id,
      });
    });
  }

  void _cycleTheme() {
    setState(() {
      final values = StorybookThemeMode.values;
      _themeMode = values[(_themeMode.index + 1) % values.length];
      _addAction('theme.changed', <String, Object?>{'theme': _themeMode.name});
    });
  }

  void _cycleViewport() {
    setState(() {
      final values = StorybookViewportPreset.values;
      _viewport = values[(_viewport.index + 1) % values.length];
      _addAction('viewport.changed', <String, Object?>{
        'viewport': storybookViewportLabel(_viewport),
      });
    });
  }

  void _toggleInspector() {
    setState(() {
      _showInspector = !_showInspector;
      _addAction('inspector.toggled', <String, Object?>{
        'visible': _showInspector,
      });
    });
  }

  void _toggleDensity() {
    setState(() {
      _compactPreview = !_compactPreview;
      _addAction('density.toggled', <String, Object?>{
        'compact': _compactPreview,
      });
    });
  }

  void _resetStory() {
    setState(() {
      _controlValues.remove(_targetKey(_selectedStory, _selectedVariant));
      _resetGeneration += 1;
      _addAction('story.reset', <String, Object?>{
        'storyId': _selectedStory.id,
        'variantId': _selectedVariant?.id ?? 'default',
      });
    });
  }

  void _changeControl(StoryControl control, int delta) {
    if (control.options.isEmpty) return;
    final values = _selectedControlValues;
    final current = control.normalizedIndex(values[control.id]);
    final next = (current + delta) % control.options.length;
    final resolved = next < 0 ? next + control.options.length : next;
    _setControlValue(control, resolved);
  }

  void _setControlValue(StoryControl control, Object? value) {
    setState(() {
      _selectedControlValues[control.id] = value;
      _addAction('control.changed', <String, Object?>{
        'controlId': control.id,
        'value': _controlValueLabel(control, value),
      });
    });
  }

  void _recordStoryAction(String name, [Map<String, Object?> data = const {}]) {
    setState(() => _addAction(name, data));
  }

  void _addAction(String name, Map<String, Object?> data) {
    _actionSequence += 1;
    _actionLog.insert(
      0,
      StoryAction(
        sequence: _actionSequence,
        storyId: _selectedStory.id,
        name: name,
        data: Map<String, Object?>.unmodifiable(data),
      ),
    );
    if (_actionLog.length > 30) {
      _actionLog.removeRange(30, _actionLog.length);
    }
  }

  List<AppCommand> _commands() {
    return [
      AppCommand(
        id: const CommandId('storybook.palette.open'),
        title: 'Open command palette',
        category: 'Storybook',
        shortcuts: [KeyChord.ctrl.k],
        run: (context) {
          final buildContext = context.buildContext;
          if (buildContext != null) {
            return CommandPalette.open(buildContext);
          }
        },
      ),
      AppCommand(
        id: const CommandId('storybook.theme.next'),
        title: 'Cycle theme',
        description: 'Switch terminal, dark, light, and high-contrast themes.',
        category: 'Storybook',
        shortcuts: [KeyChord.ctrl.t],
        run: (_) => _cycleTheme(),
      ),
      AppCommand(
        id: const CommandId('storybook.story.previous'),
        title: 'Previous story',
        category: 'Storybook',
        shortcuts: [KeyChord.pageUp],
        run: (_) => _moveStory(-1),
      ),
      AppCommand(
        id: const CommandId('storybook.story.next'),
        title: 'Next story',
        category: 'Storybook',
        shortcuts: [KeyChord.pageDown],
        run: (_) => _moveStory(1),
      ),
      AppCommand(
        id: const CommandId('storybook.variant.previous'),
        title: 'Previous variant',
        category: 'Storybook',
        shortcuts: [KeyChord.alt.left],
        enabled: (_) => _selectedStory.variants.isNotEmpty,
        run: (_) => _moveVariant(-1),
      ),
      AppCommand(
        id: const CommandId('storybook.variant.next'),
        title: 'Next variant',
        category: 'Storybook',
        shortcuts: [KeyChord.alt.right],
        enabled: (_) => _selectedStory.variants.isNotEmpty,
        run: (_) => _moveVariant(1),
      ),
      AppCommand(
        id: const CommandId('storybook.inspector.toggle'),
        title: _showInspector ? 'Hide inspector' : 'Show inspector',
        category: 'Storybook',
        shortcuts: [KeyChord.ctrl.s],
        run: (_) => _toggleInspector(),
      ),
      AppCommand(
        id: const CommandId('storybook.preview.density'),
        title: _compactPreview ? 'Use full preview' : 'Use compact preview',
        category: 'Storybook',
        shortcuts: [KeyChord.ctrl.d],
        run: (_) => _toggleDensity(),
      ),
      AppCommand(
        id: const CommandId('storybook.viewport.next'),
        title: 'Cycle viewport preset',
        category: 'Storybook',
        shortcuts: [KeyChord.ctrl.v],
        run: (_) => _cycleViewport(),
      ),
      AppCommand(
        id: const CommandId('storybook.story.reset'),
        title: 'Reset current story',
        category: 'Storybook',
        shortcuts: [KeyChord.ctrl.r],
        run: (_) => _resetStory(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = storybookThemeFor(_themeMode);
    return Theme(
      data: theme,
      child: FleuryApp(
        title: 'Fleury Storybook',
        status: (_) => [
          StatusItem.text('Widget', value: _selectedWidgetName),
          StatusItem.text('Story', value: _selectedStory.title),
          StatusItem.text('Theme', value: storybookThemeLabel(_themeMode)),
          StatusItem.text('Viewport', value: storybookViewportLabel(_viewport)),
          StatusItem.text('Widgets', value: '${_widgetCount(widget.stories)}'),
        ],
        child: CommandScope(
          label: 'Storybook commands',
          commands: _commands(),
          child: _StorybookShell(
            stories: widget.stories,
            selectedIndex: _selectedIndex,
            selectedWidgetName: _selectedWidgetName,
            story: _selectedStory,
            variant: _selectedVariant,
            controlValues: _selectedControlValues,
            actionLog: _actionLog,
            commands: _commands(),
            themeMode: _themeMode,
            viewport: _viewport,
            compactPreview: _compactPreview,
            showInspector: _showInspector,
            resetGeneration: _resetGeneration,
            onSelectWidget: _selectWidget,
            onCycleTheme: _cycleTheme,
            onCycleViewport: _cycleViewport,
            onToggleInspector: _toggleInspector,
            onToggleDensity: _toggleDensity,
            onResetStory: _resetStory,
            onChangeControl: _changeControl,
            onSetControlValue: _setControlValue,
            onRecordAction: _recordStoryAction,
          ),
        ),
      ),
    );
  }
}

String _targetKey(Story story, StoryVariant? variant) {
  return variant == null ? story.id : '${story.id}:${variant.id}';
}

String _defaultWidgetName(Story story) {
  return story.widgets.isEmpty ? story.title : story.widgets.first;
}

int _widgetCount(List<Story> stories) {
  return stories.fold<int>(0, (count, story) => count + story.widgets.length);
}

class _StorybookShell extends StatelessWidget {
  const _StorybookShell({
    required this.stories,
    required this.selectedIndex,
    required this.selectedWidgetName,
    required this.story,
    required this.variant,
    required this.controlValues,
    required this.actionLog,
    required this.commands,
    required this.themeMode,
    required this.viewport,
    required this.compactPreview,
    required this.showInspector,
    required this.resetGeneration,
    required this.onSelectWidget,
    required this.onCycleTheme,
    required this.onCycleViewport,
    required this.onToggleInspector,
    required this.onToggleDensity,
    required this.onResetStory,
    required this.onChangeControl,
    required this.onSetControlValue,
    required this.onRecordAction,
  });

  final List<Story> stories;
  final int selectedIndex;
  final String selectedWidgetName;
  final Story story;
  final StoryVariant? variant;
  final Map<String, Object?> controlValues;
  final List<StoryAction> actionLog;
  final List<AppCommand> commands;
  final StorybookThemeMode themeMode;
  final StorybookViewportPreset viewport;
  final bool compactPreview;
  final bool showInspector;
  final int resetGeneration;
  final void Function(int storyIndex, String widgetName) onSelectWidget;
  final void Function() onCycleTheme;
  final void Function() onCycleViewport;
  final void Function() onToggleInspector;
  final void Function() onToggleDensity;
  final void Function() onResetStory;
  final void Function(StoryControl control, int delta) onChangeControl;
  final void Function(StoryControl control, Object? value) onSetControlValue;
  final StoryActionRecorder onRecordAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(1),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cols = constraints.maxCols ?? 120;
          final narrow = cols < 96;
          final showDetailsPanel = showInspector && !narrow;
          final selectorWidth = narrow ? 30 : 34;
          final detailsWidth = cols >= 118 ? 42 : 34;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                story: story,
                selectedWidgetName: selectedWidgetName,
                variant: variant,
                themeMode: themeMode,
                viewport: viewport,
                onCycleTheme: onCycleTheme,
                onCycleViewport: onCycleViewport,
                onToggleInspector: onToggleInspector,
                onToggleDensity: onToggleDensity,
                onResetStory: onResetStory,
              ),
              const SizedBox(height: 1),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: FocusTraversalGroup(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: selectorWidth,
                              child: _WidgetSelector(
                                width: selectorWidth,
                                stories: stories,
                                selectedIndex: selectedIndex,
                                selectedWidgetName: selectedWidgetName,
                                onSelect: onSelectWidget,
                              ),
                            ),
                            const SizedBox(width: 1),
                            Expanded(
                              child: _PreviewPanel(
                                key: ValueKey('${story.id}:$resetGeneration'),
                                story: story,
                                variant: variant,
                                selectedWidgetName: selectedWidgetName,
                                values: controlValues,
                                recordAction: onRecordAction,
                                viewport: viewport,
                                compact: compactPreview,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (showDetailsPanel) ...[
                      const SizedBox(width: 1),
                      SizedBox(
                        width: detailsWidth,
                        child: _DetailsPanel(
                          story: story,
                          variant: variant,
                          values: controlValues,
                          actionLog: actionLog,
                          commands: commands,
                          showInspector: showInspector,
                          selectedWidgetName: selectedWidgetName,
                          onChangeControl: onChangeControl,
                          onSetControlValue: onSetControlValue,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Text('Ctrl+K palette', style: theme.mutedStyle),
                  const Text('  '),
                  Text('Ctrl+T theme', style: theme.mutedStyle),
                  const Text('  '),
                  Text('Ctrl+S inspector', style: theme.mutedStyle),
                  const Text('  '),
                  Text('Ctrl+V viewport', style: theme.mutedStyle),
                  const Text('  '),
                  Text('Enter open widget', style: theme.mutedStyle),
                  if (!narrow) ...[
                    const Text('  '),
                    Text('PgUp/PgDn stories', style: theme.mutedStyle),
                  ],
                  const Expanded(child: SizedBox()),
                  KeyHintBar(),
                ],
              ),
              if (narrow && showInspector)
                Text(
                  'Details hidden in narrow layout. Use a wider terminal for inspector.',
                  style: theme.mutedStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.story,
    required this.selectedWidgetName,
    required this.variant,
    required this.themeMode,
    required this.viewport,
    required this.onCycleTheme,
    required this.onCycleViewport,
    required this.onToggleInspector,
    required this.onToggleDensity,
    required this.onResetStory,
  });

  final Story story;
  final String selectedWidgetName;
  final StoryVariant? variant;
  final StorybookThemeMode themeMode;
  final StorybookViewportPreset viewport;
  final void Function() onCycleTheme;
  final void Function() onCycleViewport;
  final void Function() onToggleInspector;
  final void Function() onToggleDensity;
  final void Function() onResetStory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = (constraints.maxCols ?? 120) < 96;
        return Container(
          height: 3,
          border: BoxBorder(
            style: theme.borderStyle,
            cellStyle: theme.mutedStyle,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Row(
            children: [
              Text('Fleury Storybook', style: const CellStyle(bold: true)),
              if (!compact)
                Text(' / ${story.category}', style: theme.mutedStyle),
              const Text('  '),
              Text(
                selectedWidgetName,
                style: CellStyle(foreground: theme.colorScheme.primary),
              ),
              if (!compact && story.title != selectedWidgetName)
                Text(' in ${story.title}', style: theme.mutedStyle),
              if (!compact && variant != null) ...[
                const Text('  '),
                Text('variant: ${variant!.label}', style: theme.mutedStyle),
              ],
              const Expanded(child: SizedBox()),
              if (!compact) ...[
                Button(
                  label: storybookThemeLabel(themeMode),
                  onPressed: onCycleTheme,
                ),
                const Text(' '),
                Button(
                  label: storybookViewportLabel(viewport),
                  onPressed: onCycleViewport,
                ),
                const Text(' '),
                Button(label: 'Inspector', onPressed: onToggleInspector),
                const Text(' '),
                Button(label: 'Density', onPressed: onToggleDensity),
                const Text(' '),
                Button(label: 'Reset', onPressed: onResetStory),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _WidgetSelector extends StatefulWidget {
  const _WidgetSelector({
    required this.width,
    required this.stories,
    required this.selectedIndex,
    required this.selectedWidgetName,
    required this.onSelect,
  });

  final int width;
  final List<Story> stories;
  final int selectedIndex;
  final String selectedWidgetName;
  final void Function(int storyIndex, String widgetName) onSelect;

  @override
  State<_WidgetSelector> createState() => _WidgetSelectorState();
}

class _WidgetSelectorState extends State<_WidgetSelector> {
  final TextEditingController _queryController = TextEditingController();
  final ListController _listController = ListController(selectedIndex: 0);

  List<SearchResult> _results() {
    final results = <SearchResult>[
      for (var i = 0; i < widget.stories.length; i++)
        for (final widgetName in widget.stories[i].widgets)
          SearchResult(
            id: '${widget.stories[i].id}:$widgetName',
            title: widgetName,
            category: widget.stories[i].category,
            detail:
                '${widget.stories[i].title}: ${widget.stories[i].description}',
            metadata: {
              'storyId': widget.stories[i].id,
              'storyIndex': i,
              'storyTitle': widget.stories[i].title,
              'widgetName': widgetName,
              'active':
                  i == widget.selectedIndex &&
                  widgetName == widget.selectedWidgetName,
            },
          ),
    ];
    // Browse order: group by category in a fixed foundational→specialized
    // order, alphabetical within each group. Search re-ranks by match, so this
    // only governs the no-query list — the predictable way to find a widget.
    results.sort((a, b) {
      final ca = _categoryRank(a.category);
      final cb = _categoryRank(b.category);
      if (ca != cb) return ca.compareTo(cb);
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return results;
  }

  /// Fixed semantic order for category groups; unknown categories sort last,
  /// then alphabetically among themselves.
  static int _categoryRank(String? category) {
    const order = [
      'Core',
      'Input',
      'Forms',
      'Navigation',
      'Data',
      'Content',
      'Visualization',
      'Files',
      'Output',
      'Agent',
      'Workflow',
    ];
    final i = order.indexOf(category ?? '');
    return i >= 0 ? i : order.length;
  }

  void _activateResult(SearchResult result) {
    final storyIndex = result.metadata['storyIndex'];
    final widgetName = result.metadata['widgetName'];
    if (storyIndex is int && widgetName is String) {
      widget.onSelect(storyIndex, widgetName);
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _listController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _results();
    return _Panel(
      title: 'Widgets',
      child: SearchPanel(
        results: results,
        queryController: _queryController,
        controller: _listController,
        label: 'Widget selector',
        placeholder: 'Search widgets...',
        width: (widget.width - 3).clamp(20, 31),
        fillHeight: true,
        autofocus: true,
        copySelection: false,
        onActivate: (result, _) => _activateResult(result),
      ),
      footer: Text(
        '${results.length} widgets, ${widget.stories.length} stories',
        style: theme.mutedStyle,
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    super.key,
    required this.story,
    required this.variant,
    required this.selectedWidgetName,
    required this.values,
    required this.recordAction,
    required this.viewport,
    required this.compact,
  });

  final Story story;
  final StoryVariant? variant;
  final String selectedWidgetName;
  final Map<String, Object?> values;
  final StoryActionRecorder recordAction;
  final StorybookViewportPreset viewport;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = story.builder(
      StoryBuildContext(
        story: story,
        variant: variant,
        selectedWidgetName: selectedWidgetName,
        values: values,
        recordAction: recordAction,
      ),
    );
    final viewportSize = storybookViewportSize(viewport);
    final height =
        viewportSize?.rows ??
        (compact ? story.initialHeight.clamp(8, 12) : story.initialHeight);
    final width = viewportSize?.cols;
    return _Panel(
      title: 'Preview',
      child: SizedBox(
        width: width,
        height: height,
        child: Container(
          border: BoxBorder(
            style: BorderStyle.rounded,
            cellStyle: Theme.of(context).mutedStyle,
          ),
          padding: const EdgeInsets.all(1),
          child: content,
        ),
      ),
      footer: Text('Tab or arrow into the preview to interact.'),
    );
  }
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({
    required this.story,
    required this.variant,
    required this.values,
    required this.actionLog,
    required this.commands,
    required this.showInspector,
    required this.selectedWidgetName,
    required this.onChangeControl,
    required this.onSetControlValue,
  });

  final Story story;
  final StoryVariant? variant;
  final Map<String, Object?> values;
  final List<StoryAction> actionLog;
  final List<AppCommand> commands;
  final bool showInspector;
  final String selectedWidgetName;
  final void Function(StoryControl control, int delta) onChangeControl;
  final void Function(StoryControl control, Object? value) onSetControlValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focused = Focus.maybeOf(context)?.focusedNode;
    final rows = <Widget>[
      Text(story.description),
      const SizedBox(height: 1),
      Text('Selected Widget', style: const CellStyle(bold: true)),
      Text(
        _selectedWidgetLabel(story, selectedWidgetName),
        style: theme.mutedStyle,
      ),
      if (variant != null && variant!.description.isNotEmpty) ...[
        const SizedBox(height: 1),
        Text('Variant', style: const CellStyle(bold: true)),
        Text(
          '${variant!.label}: ${variant!.description}',
          style: theme.mutedStyle,
        ),
      ],
      const SizedBox(height: 1),
      Text('Widgets', style: const CellStyle(bold: true)),
      Text(story.widgets.join(', '), style: theme.mutedStyle),
      if (story.variants.isNotEmpty) ...[
        const SizedBox(height: 1),
        Text('Variants', style: const CellStyle(bold: true)),
        Text(
          'Default, ${story.variants.map((variant) => variant.label).join(', ')}',
          style: theme.mutedStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
      if (story.controls.isNotEmpty) ...[
        const SizedBox(height: 1),
        Text('Controls', style: const CellStyle(bold: true)),
        for (final control in story.controls)
          _ControlRow(
            control: control,
            value: values[control.id],
            onPrevious: () => onChangeControl(control, -1),
            onNext: () => onChangeControl(control, 1),
            onChanged: (value) => onSetControlValue(control, value),
          ),
      ],
      const SizedBox(height: 1),
      Text('Actions', style: const CellStyle(bold: true)),
      if (actionLog.isEmpty)
        Text('No actions yet.', style: theme.mutedStyle)
      else
        for (final action in actionLog.take(6))
          Text(
            '#${action.sequence} ${action.name}${_actionDataLabel(action)}',
            style: action.storyId == story.id
                ? CellStyle.empty
                : theme.mutedStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      if (showInspector) ...[
        const SizedBox(height: 1),
        Text('Inspector', style: const CellStyle(bold: true)),
        Text('Story id: ${story.id}', style: theme.mutedStyle),
        Text(
          'Variant id: ${variant?.id ?? 'default'}',
          style: theme.mutedStyle,
        ),
        Text(
          'Focus: ${focused?.toString() ?? 'none'}',
          style: theme.mutedStyle,
        ),
        Text(
          'Controls: ${story.controls.length}  Actions: ${actionLog.length}',
          style: theme.mutedStyle,
        ),
        Text('Commands: ${commands.length}', style: theme.mutedStyle),
        for (final command in commands.take(8))
          Text(
            '${_commandShortcutLabel(command)} ${command.title}',
            style: theme.mutedStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 1),
        Text('Semantic Coverage', style: const CellStyle(bold: true)),
        for (final widgetName in story.widgets)
          Text('• $widgetName', style: theme.mutedStyle),
      ],
      if (story.notes.isNotEmpty) ...[
        const SizedBox(height: 1),
        Text('Notes', style: const CellStyle(bold: true)),
        for (final note in story.notes)
          Text('• $note', style: theme.mutedStyle),
      ],
    ];
    return _Panel(
      title: 'Details',
      child: ScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
  }
}

String _selectedWidgetLabel(Story story, String selectedWidgetName) {
  return story.title == selectedWidgetName
      ? selectedWidgetName
      : '$selectedWidgetName in ${story.title}';
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({
    required this.control,
    required this.value,
    required this.onPrevious,
    required this.onNext,
    required this.onChanged,
  });

  final StoryControl control;
  final Object? value;
  final void Function() onPrevious;
  final void Function() onNext;
  final void Function(Object? value) onChanged;

  @override
  Widget build(BuildContext context) {
    final label = Expanded(
      child: Text(control.label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    return switch (control.type) {
      StoryControlType.text => Row(
        children: [
          label,
          SizedBox(
            width: 18,
            child: _TextControlEditor(
              value: control.normalizedText(value),
              placeholder: control.placeholder,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
      StoryControlType.number => Row(
        children: [
          label,
          SizedBox(
            width: 18,
            child: Stepper(
              value: control.normalizedNumber(value),
              min: control.min,
              max: control.max,
              step: control.step ?? 1,
              label: null,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
      StoryControlType.option || StoryControlType.toggle => Row(
        children: [
          label,
          Button(label: '<', onPressed: onPrevious),
          const Text(' '),
          SizedBox(
            width: 10,
            child: Text(
              control.options.isEmpty
                  ? ''
                  : control.options[control.normalizedIndex(value)],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Text(' '),
          Button(label: '>', onPressed: onNext),
        ],
      ),
    };
  }
}

class _TextControlEditor extends StatefulWidget {
  const _TextControlEditor({
    required this.value,
    required this.placeholder,
    required this.onChanged,
  });

  final String value;
  final String placeholder;
  final void Function(String value) onChanged;

  @override
  State<_TextControlEditor> createState() => _TextControlEditorState();
}

class _TextControlEditorState extends State<_TextControlEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant _TextControlEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == _controller.text) return;
    _updating = true;
    _controller
      ..text = widget.value
      ..selection = widget.value.length;
    _updating = false;
  }

  void _onTextChanged() {
    if (_updating) return;
    widget.onChanged(_controller.text);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextInput(
      controller: _controller,
      placeholder: widget.placeholder,
      semanticLabel: widget.placeholder.isEmpty ? null : widget.placeholder,
    );
  }
}

class _Panel extends StatefulWidget {
  const _Panel({required this.title, required this.child, this.footer});

  final String title;
  final Widget child;
  final Widget? footer;

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  FocusManager? _manager;
  bool _focusedWithin = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final manager = Focus.maybeOf(context);
    if (identical(manager, _manager)) return;
    _manager?.removeListener(_onFocusChange);
    _manager = manager;
    _manager?.addListener(_onFocusChange);
    _onFocusChange();
  }

  void _onFocusChange() {
    final next = _computeFocusedWithin();
    if (next == _focusedWithin) return;
    setState(() {
      _focusedWithin = next;
    });
  }

  bool _computeFocusedWithin() {
    final focusedContext = _manager?.focusedNode?.context;
    if (focusedContext is! Element) return false;
    final panelContext = context;
    if (panelContext is! Element) return false;
    Element? element = focusedContext;
    while (element != null) {
      if (identical(element, panelContext)) return true;
      element = element.elementParent;
    }
    return false;
  }

  @override
  void dispose() {
    _manager?.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeStyle = _focusedWithin
        ? _activePanelStyle(theme)
        : theme.mutedStyle;
    return Container(
      border: BoxBorder(style: theme.borderStyle, cellStyle: activeStyle),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: _focusedWithin
                ? activeStyle.merge(const CellStyle(bold: true))
                : const CellStyle(bold: true),
          ),
          const SizedBox(height: 1),
          Expanded(child: widget.child),
          if (widget.footer != null) ...[
            const SizedBox(height: 1),
            widget.footer!,
          ],
        ],
      ),
    );
  }
}

CellStyle _activePanelStyle(ThemeData theme) {
  final focused = theme.focusedStyle;
  if (focused.foreground != null) return focused;
  return focused.merge(CellStyle(foreground: theme.colorScheme.primary));
}

String _controlValueLabel(StoryControl control, Object? value) {
  return switch (control.type) {
    StoryControlType.option || StoryControlType.toggle =>
      control.options.isEmpty
          ? ''
          : control.options[control.normalizedIndex(value)],
    StoryControlType.text => control.normalizedText(value),
    StoryControlType.number => control.normalizedNumber(value).toString(),
  };
}

String _commandShortcutLabel(AppCommand command) {
  if (command.shortcuts.isEmpty) return '      ';
  return command.shortcuts.map((shortcut) => shortcut.hintLabel).join('/');
}

String _actionDataLabel(StoryAction action) {
  if (action.data.isEmpty) return '';
  final parts = <String>[
    for (final entry in action.data.entries) '${entry.key}=${entry.value}',
  ];
  return ' (${parts.join(', ')})';
}
