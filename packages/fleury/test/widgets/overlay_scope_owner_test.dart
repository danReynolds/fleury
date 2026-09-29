import 'package:fleury/fleury.dart';
import 'package:test/test.dart';
import '../support/harness.dart';

class _Model extends Notifier {
  _Model(this.value);
  String value;
  bool released = false;
  void refresh() => notify();
  @override
  void dispose() {
    released = true;
    super.dispose();
  }
}

class _Host extends StatefulWidget {
  const _Host({super.key});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  OverlayEntry? entry;
  void show(Widget child) {
    entry = OverlayEntry(owner: context, builder: (_) => child);
    Overlay.of(context).insert(entry!);
  }

  @override
  Widget build(BuildContext context) => const Text('owner');
}

class _Read extends StatefulWidget {
  const _Read(this.reads, this.disposals);
  final List<String> reads;
  final List<bool> disposals;
  @override
  State<_Read> createState() => _ReadState();
}

class _ReadState extends State<_Read> {
  late _Model model;
  @override
  Widget build(BuildContext context) {
    model = context.scope<_Model>();
    widget.reads.add(model.value);
    return Text(model.value);
  }

  @override
  void dispose() {
    widget.disposals.add(model.released);
    super.dispose();
  }
}

void main() {
  testWidgets(
    'foreign and unmounted owners are rejected before entry attachment',
    (tester) {
      final key = GlobalKey<_HostState>();
      tester.pumpWidget(_Host(key: key));
      final overlay = Overlay.of(key.currentState!.context);
      final owner = BuildOwner();
      final foreign = owner.mountRoot(const Text('foreign'));
      final entry = OverlayEntry(
        owner: foreign,
        builder: (_) => const Text('float'),
      );
      expect(() => overlay.insert(entry), throwsStateError);
      foreign.unmount();
      expect(() => overlay.insert(entry), throwsStateError);
      entry.dispose();
      // Failed validation must not poison this host's entry list.
      key.currentState!.show(const Text('valid'));
      tester.pump();
      expect(tester.renderToString(), contains('valid'));
    },
  );

  testWidgets('an owned overlay follows live scopes and a GlobalKey move', (
    tester,
  ) {
    final hostKey = GlobalKey<_HostState>();
    final a = _Model('a');
    final b = _Model('b');
    final host = _Host(key: hostKey);
    var right = false;
    Widget body() => Row(
      children: [
        Scope(a, child: right ? const Text('left') : host),
        Scope(b, child: right ? host : const Text('right')),
      ],
    );
    tester.pumpWidget(body());
    final reads = <String>[];
    final disposals = <bool>[];
    hostKey.currentState!.show(_Read(reads, disposals));
    tester.pump();
    expect(reads.last, 'a');
    a.value = 'updated';
    a.refresh();
    tester.pump();
    expect(reads.last, 'updated');
    right = true;
    tester.pumpWidget(body());
    tester.pump();
    expect(reads.last, 'b');
    expect(
      disposals,
      isEmpty,
      reason: 'moving the owner preserves floating state',
    );
    reads.clear();
    a.refresh();
    tester.pump();
    expect(reads, isEmpty, reason: 'old scope dependency was detached');
    b.value = 'new';
    b.refresh();
    tester.pump();
    expect(reads.last, 'new');
    tester.pumpWidget(const Text('gone'));
    tester.pump();
    expect(disposals, [false]);
  });

  testWidgets('floating descendants dispose before an owned model', (tester) {
    final key = GlobalKey<_HostState>();
    final model = _Model('owned');
    tester.pumpWidget(
      Scope<_Model>.create(() => model, child: _Host(key: key)),
    );
    final disposals = <bool>[];
    final entry = key.currentState!..show(_Read([], disposals));
    tester.pump();
    tester.pumpWidget(const Text('removed'));
    tester.pump();
    expect(disposals, [false]);
    expect(model.released, isTrue);
    expect(entry.entry, isNotNull);
  });
}
