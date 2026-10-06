// Shared by the live Testing guide and its executable tests. The guide shows
// each library under testing/ whole, as a file in the reader's own lib/; the
// tests under ../test/testing/ import them the same way.
import 'dart:async';

import 'package:fleury/fleury_core.dart';

export 'testing/animated_upload.dart';
export 'testing/counter.dart';
export 'testing/draft_editor.dart';
export 'testing/editor_demo.dart';
export 'testing/preferences.dart';
export 'testing/save_demo.dart';
export 'testing/save_status.dart';

/// An async control whose semantic handler returns the operation's Future.
class PublishControl extends StatefulWidget {
  const PublishControl({super.key, required this.publish, this.onStarted});
  final Future<void> Function() publish;
  final VoidCallback? onStarted;

  @override
  State<PublishControl> createState() => _PublishControlState();
}

class _PublishControlState extends State<PublishControl> {
  bool busy = false;
  String status = 'Ready';

  Future<void> publish() async {
    if (busy) return;
    setState(() {
      busy = true;
      status = 'Publishing…';
    });
    widget.onStarted?.call();
    try {
      await widget.publish();
      if (mounted) setState(() => status = 'Published');
    } catch (_) {
      if (mounted) setState(() => status = 'Publish failed');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    role: SemanticRole.button,
    label: 'Publish',
    value: status,
    enabled: !busy,
    busy: busy,
    includeChildren: false,
    actions: {if (!busy) SemanticAction.activate},
    onAction: (_) => publish(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Button(
          text: 'Publish',
          onPressed: busy ? null : () => unawaited(publish()),
        ),
        const SizedBox(height: 1),
        Text(status),
      ],
    ),
  );
}

class TestingPublishDemo extends StatelessWidget {
  const TestingPublishDemo({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: PublishControl(
      publish: () => Future<void>.delayed(const Duration(milliseconds: 800)),
    ),
  );
}
