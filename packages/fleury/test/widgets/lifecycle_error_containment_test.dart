// A child that throws while it mounts or updates is contained like a thrown
// build(): the nearest building ancestor reports the error once and puts the
// error panel in that child's place, and the session keeps rendering.
//
// These throws used to escape every per-element catch. The frame driver's
// backstop replaced the whole screen, siblings the aborted reconcile had
// already released vanished for good, and a parent that rebuilt every frame
// (an animation, a stream) tripped the backstop storm and tore the session
// down.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/render_fixtures.dart';

class _ThrowsInInit extends StatefulWidget {
  const _ThrowsInInit();

  @override
  State<_ThrowsInInit> createState() => _ThrowsInInitState();
}

class _ThrowsInInitState extends State<_ThrowsInInit> {
  @override
  void initState() {
    super.initState();
    throw StateError('init-boom');
  }

  @override
  Widget build(BuildContext context) => const Text('never built');
}

class _ThrowsOnUpdate extends StatefulWidget {
  const _ThrowsOnUpdate({required this.label});

  final String label;

  @override
  State<_ThrowsOnUpdate> createState() => _ThrowsOnUpdateState();
}

class _ThrowsOnUpdateState extends State<_ThrowsOnUpdate> {
  @override
  void didUpdateWidget(_ThrowsOnUpdate oldWidget) {
    super.didUpdateWidget(oldWidget);
    throw StateError('update-boom');
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

class _DisposeProbe extends StatefulWidget {
  const _DisposeProbe({required this.log});

  final List<String> log;

  @override
  State<_DisposeProbe> createState() => _DisposeProbeState();
}

class _DisposeProbeState extends State<_DisposeProbe> {
  @override
  void dispose() {
    widget.log.add('disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('probe');
}

class _Host extends StatefulWidget {
  const _Host({super.key});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  Widget? _middle;
  var _frame = 0;

  void show(Widget? middle) => setState(() => _middle = middle);

  void tick() => setState(() => _frame++);

  @override
  Widget build(BuildContext context) => Column(
    children: [Text('header $_frame'), ?_middle, const Text('footer')],
  );
}

class _Wrap extends StatelessWidget {
  const _Wrap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _Frames implements FramePresenter {
  final frames = <String>[];

  @override
  bool get wantsPresentationPlan => false;

  @override
  void presentFrame(TuiRenderedFrame frame, FramePresentInfo info) {
    final size = frame.next.size;
    frames.add(
      frame.next.textInRange(CellRect.fromLTWH(0, 0, size.cols, size.rows)),
    );
  }

  @override
  void onFrameCommitted(TuiRenderedFrame frame, FramePresentInfo info) {}

  @override
  FrameDiffStats? frameDiffStats(
    TuiRenderedFrame frame,
    FramePresentInfo info,
  ) => null;
}

String _text(CellBuffer buffer) => buffer.textInRange(
  CellRect.fromLTWH(0, 0, buffer.size.cols, buffer.size.rows),
);

void main() {
  late TuiRuntime runtime;
  late List<Object> reported;
  final host = GlobalKey<_HostState>();

  String render() {
    final buffer = CellBuffer(const CellSize(40, 8));
    runtime.renderFrame(buffer);
    return _text(buffer);
  }

  setUp(() {
    runtime = TuiRuntime();
    reported = <Object>[];
    runtime.owner.onBuildError = (error, _) => reported.add(error);
    runtime.mountRoot(
      Column(
        children: [
          const Text('outside'),
          _Host(key: host),
        ],
      ),
    );
  });

  tearDown(() => runtime.dispose());

  test('a child whose initState throws becomes an error panel in place', () {
    render();
    host.currentState!.show(const _ThrowsInInit());

    final out = render();

    expect(out, contains('init-boom'), reason: 'the panel shows the error');
    expect(out, contains('outside'), reason: 'the rest of the app survives');
    expect(reported, [isA<StateError>()], reason: 'reported exactly once');
  });

  test('the panel gives way to real content once the child is fixed', () {
    render();
    host.currentState!.show(const _ThrowsInInit());
    render();

    host.currentState!.show(null);
    final out = render();

    expect(out, isNot(contains('init-boom')));
    expect(out, contains('header'));
    expect(out, contains('footer'));
  });

  test('a child whose didUpdateWidget throws becomes an error panel', () {
    host.currentState!.show(const _ThrowsOnUpdate(label: 'first'));
    expect(render(), contains('first'));

    host.currentState!.show(const _ThrowsOnUpdate(label: 'second'));
    final out = render();

    expect(out, contains('update-boom'));
    expect(out, contains('outside'));
    expect(reported, [isA<StateError>()]);
  });

  test('a parent rebuilding every frame keeps rendering the panel', () {
    render();
    host.currentState!.show(const _ThrowsInInit());
    for (var frame = 0; frame < 12; frame++) {
      host.currentState!.tick();
      expect(render(), contains('init-boom'), reason: 'frame $frame');
    }
    expect(reported, hasLength(12));
  });

  test('a LayoutBuilder whose builder throws shows the panel in its slot', () {
    runtime.updateRoot(
      Column(
        children: [
          const Text('above'),
          SizedBox(
            height: 3,
            child: LayoutBuilder(
              builder: (_, _) => throw StateError('layout-builder-boom'),
            ),
          ),
          const Text('below'),
        ],
      ),
    );

    final out = render();

    expect(out, contains('above'));
    expect(out, contains('layout-builder-boom'));
    expect(out, contains('below'));
  });

  test('a frame whose layout throws still disposes what its build removed', () {
    // Finalizing waits for layout, because layout builds too. A layout that
    // throws must not leave removed State (and its timers) alive for as long
    // as frames keep failing.
    final log = <String>[];
    host.currentState!.show(_DisposeProbe(log: log));
    render();

    host.currentState!.show(const Boom());
    expect(render, throwsA(isA<StateError>()));
    expect(log, ['disposed']);
  });

  test('a raw BuildOwner still propagates a child initState throw', () {
    final owner = BuildOwner();
    expect(
      () => owner.mountRoot(
        const _Wrap(child: Column(children: [_ThrowsInInit()])),
      ),
      throwsA(isA<StateError>()),
      reason: 'no errorBuilder means no boundary',
    );
  });

  test('a resize whose root rebuild throws fails that frame and is retried '
      'until the rebuild succeeds', () {
    final resizeRuntime = TuiRuntime();
    var size = const CellSize(30, 4);
    var broken = true;
    final backstopped = <Object>[];
    final presenter = _Frames();
    final driver = FrameDriver(
      runtime: resizeRuntime,
      frameLoop: TuiFrameLoop(renderDamage: resizeRuntime.renderDamageTracker),
      readViewport: () => FrameViewportSnapshot(size),
      presenter: presenter,
      onBackstopError: (error, _) => backstopped.add(error),
    );
    addTearDown(driver.dispose);
    // A render-object root: no building ancestor to contain the child's
    // didUpdateWidget, so the throw reaches the driver.
    driver.mountRoot(
      () => Column(
        children: [
          if (broken)
            _ThrowsOnUpdate(label: 'cols ${size.cols}')
          else
            Text('cols ${size.cols}'),
        ],
      ),
    );
    driver.renderNow('first');

    size = const CellSize(32, 4);
    expect(() => driver.renderNow('resized'), returnsNormally);
    expect(backstopped, [isA<StateError>()]);
    expect(presenter.frames.last, contains('update-boom'));

    // Still broken: the next frame retries the rebuild instead of laying
    // out the old MediaQuery in the new buffer.
    driver.renderNow('retry');
    expect(backstopped, hasLength(2));

    broken = false;
    driver.renderNow('fixed');
    expect(backstopped, hasLength(2));
    expect(presenter.frames.last, contains('cols 32'));

    driver.renderNow('idle');
    expect(backstopped, hasLength(2), reason: 'the resize is settled');
  });
}
