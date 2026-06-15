import 'package:fleury/fleury.dart';

enum StoryControlType { option, toggle, text, number }

final class StoryControl {
  const StoryControl.option({
    required this.id,
    required this.label,
    required this.options,
    this.initialIndex = 0,
  }) : type = StoryControlType.option,
       initialValue = initialIndex,
       placeholder = '',
       min = null,
       max = null,
       step = null;

  const StoryControl.toggle({
    required this.id,
    required this.label,
    bool initialValue = false,
  }) : type = StoryControlType.toggle,
       options = const ['Off', 'On'],
       initialIndex = initialValue ? 1 : 0,
       initialValue = initialValue ? 1 : 0,
       placeholder = '',
       min = null,
       max = null,
       step = null;

  const StoryControl.text({
    required this.id,
    required this.label,
    String initialText = '',
    this.placeholder = '',
  }) : type = StoryControlType.text,
       options = const <String>[],
       initialIndex = 0,
       initialValue = initialText,
       min = null,
       max = null,
       step = null;

  const StoryControl.number({
    required this.id,
    required this.label,
    num initialNumber = 0,
    this.min,
    this.max,
    this.step = 1,
  }) : type = StoryControlType.number,
       options = const <String>[],
       initialIndex = 0,
       initialValue = initialNumber,
       placeholder = '';

  final String id;
  final String label;
  final StoryControlType type;
  final List<String> options;
  final int initialIndex;
  final Object initialValue;
  final String placeholder;
  final num? min;
  final num? max;
  final num? step;

  int normalizedIndex(Object? value) {
    if (options.isEmpty) return 0;
    final index = switch (value) {
      int value => value,
      num value => value.toInt(),
      _ => initialIndex,
    };
    return index.clamp(0, options.length - 1);
  }

  String normalizedText(Object? value) {
    return switch (value) {
      String value => value,
      null => initialValue.toString(),
      _ => value.toString(),
    };
  }

  num normalizedNumber(Object? value) {
    final raw = switch (value) {
      num value => value,
      String value => num.tryParse(value) ?? initialValue,
      _ => initialValue,
    };
    var resolved = raw is num ? raw : 0;
    final lower = min;
    final upper = max;
    if (lower != null && resolved < lower) resolved = lower;
    if (upper != null && resolved > upper) resolved = upper;
    return resolved;
  }
}

typedef StoryWidgetBuilder = Widget Function(StoryBuildContext context);
typedef StoryActionRecorder =
    void Function(String name, [Map<String, Object?> data]);

final class StoryAction {
  const StoryAction({
    required this.sequence,
    required this.storyId,
    required this.name,
    required this.data,
  });

  final int sequence;
  final String storyId;
  final String name;
  final Map<String, Object?> data;
}

final class StoryVariant {
  const StoryVariant({
    required this.id,
    required this.label,
    this.description = '',
    this.controlValues = const <String, Object?>{},
  });

  final String id;
  final String label;
  final String description;
  final Map<String, Object?> controlValues;
}

final class Story {
  const Story({
    required this.id,
    required this.title,
    required this.category,
    required this.description,
    required this.widgets,
    required this.builder,
    this.controls = const <StoryControl>[],
    this.defaultControlValues = const <String, Object?>{},
    this.variants = const <StoryVariant>[],
    this.notes = const <String>[],
    this.usage,
    this.initialHeight = 18,
  });

  final String id;
  final String title;
  final String category;
  final String description;
  final List<String> widgets;
  final StoryWidgetBuilder builder;
  final List<StoryControl> controls;
  final Map<String, Object?> defaultControlValues;
  final List<StoryVariant> variants;
  final List<String> notes;

  /// A one-line interaction tip for the previewed widget — e.g.
  /// `↑/↓ to step · PgUp/PgDn ±10`. Surfaced in the preview footer so the
  /// keyboard model is discoverable without reading source.
  final String? usage;

  final int initialHeight;

  Map<String, Object?> initialControlValues({
    StoryVariant? variant,
    Map<String, Object?> overrides = const <String, Object?>{},
  }) {
    return <String, Object?>{
      for (final control in controls) control.id: control.initialValue,
      ...defaultControlValues,
      if (variant != null) ...variant.controlValues,
      ...overrides,
    };
  }
}

final class StoryBuildContext {
  const StoryBuildContext({
    required this.story,
    required Map<String, Object?> values,
    this.variant,
    this.selectedWidgetName,
    StoryActionRecorder? recordAction,
  }) : _values = values,
       _recordAction = recordAction;

  final Story story;
  final StoryVariant? variant;
  final String? selectedWidgetName;
  final Map<String, Object?> _values;
  final StoryActionRecorder? _recordAction;

  int indexOf(String id) {
    final control = story.controls.where((control) => control.id == id).first;
    return control.normalizedIndex(_values[id]);
  }

  String option(String id) {
    final control = story.controls.where((control) => control.id == id).first;
    return control.options[indexOf(id)];
  }

  bool enabled(String id) => indexOf(id) == 1;

  String text(String id) {
    final control = story.controls.where((control) => control.id == id).first;
    return control.normalizedText(_values[id]);
  }

  num number(String id) {
    final control = story.controls.where((control) => control.id == id).first;
    return control.normalizedNumber(_values[id]);
  }

  void action(String name, [Map<String, Object?> data = const {}]) {
    _recordAction?.call(name, data);
  }
}
