// Shared reactive test helpers — one home for the _Flag/_Listen plumbing that
// several widget tests were each re-implementing (and that duplicated the
// exported ListenableBuilder). Prefer ListenableBuilder in new tests; these
// exist for the cases that need an explicit State (didUpdateWidget, dispose).

import 'package:fleury/fleury.dart';

/// A boolean you can flip to drive a rebuild in a listener.
class Flag extends ChangeNotifier {
  bool value = false;
  void set(bool v) {
    value = v;
    notifyListeners();
  }

  void enable() => set(true);
}

/// Rebuilds `builder(flag.value)` whenever [flag] fires — an external-
/// dependency leaf rebuild (the pattern an InheritedNotifier dependent has).
class Reactive extends StatefulWidget {
  const Reactive({super.key, required this.flag, required this.builder});
  final Flag flag;
  final Widget Function(bool on) builder;
  @override
  State<Reactive> createState() => _ReactiveState();
}

class _ReactiveState extends State<Reactive> {
  @override
  void initState() {
    super.initState();
    widget.flag.addListener(_changed);
  }

  @override
  void didUpdateWidget(Reactive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.flag, widget.flag)) {
      oldWidget.flag.removeListener(_changed);
      widget.flag.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.flag.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(widget.flag.value);
}
