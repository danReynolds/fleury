// Ephemeral demo (not shipped): one small "deploy console" in which every
// layering mechanism appears doing the job it is best at.
//
//   Stack+Positioned  — a LIVE badge layered over OUR OWN panel
//   Overlay+Follower  — a flyout anchored to the status chip, over everything
//   Popup             — the flyout's skin: opaque, framed, chrome
//   Navigator.present — the deploy confirmation: modal, awaited, contained
//   Toaster (stock)   — rung 1 of the ladder: don't hand-roll what exists
//
// Keys: i = info flyout · w = widen header (watch the flyout track) ·
//       d = deploy (modal dialog) · Ctrl+C quits.

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

Future<void> main() => runApp(
  FleuryApp(
    title: 'Layering demo',
    home: const Toaster(child: DeployConsole()),
  ),
  mode: const TerminalMode(mouse: true),
);

class DeployConsole extends StatefulWidget {
  const DeployConsole({super.key});

  @override
  State<DeployConsole> createState() => _DeployConsoleState();
}

class _DeployConsoleState extends State<DeployConsole> {
  final BoundsNotifier _chipBounds = BoundsNotifier();
  final List<String> _log = <String>['boot: console ready'];
  Timer? _tick;
  int _n = 0;
  bool _wide = false;
  OverlayEntry? _flyout;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 900), (_) {
      setState(() {
        _n++;
        _log.add('health: check #$_n ok (latency ${18 + _n % 7}ms)');
        if (_log.length > 10) _log.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _flyout?.remove();
    super.dispose();
  }

  // ── Overlay + Follower + Popup: a custom non-modal float ────────────────
  void _toggleFlyout() {
    final existing = _flyout;
    if (existing != null) {
      existing.remove();
      setState(() => _flyout = null);
      return;
    }
    final entry = OverlayEntry(
      builder: (context) => BoundsAnchor(
        notifier: _chipBounds, // pinned to the chip, wherever layout puts it
        child: Surface(
          // opaque, or the log bleeds through
          child: Container(
            border: BoxBorder(style: Theme.of(context).borderStyle),
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const <Widget>[
                Text('build   2214 (main @ 27983d1)'),
                Text('host    prod-eu-3'),
                Text('uptime  41 days'),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(entry);
    setState(() => _flyout = entry);
  }

  // ── Navigator.present + Dialog: a modal, awaited decision ───────────────
  Future<void> _deploy() async {
    final ok = await context.present<bool>(
      Dialog(
        title: 'Deploy to production?',
        width: 40,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Ship build 2214 to prod-eu-3.'),
            const Text(
              'error: last deploy exited 517', // selectable content
              style: CellStyle(dim: true),
            ),
            const SizedBox(height: 1),
            Row(
              children: <Widget>[
                Button(label: 'Cancel', onPressed: () => context.pop(false)),
                const SizedBox(width: 2),
                Button(
                  label: 'Deploy',
                  variant: ButtonVariant.primary,
                  autofocus: true,
                  onPressed: () => context.pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (ok ?? false) {
      setState(() => _log.add('deploy: build 2214 -> prod-eu-3 STARTED'));
      Toaster.show(context, 'Deploy started', severity: ToastSeverity.success);
    } else {
      Toaster.show(context, 'Deploy cancelled');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyBindings(
      bindings: <KeyBinding>[
        KeyBinding(
          KeySequence.i,
          label: 'Info flyout',
          onTrigger: _toggleFlyout,
        ),
        KeyBinding(KeySequence.d, label: 'Deploy', onTrigger: _deploy),
        KeyBinding(
          KeySequence.w,
          label: 'Widen header',
          onTrigger: () => setState(() => _wide = !_wide),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Header: the chip is an Anchor — the flyout pins to it.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Row(
              children: <Widget>[
                Text(
                  _wide ? 'deploy console — europe-west cluster ' : 'deploy ',
                  style: CellStyle(foreground: theme.colorScheme.primary),
                ),
                BoundsObserver(notifier: _chipBounds, child: const Text('[ status: OK ]')),
              ],
            ),
          ),
          // ── Stack + Positioned: OUR OWN badge over OUR OWN panel ────────
          Expanded(
            child: Stack(
              children: <Widget>[
                Panel(
                  title: 'deploy log',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[for (final line in _log) Text(line)],
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 14,
                  child: Text(
                    ' ● LIVE ',
                    style: CellStyle(foreground: theme.colorScheme.success),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: theme.colorScheme.foreground,
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: KeyHintBar(
              style: CellStyle(foreground: theme.colorScheme.background),
            ),
          ),
        ],
      ),
    );
  }
}
