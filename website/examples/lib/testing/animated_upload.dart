import 'package:fleury/fleury_core.dart';

class AnimatedUpload extends StatefulWidget {
  const AnimatedUpload({super.key});

  @override
  State<AnimatedUpload> createState() => _AnimatedUploadState();
}

class _AnimatedUploadState extends State<AnimatedUpload> {
  double target = 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AnimationBuilder<double>(
        target,
        duration: const Duration(seconds: 1),
        curve: Curves.linear,
        builder: (_, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 26,
              child: ProgressBar(value: value, semanticLabel: 'Upload'),
            ),
            Text('${(value * 100).round()}%'),
          ],
        ),
      ),
      Button(
        text: 'Animate',
        onPressed: () => setState(() => target = target == 0 ? 1 : 0),
      ),
    ],
  );
}
