import 'package:fleury/fleury_core.dart';

/// Declared (non-core) roles standing in for a widget package's vocabulary.
///
/// Core tests cannot import `fleury_widgets`, and the point of these is not the
/// catalog anyway: the wire, the snapshot, and the debug surfaces must carry a
/// declared role by name and project it through its core role.
const SemanticRole declaredMessageList = SemanticRole(
  'messageList',
  base: SemanticRole.list,
);
const SemanticRole declaredMessage = SemanticRole(
  'message',
  base: SemanticRole.listItem,
);
const SemanticRole declaredTraceEvent = SemanticRole(
  'traceEvent',
  base: SemanticRole.listItem,
);
