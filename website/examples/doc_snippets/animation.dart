// Compile-checked source for the Animation guide.

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

void main() => runApp(
  const FleuryApp(title: 'Animation', home: AnimationGuideDemo()),
  mode: const TerminalMode(mouse: true),
);

class AnimationGuideDemo extends StatelessWidget {
  const AnimationGuideDemo({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    children: <Widget>[
      MissionLaunch(),
      ManualRoute(),
      ProgressDemo(),
      TimingComparison(),
      ConnectionEntrance(),
      ValidationFeedback(),
      EffectPicker(),
      PacketRoute(),
      PacketTransferFrames(),
      TickerSimulation(),
    ],
  );
}

class MissionLaunch extends StatefulWidget {
  const MissionLaunch({super.key});

  @override
  State<MissionLaunch> createState() => _MissionLaunchState();
}

class _MissionLaunchState extends State<MissionLaunch> {
  static const idle = RgbColor(115, 125, 140);
  static const arrived = RgbColor(70, 220, 145);

  late final Animation<double> progress = Animation<double>(
    0.0,
    debugLabel: 'orbital courier progress',
  );
  var launched = false;

  void toggleMission() {
    if (launched) {
      setState(() => launched = false);
      progress.to(
        0.0,
        curve: Curves.easeInOut,
        duration: const Duration(milliseconds: 1400),
      );
      return;
    }

    setState(() => launched = true);
    launch();
  }

  Future<void> launch() async {
    try {
      await progress
          .to(
            0.12,
            curve: Curves.easeOut,
            duration: const Duration(milliseconds: 700),
          )
          .delay(const Duration(milliseconds: 450))
          .to(
            0.58,
            curve: Curves.easeInOut,
            duration: const Duration(milliseconds: 1600),
          )
          .delay(const Duration(milliseconds: 400))
          .to(
            1.0,
            curve: Curves.easeOut,
            duration: const Duration(milliseconds: 1800),
          )
          .orCancel;
    } on TickerCanceled {
      // Reset or a newer launch replaced this flight.
    }
  }

  String statusFor(double value) {
    if (!launched && value > 0.02) return 'RETURN · Recalling courier';
    if (value > 0.98) return '4/4 DELIVERY · Payload secured';
    if (value > 0.60) return '3/4 TRANSFER · Matching orbital speed';
    if (value > 0.13) return '2/4 ASCENT · Clearing the atmosphere';
    if (value > 0.01) return '1/4 IGNITION · Engines nominal';
    return 'READY · Awaiting flight plan';
  }

  @override
  void dispose() {
    progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = progress.value.clamp(0.0, 1.0);
    final position = (visual * 30).round();
    final filled = (visual * 30).round();
    final accent = rgbColorLerp(idle, arrived, visual);
    final route =
        '${List<String>.filled(position, '·').join()}◆'
        '${List<String>.filled(30 - position, '·').join()}';
    final gauge =
        '${List<String>.filled(filled, '█').join()}'
        '${List<String>.filled(30 - filled, '░').join()}';

    return Column(
      children: <Widget>[
        Button(
          label: launched ? 'Reset mission' : 'Launch',
          onPressed: toggleMission,
        ),
        Container(
          width: 52,
          height: 7,
          border: BoxBorder(cellStyle: CellStyle(foreground: accent)),
          child: Column(
            children: <Widget>[
              Text('EARTH $route ORBIT', style: CellStyle(foreground: accent)),
              Text('$gauge ${(visual * 100).round()}%'),
              Text(statusFor(visual), style: CellStyle(foreground: accent)),
            ],
          ),
        ),
      ],
    );
  }
}

class ManualRoute extends StatefulWidget {
  const ManualRoute({super.key});

  @override
  State<ManualRoute> createState() => _ManualRouteState();
}

class _ManualRouteState extends State<ManualRoute> {
  final progress = Animation<double>(0.0, debugLabel: 'manual package route');
  var running = false;

