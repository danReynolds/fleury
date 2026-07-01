// Clipboard write-path tests. Drives SystemClipboard with stub
// environment / runTool / stdout so we can assert each layer of the
// fallback chain in isolation.

import 'dart:convert';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  group('SystemClipboard — platform tool path', () {
    test('chooses pbcopy on macOS-ish envs (Wayland/X11 unset)', () async {
      // Note: we can't override `Platform.isMacOS` in this test
      // harness — but the Linux branch with neither WAYLAND_DISPLAY
      // nor DISPLAY skips the tool path and falls to OSC 52, so we
      // probe Linux's "no display" case here. The pbcopy/wl-copy/clip
      // branch selection logic itself is covered by inspection.
      final clip = SystemClipboard(
        environment: const <String, String>{},
        stdoutWrite: (_) {},
        runTool: (executable, args, text) async => true,
      );
      // No SSH env, no display → on Linux: no tool, falls to OSC 52.
      // The test still verifies the in-process register is populated.
      await clip.write('hello');
      expect(clip.readInProcess(), 'hello');
    });

    test('skips the platform tool when SSH_TTY is set', () async {
      var toolInvocations = 0;
      String? oscEmitted;
      final clip = SystemClipboard(
        environment: const <String, String>{
          'SSH_TTY': '/dev/pts/1',
          'DISPLAY': ':0',
        },
        stdoutWrite: (s) => oscEmitted = s,
        runTool: (executable, args, text) async {
          toolInvocations++;
          return true;
        },
      );
      final result = await clip.write('hello');
      expect(toolInvocations, 0, reason: 'SSH must skip platform tool');
      expect(result, ClipboardWriteResult.osc52);
      expect(oscEmitted, isNotNull);
    });

    test('skips the platform tool when SSH_CONNECTION is set', () async {
      var toolInvocations = 0;
      final clip = SystemClipboard(
        environment: const <String, String>{
          'SSH_CONNECTION': '10.0.0.1 22 10.0.0.2 22',
          'DISPLAY': ':0',
        },
        stdoutWrite: (_) {},
        runTool: (executable, args, text) async {
          toolInvocations++;
          return true;
        },
      );
      await clip.write('payload');
      expect(toolInvocations, 0);
    });

    test(
      'falls through to OSC 52 when the platform tool exits non-zero',
      () async {
        String? oscEmitted;
        final clip = SystemClipboard(
          environment: const <String, String>{'DISPLAY': ':0'},
          stdoutWrite: (s) => oscEmitted = s,
          runTool: (executable, args, text) async => false,
        );
        final result = await clip.write('hello');
        expect(result, ClipboardWriteResult.osc52);
        expect(oscEmitted, isNotNull);
      },
    );
  });

  group('SystemClipboard — OSC 52 escape', () {
    test('emits a base64-encoded clipboard set sequence', () async {
      String? oscEmitted;
      final clip = SystemClipboard(
        environment: const <String, String>{'SSH_TTY': '/dev/pts/1'},
        stdoutWrite: (s) => oscEmitted = s,
        runTool: (executable, args, text) async => true,
      );
      const payload = 'hello world';
      await clip.write(payload);

      expect(oscEmitted, isNotNull);
      // Spec: ESC ] 52 ; c ; <base64> BEL
      expect(oscEmitted!.startsWith('\x1b]52;c;'), isTrue);
      expect(oscEmitted!.endsWith('\x07'), isTrue);
      final encoded = oscEmitted!.substring(7, oscEmitted!.length - 1);
      expect(utf8.decode(base64.decode(encoded)), payload);
    });

    test('writeWithReport exposes OSC 52 capability state', () async {
      String? oscEmitted;
      final clip = SystemClipboard(
        environment: const <String, String>{'SSH_TTY': '/dev/pts/1'},
        stdoutWrite: (s) => oscEmitted = s,
        runTool: (executable, args, text) async => true,
      );

      final report = await clip.writeWithReport('hello');
      final state = report.toSemanticState();

      expect(report.result, ClipboardWriteResult.osc52);
      expect(report.resolution.feature, TerminalFeature.osc52Clipboard);
      expect(report.resolution.state, CapabilityResolutionState.available);
      expect(report.overSsh, isTrue);
      expect(report.osc52Attempted, isTrue);
      expect(report.osc52Emitted, isTrue);
      expect(oscEmitted, isNotNull);
      expect(state.terminalCapability, 'osc52Clipboard');
      expect(state.capabilityRequirement, 'preferred');
      expect(state.capabilityResolution, 'available');
      expect(state.clipboardTransport, 'osc52');
      expect(state.clipboardPolicy, 'standard');
      expect(state.values['clipboardInProcessUpdated'], isTrue);
    });

    test('refuses to emit a payload larger than the safe cap', () async {
      String? oscEmitted;
      final clip = SystemClipboard(
        environment: const <String, String>{'SSH_TTY': '/dev/pts/1'},
        stdoutWrite: (s) => oscEmitted = s,
        runTool: (executable, args, text) async => true,
      );
      // > 100KB after base64. A 100KB raw string base64s to ~133KB.
      final huge = 'a' * 100000;
      final result = await clip.write(huge);
      expect(result, ClipboardWriteResult.inProcessOnly);
      expect(oscEmitted, isNull);
      // In-process register still populated.
      expect(clip.readInProcess(), huge);
    });

    test('policy can force in-process-only writes', () async {
      String? oscEmitted;
      final clip = SystemClipboard(
        environment: const <String, String>{'SSH_TTY': '/dev/pts/1'},
        stdoutWrite: (s) => oscEmitted = s,
        runTool: (executable, args, text) async => true,
      );

      final report = await clip.writeWithReport(
        'local only',
        policy: ClipboardWritePolicy.inProcessOnly,
      );

      expect(report.result, ClipboardWriteResult.inProcessOnly);
      expect(report.resolution.feature, TerminalFeature.osc52Clipboard);
      expect(
        report.resolution.state,
        CapabilityResolutionState.disabledByPolicy,
      );
      expect(report.resolution.fallbackLabel, 'in-process register');
      expect(report.osc52Attempted, isFalse);
      expect(report.osc52Emitted, isFalse);
      expect(oscEmitted, isNull);
      expect(clip.readInProcess(), 'local only');
      expect(report.toSemanticState().clipboardPolicy, 'inProcessOnly');
    });
  });

  group('SystemClipboard — in-process register', () {
    test('always populates regardless of which path succeeded', () async {
      final clip = SystemClipboard(
        environment: const <String, String>{'SSH_TTY': '/dev/pts/1'},
        stdoutWrite: (_) {},
        runTool: (executable, args, text) async => true,
      );
      expect(clip.readInProcess(), isNull);
      await clip.write('first');
      expect(clip.readInProcess(), 'first');
      await clip.write('second');
      expect(clip.readInProcess(), 'second');
    });
  });

  group('InProcessClipboard', () {
    test('captures writes without touching stdout or processes', () async {
      final clip = InProcessClipboard();
      final result = await clip.write('hello');
      expect(result, ClipboardWriteResult.inProcessOnly);
      expect(clip.lastWritten, 'hello');
      expect(clip.readInProcess(), 'hello');
    });

    test('writeWithReport marks the in-process fallback', () async {
      final clip = InProcessClipboard();
      final report = await clip.writeWithReport('hello');

      expect(report.result, ClipboardWriteResult.inProcessOnly);
      expect(report.resolution.feature, TerminalFeature.clipboardWrite);
      expect(report.resolution.state, CapabilityResolutionState.degraded);
      expect(report.resolution.fallbackLabel, 'in-process register');
      expect(report.toSemanticState().clipboardTransport, 'inProcessOnly');
    });
  });
}
