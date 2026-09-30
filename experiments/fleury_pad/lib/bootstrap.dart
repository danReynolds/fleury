import 'dart:js_interop';
import 'package:fleury/fleury_core.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;
import 'main.dart' as user;

@JS('fleuryPadReassemble')
external set _reassemble(JSFunction callback);
@JS('fleuryPadReady')
external void _ready();

Future<void> main() async {
  final app = await mountApp(
    () => const _PadRoot(),
    into: web.document.querySelector('#app')!,
  );
  _reassemble = (() => _reload(app)).toJS;
  _ready();
}

// Future<void>.toJS boxes Dart exceptions behind a generic JavaScript error.
// Reject with the original message so the editor can explain a failed hook.
JSPromise _reload(MountedApp app) => JSPromise(
  ((JSFunction resolve, JSFunction reject) {
    app.reassemble().then(
      (_) => resolve.callAsFunction(null),
      onError: (Object error, StackTrace stack) {
        reject.callAsFunction(null, error.toString().toJS);
      },
    );
  }).toJS,
);

// Keep a live call to the editable entry point on every rebuild.
class _PadRoot extends StatelessWidget {
  const _PadRoot();

  @override
  Widget build(BuildContext context) => user.buildApp();
}
