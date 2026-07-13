// OSC 8 hyperlink capability detection (Stage 1): the env allow-list, the
// FLEURY_HYPERLINKS override (both ways, including its tmux escape hatch),
// tmux suppression, and the downstream projection / feature-gate / diagnose
// wiring that reads the detected value.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('detectHyperlinksFromEnvironment', () {
    test('defaults to false for an unknown terminal', () {
      expect(detectHyperlinksFromEnvironment(const {}), isFalse);
      expect(
        detectHyperlinksFromEnvironment(const {'TERM': 'xterm-256color'}),
        isFalse,
        reason: 'a generic xterm is not on the allow-list',
      );
    });

    test('FLEURY_HYPERLINKS override wins both ways', () {
      // Force ON over an unknown terminal.
      expect(detectHyperlinksFromEnvironment(const {'FLEURY_HYPERLINKS': '1'}),
          isTrue);
      // Force OFF over a known-supporting terminal.
      expect(
        detectHyperlinksFromEnvironment(
          const {'FLEURY_HYPERLINKS': '0', 'TERM_PROGRAM': 'iTerm.app'},
        ),
        isFalse,
        reason: 'explicit off beats the allow-list',
      );
    });

    test('known-supporting terminals are on the allow-list', () {
      for (final env in const <Map<String, String>>[
        {'TERM_PROGRAM': 'iTerm.app'},
        {'TERM_PROGRAM': 'WezTerm'},
        {'TERM_PROGRAM': 'ghostty'},
        {'VTE_VERSION': '7002'},
        {'KITTY_WINDOW_ID': '1'},
        {'TERM': 'xterm-kitty'},
        {'WT_SESSION': 'abc-123'},
      ]) {
        expect(
          detectHyperlinksFromEnvironment(env),
          isTrue,
          reason: 'expected support for $env',
        );
      }
    });

    test('tmux suppresses even a supporting outer terminal', () {
      // iTerm under tmux ($TMUX set) must NOT report support.
      expect(
        detectHyperlinksFromEnvironment(
          const {'TERM_PROGRAM': 'iTerm.app', 'TMUX': '/tmp/tmux-501/def,9,0'},
        ),
        isFalse,
      );
      // A screen/tmux $TERM also counts as a multiplexer.
      expect(
        detectHyperlinksFromEnvironment(
          const {'KITTY_WINDOW_ID': '1', 'TERM': 'screen.xterm-kitty'},
        ),
        isFalse,
      );
    });

    test('FLEURY_HYPERLINKS=1 overrides tmux suppression', () {
      expect(
        detectHyperlinksFromEnvironment(
          const {
            'TERM_PROGRAM': 'iTerm.app',
            'TMUX': '/tmp/tmux-501/def,9,0',
            'FLEURY_HYPERLINKS': '1',
          },
        ),
        isTrue,
        reason: 'explicit force-on wins even under tmux',
      );
    });
  });

  group('capability projection + feature gate', () {
    test('toSurfaceCapabilities reflects the detected value', () {
      final supporting = detectTerminalCapabilitiesFromEnvironment(
        const {'TERM_PROGRAM': 'ghostty'},
      );
      expect(supporting.hyperlinks, isTrue);
      expect(supporting.toSurfaceCapabilities().hyperlinks, isTrue);

      final unknown = detectTerminalCapabilitiesFromEnvironment(const {});
      expect(unknown.hyperlinks, isFalse);
      expect(unknown.toSurfaceCapabilities().hyperlinks, isFalse);
    });

    test('osc8Hyperlinks feature derives from the capability, not a constant',
        () {
      expect(
        terminalFeatureAvailable(
          TerminalFeature.osc8Hyperlinks,
          const TerminalCapabilities(hyperlinks: true),
        ),
        isTrue,
      );
      expect(
        terminalFeatureAvailable(
          TerminalFeature.osc8Hyperlinks,
          const TerminalCapabilities(),
        ),
        isFalse,
      );
    });
  });

  group('diagnose reflects real OSC 8 state', () {
    String osc8(TerminalCapabilities caps) =>
        TerminalCapabilityReport.fromCapabilities(caps).osc8Hyperlinks;

    test('supported when detected', () {
      expect(osc8(const TerminalCapabilities(hyperlinks: true)), 'supported');
    });

    test('suppressed-under-tmux when a multiplexer blocked support', () {
      expect(
        osc8(const TerminalCapabilities(tmuxPassthrough: true)),
        'suppressed-under-tmux',
      );
    });

    test('unsupported on an unknown terminal', () {
      expect(osc8(const TerminalCapabilities()), 'unsupported');
    });

    test('serializes the derived value into diagnose JSON', () {
      final json = TerminalCapabilityReport.fromCapabilities(
        const TerminalCapabilities(hyperlinks: true),
      ).toJson();
      expect(json['osc8Hyperlinks'], 'supported');
    });
  });
}