  Future<void> runRoute() async {
    setState(() => running = true);
    try {
      await progress
          .to(
            1.0,
            curve: Curves.easeInOut,
            duration: const Duration(milliseconds: 700),
          )
          .delay(const Duration(milliseconds: 600))
          .to(
            0.0,
            curve: Curves.easeInOut,
            duration: const Duration(milliseconds: 700),
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (mounted) setState(() => running = false);
  }

  void returnNow() {
    setState(() => running = false);
    progress.to(
      0.0,
      curve: Curves.easeOut,
      duration: const Duration(milliseconds: 450),
    );
  }

  @override
  void dispose() {
    progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = progress.value;
    final position = (value * 24).round();
    return Column(
      children: <Widget>[
        Button(
          label: running ? 'Return now' : 'Run route',
          onPressed: running ? returnNow : runRoute,
        ),
        Text('Package position: $position · progress.value is a double'),
      ],
    );
  }
}

class ProgressDemo extends StatefulWidget {
  const ProgressDemo({super.key});

  @override
  State<ProgressDemo> createState() => _ProgressDemoState();
}

class _ProgressDemoState extends State<ProgressDemo> {
  var delivered = false;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Button(
        label: delivered ? 'Return to depot' : 'Send to station',
        onPressed: () => setState(() => delivered = !delivered),
      ),
      AnimationBuilder<double>(
        delivered ? 1.0 : 0.0,
        curve: Curves.easeInOut,
        duration: const Duration(milliseconds: 1100),
        builder: (context, double progress, _) {
          final position = (progress * 24).round();
          return Column(
            children: <Widget>[
              Text('Package position: $position · progress is a double'),
              Container(
                height: 1,
                child: progress > 0.995
                    ? const Text('✦ PACKAGE DELIVERED ✦')
                          .animate(duration: const Duration(milliseconds: 650))
                          .flash(color: const RgbColor(120, 255, 190))
                          .slideIn(from: Edge.bottom)
                    : const Text(''),
              ),
            ],
          );
        },
      ),
    ],
  );
}

class TimingComparison extends StatefulWidget {
  const TimingComparison({super.key});

  @override
  State<TimingComparison> createState() => _TimingComparisonState();
}

Widget sharedTimingStatus(bool active) {
  const inactive = RgbColor(110, 120, 135);
  const activeColor = RgbColor(70, 220, 145);

  return AnimationBuilder<double>(
    active ? 1.0 : 0.0,
    curve: Curves.easeOut,
    duration: const Duration(milliseconds: 800),
    builder: (context, double progress, _) {
      final width = 22 + (20 * progress).round();
      final accent = rgbColorLerp(inactive, activeColor, progress);
      return Container(
        width: width,
        height: 3,
        border: BoxBorder(cellStyle: CellStyle(foreground: accent)),
        child: Text('TOGETHER ${(progress * 100).round()}%'),
      );
    },
  );
}

Widget independentTimingStatus(bool active) {
  const inactive = RgbColor(110, 120, 135);
  const activeColor = RgbColor(70, 220, 145);

  return AnimationBuilder<int>(
    active ? 42 : 22,
    curve: Curves.easeOut,
    duration: const Duration(milliseconds: 180),
    builder: (context, width, _) => AnimationBuilder<double>(
      active ? 1.0 : 0.0,
      curve: Curves.easeOut,
      duration: const Duration(milliseconds: 800),
      builder: (context, double colorProgress, _) => Container(
        width: width,
        height: 3,
        border: BoxBorder(
          cellStyle: CellStyle(
            foreground: rgbColorLerp(inactive, activeColor, colorProgress),
          ),
        ),
        child: Text('ACCENT ${(colorProgress * 100).round()}%'),
      ),
    ),
  );
}

class _TimingComparisonState extends State<TimingComparison> {
  var active = false;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Button(
        label: active ? 'Reset' : 'Animate',
        onPressed: () => setState(() => active = !active),
      ),
      sharedTimingStatus(active),
      independentTimingStatus(active),
    ],
  );
}

class ConnectionEntrance extends StatefulWidget {
  const ConnectionEntrance({super.key});

  @override
  State<ConnectionEntrance> createState() => _ConnectionEntranceState();
}

class _ConnectionEntranceState extends State<ConnectionEntrance> {
  var connected = false;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Button(
        label: connected ? 'Disconnect' : 'Connect',
        onPressed: () => setState(() => connected = !connected),
      ),
      if (connected)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: const Text('● Connected to relay')
              .animate(
                duration: const Duration(milliseconds: 600),
                curve: Curves.linear,
              )
              .fadeIn()
              .slideIn(from: Edge.left),
        )
      else
        const Text('○ Offline'),
    ],
  );
}

enum EntryEffect { fade, slide, wipe, expand }

enum ExitEffect { fade, slide, wipe, shrink }

Effect entryEffect(EntryEffect effect) => switch (effect) {
  EntryEffect.fade => Effects.fadeIn(),
  EntryEffect.slide => Effects.slideIn(from: Edge.left),
  EntryEffect.wipe => Effects.wipeIn(from: Edge.left),
  EntryEffect.expand => Effects.expand(),
};

