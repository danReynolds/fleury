// Compile-checked source behind the Navigation guide. It keeps the first
// example deliberately small: push a screen, present a dialog, and pop with
// or without a typed result. Guarded by ../test/doc_snippets_test.dart.

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

void main() => runApp(navigationDemoApp());

Widget navigationDemoApp() =>
    const FleuryApp(title: 'Navigation', home: NavigationHome());

enum DetailsResult { done }

class NavigationHome extends StatefulWidget {
  const NavigationHome({super.key});

  @override
  State<NavigationHome> createState() => _NavigationHomeState();
}

class _NavigationHomeState extends State<NavigationHome> {
  String _result = 'none';

  Future<void> _openDetails(BuildContext context) async {
    final result = await context.push<DetailsResult>(const DetailsScreen());
    if (!mounted || result == null) return;
    setState(() => _result = result.name);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('HOME · STACK DEPTH 1', style: CellStyle(bold: true)),
        const SizedBox(height: 1),
        Button(
          label: 'Push details',
          autofocus: true,
          onPressed: () => unawaited(_openDetails(context)),
        ),
        const Spacer(),
        Text('result: $_result'),
      ],
    ),
  );
}

class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  String _dialogResult = 'not shown';

  Future<void> _presentDialog(BuildContext context) async {
    final confirmed = await context.present<bool>(const ConfirmationDialog());
    if (!mounted) return;
    setState(() => _dialogResult = confirmed == true ? 'confirmed' : 'closed');
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('DETAILS · STACK DEPTH 2', style: CellStyle(bold: true)),
        Text('dialog: $_dialogResult'),
        const SizedBox(height: 1),
        Button(
          label: 'Present dialog',
          autofocus: true,
          onPressed: () => unawaited(_presentDialog(context)),
        ),
        Button(
          label: 'Pop with result',
          onPressed: () => context.pop(DetailsResult.done),
        ),
        Button(label: 'Pop without result', onPressed: context.pop),
      ],
    ),
  );
}

class ConfirmationDialog extends StatelessWidget {
  const ConfirmationDialog({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    height: 7,
    child: Panel(
      title: 'PRESENTED DIALOG',
      focused: true,
      child: Center(
        child: Button(
          label: 'Confirm and pop',
          autofocus: true,
          onPressed: () => context.pop(true),
        ),
      ),
    ),
  );
}
