// OSC 8 hyperlink capability detection (Stage 1): the shared env-flag parse,
// the four-state reason (HyperlinkSupport) with version thresholds and tmux
// suppression, the emission-gate bool derived from it, the downstream
// projection / feature-gate wiring, and the accurate end-to-end diagnose state.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('parseEnvFlag', () {
    test('parses the accepted on/off vocabulary; null otherwise', () {
      for (final on in const ['1', 'true', 'yes', 'on', 'TRUE', ' On ']) {
        expect(parseEnvFlag(on), isTrue, reason: on);
      }
      for (final off in const ['0', 'false', 'no', 'off', 'OFF', ' 0 ']) {
        expect(parseEnvFlag(off), isFalse, reason: off);
      }
      for (final none in <String?>[null, '', 'maybe', '2']) {
        expect(parseEnvFlag(none), isNull, reason: '$none');
      }
    });
  });

  group('detectHyperlinkSupportFromEnvironment (the four-state reason)', () {
    test('supported for a version-checked, allow-listed terminal', () {
      expect(
        detectHyperlinkSupportFromEnvironment(
          const {'TERM_PROGRAM': 'iTerm.app', 'TERM_PROGRAM_VERSION': '3.4.19'},
        ),
        HyperlinkSupport.supported,
      );
      expect(
        detectHyperlinkSupportFromEnvironment(const {'TERM_PROGRAM': 'ghostty'}),
        HyperlinkSupport.supported,
      );
    });

    test('disabled-by-override for FLEURY_HYPERLINKS=0 on a supporting terminal',
        () {
      // Previously mislabeled 'unsupported'.
      expect(
        detectHyperlinkSupportFromEnvironment(
          const {'FLEURY_HYPERLINKS': '0', 'TERM_PROGRAM': 'ghostty'},
        ),
        HyperlinkSupport.disabledByOverride,
      );
    });

    test('suppressed-under-tmux ONLY for a genuinely-capable outer terminal',
        () {
      expect(
        detectHyperlinkSupportFromEnvironment(
          const {'TERM_PROGRAM': 'ghostty', 'TMUX': '/tmp/tmux-1/def,9,0'},
        ),
        HyperlinkSupport.suppressedUnderTmux,
      );
    });

    test('unsupported for a non-capable terminal under tmux (NOT suppressed)',
        () {
      // Previously mislabeled 'suppressed-under-tmux' — which would tell the
      // user to leave tmux for links Apple_Terminal cannot render regardless.
      expect(
        detectHyperlinkSupportFromEnvironment(
          const {
            'TERM_PROGRAM': 'Apple_Terminal',
            'TMUX': '/tmp/tmux-1/def,9,0',
          },
        ),
        HyperlinkSupport.unsupported,
      );
      expect(
        detectHyperlinkSupportFromEnvironment(const {'TERM': 'xterm-256color'}),
        HyperlinkSupport.unsupported,
      );
    });

    test('FLEURY_HYPERLINKS=1 forces supported even under tmux', () {
      expect(
        detectHyperlinkSupportFromEnvironment(
          const {
            'FLEURY_HYPERLINKS': '1',
            'TERM_PROGRAM': 'Apple_Terminal',
            'TMUX': '/tmp/tmux-1/def,9,0',
          },
        ),
        HyperlinkSupport.supported,
      );
    });

    test('diagnoseLabel maps each state to its stable string', () {
      expect(HyperlinkSupport.supported.diagnoseLabel, 'supported');
      expect(
        HyperlinkSupport.suppressedUnderTmux.diagnoseLabel,
        'suppressed-under-tmux',
      );
      expect(
        HyperlinkSupport.disabledByOverride.diagnoseLabel,
        'disabled-by-override',
      );
      expect(HyperlinkSupport.unsupported.diagnoseLabel, 'unsupported');
    });
  });

  group('version thresholds', () {
    test('VTE >= 5000 supported; older VTE unsupported', () {
      expect(
        detectHyperlinksFromEnvironment(const {'VTE_VERSION': '5200'}),
        isTrue,
      );
      expect(
        detectHyperlinksFromEnvironment(const {'VTE_VERSION': '5000'}),
        isTrue,
      );
      expect(
        detectHyperlinksFromEnvironment(const {'VTE_VERSION': '4600'}),
        isFalse,
        reason: 'pre-0.50 VTE renders OSC 8 as literal garbage',
      );
    });

    test('iTerm >= 3.1 supported; older / version-less iTerm unsupported', () {
      expect(
        detectHyperlinksFromEnvironment(
          const {'TERM_PROGRAM': 'iTerm.app', 'TERM_PROGRAM_VERSION': '3.1'},
        ),
        isTrue,
      );
      expect(
        detectHyperlinksFromEnvironment(
          const {'TERM_PROGRAM': 'iTerm.app', 'TERM_PROGRAM_VERSION': '3.0.15'},
        ),
        isFalse,
      );
      expect(
        detectHyperlinksFromEnvironment(
          const {'TERM_PROGRAM': 'iTerm.app', 'TERM_PROGRAM_VERSION': '2.9'},
        ),
        isFalse,
      );
      expect(
        detectHyperlinksFromEnvironment(const {'TERM_PROGRAM': 'iTerm.app'}),
        isFalse,
        reason: 'no version -> cannot confirm >= 3.1',
      );
    });

    test('version-less allow-list stays presence-based', () {
      for (final env in const <Map<String, String>>[
        {'TERM_PROGRAM': 'WezTerm'},
        {'TERM_PROGRAM': 'ghostty'},
        {'KITTY_WINDOW_ID': '1'},
        {'TERM': 'xterm-kitty'},
        {'WT_SESSION': 'abc-123'},
      ]) {
        expect(detectHyperlinksFromEnvironment(env), isTrue, reason: '$env');
      }
    });

    test('known non-OSC-8 terminals stay unsupported — no false link claim', () {
      // Regression guard for two terminals that do NOT implement OSC 8 and must
      // NOT be allow-listed — both merely sniff visible URLs out of the text
      // (their own link detection), which is why the parenthetical URL looks
      // clickable but an OSC 8 escape is silently ignored:
      //   * Apple_Terminal — no OSC 8 support; URL auto-detection only.
      //   * WarpTerminal   — OSC 8 is an OPEN feature request (warp #4194);
      //     verified 2026-07-13 that a forced escape is not honored.
      // Emitting to a silent-ignorer isn't corrupting, but it's a false
      // `supported` claim in diagnose; the honest state is styled-but-unlinked.
      for (final program in const ['Apple_Terminal', 'WarpTerminal']) {
        expect(
          detectHyperlinksFromEnvironment({'TERM_PROGRAM': program}),
          isFalse,
          reason: program,
        );
      }
    });
  });

  group('detectHyperlinksFromEnvironment (emission-gate bool)', () {
    test('defaults false for an unknown terminal', () {
      expect(detectHyperlinksFromEnvironment(const {}), isFalse);
      expect(
        detectHyperlinksFromEnvironment(const {'TERM': 'xterm-256color'}),
        isFalse,
      );
    });

    test('FLEURY_HYPERLINKS override wins both ways', () {
      expect(
        detectHyperlinksFromEnvironment(const {'FLEURY_HYPERLINKS': '1'}),
        isTrue,
      );
      expect(
        detectHyperlinksFromEnvironment(
          const {'FLEURY_HYPERLINKS': '0', 'TERM_PROGRAM': 'ghostty'},
        ),
        isFalse,
      );
    });

    test('tmux suppresses a supporting terminal; force-on overrides it', () {
      expect(
        detectHyperlinksFromEnvironment(
          const {'TERM_PROGRAM': 'ghostty', 'TMUX': '/tmp/tmux-1/def,9,0'},
        ),
        isFalse,
      );
      expect(
        detectHyperlinksFromEnvironment(
          const {
            'TERM_PROGRAM': 'ghostty',
            'TMUX': '/tmp/tmux-1/def,9,0',
            'FLEURY_HYPERLINKS': '1',
          },
        ),
        isTrue,
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

  group('diagnose reflects the accurate OSC 8 state (end-to-end)', () {
    String diagnoseOsc8(Map<String, String> env) {
      final driver = FakeTerminalDriver(
        size: const CellSize(80, 24),
        capabilities: detectTerminalCapabilitiesFromEnvironment(env),
      );
      final json = diagnoseTerminal(driver, environment: env).toJson();
      return (json['capabilities'] as Map<String, Object?>)['osc8Hyperlinks']
          as String;
    }

    test('distinguishes all four states through diagnose JSON', () {
      expect(diagnoseOsc8(const {'TERM_PROGRAM': 'ghostty'}), 'supported');
      expect(
        diagnoseOsc8(
          const {'TERM_PROGRAM': 'ghostty', 'TMUX': '/tmp/tmux-1/def,9,0'},
        ),
        'suppressed-under-tmux',
      );
      // Previously-wrong case A: non-capable terminal under tmux.
      expect(
        diagnoseOsc8(
          const {
            'TERM_PROGRAM': 'Apple_Terminal',
            'TMUX': '/tmp/tmux-1/def,9,0',
          },
        ),
        'unsupported',
      );
      // Previously-wrong case B: explicit off on a supporting terminal.
      expect(
        diagnoseOsc8(
          const {'FLEURY_HYPERLINKS': '0', 'TERM_PROGRAM': 'ghostty'},
        ),
        'disabled-by-override',
      );
    });
  });
}