Effect exitEffect(ExitEffect effect) => switch (effect) {
  ExitEffect.fade => Effects.fadeOut(),
  ExitEffect.slide => Effects.slideOut(to: Edge.right),
  ExitEffect.wipe => Effects.wipeOut(to: Edge.right),
  ExitEffect.shrink => Effects.shrink(),
};

Duration entryDuration(EntryEffect effect) => switch (effect) {
  EntryEffect.fade => const Duration(milliseconds: 400),
  EntryEffect.slide || EntryEffect.wipe => const Duration(milliseconds: 800),
  EntryEffect.expand => const Duration(milliseconds: 300),
};

Duration exitDuration(ExitEffect effect) => switch (effect) {
  ExitEffect.fade => const Duration(milliseconds: 400),
  ExitEffect.slide || ExitEffect.wipe => const Duration(milliseconds: 800),
  ExitEffect.shrink => const Duration(milliseconds: 300),
};

class EffectPicker extends StatefulWidget {
  const EffectPicker({super.key});

  @override
  State<EffectPicker> createState() => _EffectPickerState();
}

class _EffectPickerState extends State<EffectPicker> {
  var entry = EntryEffect.fade;
  var exit = ExitEffect.fade;
  var visible = true;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Select<EntryEffect>(
        semanticLabel: 'Entrance effect',
        value: entry,
        options: const <SelectOption<EntryEffect>>[
          SelectOption(value: EntryEffect.fade, label: 'Fade in'),
          SelectOption(value: EntryEffect.slide, label: 'Slide in'),
          SelectOption(value: EntryEffect.wipe, label: 'Wipe in'),
          SelectOption(value: EntryEffect.expand, label: 'Expand'),
        ],
        onChanged: (value) => setState(() => entry = value),
      ),
      Select<ExitEffect>(
        semanticLabel: 'Exit effect',
        value: exit,
        options: const <SelectOption<ExitEffect>>[
          SelectOption(value: ExitEffect.fade, label: 'Fade out'),
          SelectOption(value: ExitEffect.slide, label: 'Slide out'),
          SelectOption(value: ExitEffect.wipe, label: 'Wipe out'),
          SelectOption(value: ExitEffect.shrink, label: 'Shrink'),
        ],
        onChanged: (value) => setState(() => exit = value),
      ),
      Button(
        label: visible ? 'Hide sample' : 'Show sample',
        onPressed: () => setState(() => visible = !visible),
      ),
      AnimatedVisibility(
        visible: visible,
        enter: entryEffect(entry),
        exit: exitEffect(exit),
        duration: visible ? entryDuration(entry) : exitDuration(exit),
        curve: Curves.linear,
        child: const BuildPreview(),
      ),
    ],
  );
}

class BuildPreview extends StatelessWidget {
  const BuildPreview({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    children: <Widget>[
      Text('DEPLOY PREVIEW'),
      Text('✓ Resolve'),
      Text('✓ Analyze'),
      Text('✓ Test'),
      Text('✓ Package'),
      Text('✓ Sign'),
      Text('✓ Publish'),
    ],
  );
}

class ValidationFeedback extends StatefulWidget {
  const ValidationFeedback({super.key});

  @override
  State<ValidationFeedback> createState() => _ValidationFeedbackState();
}

class _ValidationFeedbackState extends State<ValidationFeedback> {
  final name = TextEditingController();
  final nameFocus = FocusNode(debugLabel: 'pilot name');
  var submitCount = 0;
  var message = 'Enter a pilot name, then validate it.';
  var success = false;

  void submit() {
    final value = name.text.trim();
    setState(() {
      submitCount++;
      success = value.isNotEmpty;
      message = success
          ? '✓ $value is cleared for launch'
          : '✕ Enter any non-empty name';
    });
    nameFocus.requestFocus();
  }

  Widget feedback() {
    final color = success
        ? const RgbColor(70, 220, 145)
        : const RgbColor(255, 90, 90);
    final effect = Text(message, style: CellStyle(foreground: color)).animate(
      trigger: submitCount,
      curve: Curves.easeOut,
      duration: const Duration(milliseconds: 650),
    );
    return effect.wipeIn(from: Edge.left);
  }

  @override
  void dispose() {
    name.dispose();
    nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      SizedBox(
        width: 28,
        child: TextInput(
          controller: name,
          focusNode: nameFocus,
          autofocus: true,
          semanticLabel: 'Pilot name',
          placeholder: 'Type any name',
          onSubmit: (_) => submit(),
        ),
      ),
      feedback(),
      Button(label: 'Validate pilot', onPressed: submit),
    ],
  );
}

class PacketController {
  final position = Animation<int>(0, debugLabel: 'packet position');

  Future<void> send() async {
    position.snap(0);
    await position
        .to(
          10,
          curve: Curves.easeInOut,
          duration: const Duration(milliseconds: 900),
        )
        .delay(const Duration(milliseconds: 350))
        .to(
          20,
          curve: Curves.easeInOut,
          duration: const Duration(milliseconds: 1000),
        )
        .delay(const Duration(milliseconds: 350))
        .to(
          30,
          curve: Curves.easeOut,
          duration: const Duration(milliseconds: 1100),
        )
        .orCancel;
  }

  void dispose() => position.dispose();
}

class PacketRoute extends StatefulWidget {
  const PacketRoute({super.key});

  @override
  State<PacketRoute> createState() => _PacketRouteState();
}

class _PacketRouteState extends State<PacketRoute> {
  final packet = PacketController();
  var sending = false;

  Future<void> send() async {
    setState(() => sending = true);
    try {
      await packet.send();
    } on TickerCanceled {
      return;
    }
    if (mounted) setState(() => sending = false);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      PacketTrack(position: packet.position.value),
      Button(label: sending ? 'Restart route' : 'Send packet', onPressed: send),
    ],
  );

  @override
  void dispose() {
    packet.dispose();
    super.dispose();
  }
}

class PacketTrack extends StatelessWidget {
  const PacketTrack({super.key, required this.position});

  final int position;

  @override
  Widget build(BuildContext context) {
    final route = List<String>.filled(31, '·');
    route[10] = '1';
    route[20] = '2';
    route[30] = '◆';
    route[position.clamp(0, 30)] = position >= 30 ? '◉' : '●';
    return Text(route.join());
  }
}

class PacketTransferFrames extends StatefulWidget {
  const PacketTransferFrames({super.key});

  @override
  State<PacketTransferFrames> createState() => _PacketTransferFramesState();
}

class _PacketTransferFramesState extends State<PacketTransferFrames> {
  static const frames = <String>[
    '●··········◇',
    '──●········◇',
    '────●······◇',
    '──────●····◇',
    '────────●··◇',
    '──────────◆',
  ];
  var fast = true;
  var running = true;

  Duration get interval => Duration(milliseconds: fast ? 180 : 650);

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      const SizedBox(height: 1),
      Row(
        children: <Widget>[
          Button(
            label: fast ? 'Slow down' : 'Speed up',
            onPressed: () => setState(() => fast = !fast),
          ),
          const SizedBox(width: 1),
          Button(
            label: running ? 'Pause' : 'Resume',
            onPressed: () => setState(() => running = !running),
          ),
        ],
      ),
      FrameBuilder(
        interval: interval,
        enabled: running,
        builder: (context, frame, _, delta) {
          final index = frame % frames.length;
          return Column(
            children: <Widget>[
              Text('UPLINK ${frames[index]} ARCHIVE'),
              Text('authored frame ${index + 1}/${frames.length}'),
            ],
          );
        },
      ),
    ],
  );
}

class TickerSimulation extends StatefulWidget {
  const TickerSimulation({super.key});

  @override
  State<TickerSimulation> createState() => _TickerSimulationState();
}

class _TickerSimulationState extends State<TickerSimulation>
    with SingleTickerProviderStateMixin {
  Ticker? ticker;
  Duration lastElapsed = Duration.zero;
  var position = 0.0;
  var velocity = 12.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ticker ??= createTicker(onTick)..start();
  }

  void onTick(Duration elapsed) {
    final seconds = (elapsed - lastElapsed).inMicroseconds / 1000000;
    lastElapsed = elapsed;
    var next = position + (velocity * seconds);
    if (next >= 28) {
      next = 28 - (next - 28);
      velocity = -velocity.abs();
    } else if (next <= 0) {
      next = -next;
      velocity = velocity.abs();
    }
    setState(() => position = next.clamp(0.0, 28.0));
  }

  void toggle() => setState(() {
    if (ticker!.isActive) {
      ticker!.stop();
    } else {
      lastElapsed = Duration.zero;
      ticker!.start();
    }
  });

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Text('Simulation position: ${position.toStringAsFixed(1)}'),
      Button(
        label: ticker?.isActive == true
            ? 'Pause simulation'
            : 'Resume simulation',
        onPressed: toggle,
      ),
    ],
  );
}
