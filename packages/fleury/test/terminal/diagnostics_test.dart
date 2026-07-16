import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('terminal capability detection', () {
    test('detects color, images, and multiplexers from environment', () {
      final capabilities =
          detectTerminalCapabilitiesFromEnvironment(const <String, String>{
            'TERM': 'xterm-256color',
            'COLORTERM': 'truecolor',
            'TERM_PROGRAM': 'ghostty',
            'TMUX': '/tmp/tmux-501/default,123,0',
          });

      expect(capabilities.colorMode, ColorMode.truecolor);
      expect(capabilities.glyphTier, GlyphTier.unicode);
      expect(capabilities.imageProtocol, ImageProtocol.halfBlock);
      expect(capabilities.tmuxPassthrough, isFalse);
    });

    test('uses a conservative native-image policy under multiplexers', () {
      TerminalCapabilities detect(Map<String, String> environment) =>
          detectTerminalCapabilitiesFromEnvironment(environment);

      final nativeIterm = detect(const <String, String>{
        'TERM': 'xterm-256color',
        'TERM_PROGRAM': 'iTerm.app',
        'LC_TERMINAL': 'iTerm2',
      });
      expect(nativeIterm.imageProtocol, ImageProtocol.iterm2);
      expect(
        nativeIterm.toSurfaceCapabilities().images,
        InlineImageSupport.placements,
      );

      for (final environment in const <Map<String, String>>[
        <String, String>{
          'TERM': 'tmux-256color',
          'TERM_PROGRAM': 'iTerm.app',
          'LC_TERMINAL': 'iTerm2',
          'TMUX': '/tmp/tmux-501/default,123,0',
        },
        <String, String>{
          'TERM': 'xterm-sixel',
          'TMUX': '/tmp/tmux-501/default,123,0',
        },
      ]) {
        final capabilities = detect(environment);
        expect(capabilities.imageProtocol, ImageProtocol.halfBlock);
        expect(capabilities.tmuxPassthrough, isFalse);
        expect(
          capabilities.toSurfaceCapabilities().images,
          InlineImageSupport.none,
        );
      }

      final screen = detect(const <String, String>{
        'TERM': 'screen-256color',
        'TERM_PROGRAM': 'ghostty',
      });
      expect(screen.imageProtocol, ImageProtocol.halfBlock);
      expect(screen.tmuxPassthrough, isFalse);

      final screenBySession = detect(const <String, String>{
        'TERM': 'xterm-256color',
        'KITTY_WINDOW_ID': '1',
        'STY': '1234.session',
      });
      expect(screenBySession.imageProtocol, ImageProtocol.halfBlock);
      expect(screenBySession.tmuxPassthrough, isFalse);

      final zellij = detect(const <String, String>{
        'TERM': 'xterm-256color',
        'TERM_PROGRAM': 'WezTerm',
        'ZELLIJ': '0',
      });
      expect(zellij.imageProtocol, ImageProtocol.halfBlock);
      expect(zellij.tmuxPassthrough, isFalse);

      final screenNestedInTmux = detect(const <String, String>{
        'TERM': 'screen-256color',
        'KITTY_WINDOW_ID': '1',
        'TMUX': '/tmp/tmux-501/default,123,0',
        'STY': '1234.session',
      });
      expect(screenNestedInTmux.imageProtocol, ImageProtocol.halfBlock);
      expect(screenNestedInTmux.tmuxPassthrough, isFalse);

      final tmuxKitty = detect(const <String, String>{
        'TERM': 'xterm-kitty',
        'KITTY_WINDOW_ID': '1',
        'TMUX': '/tmp/tmux-501/default,123,0',
      });
      expect(tmuxKitty.imageProtocol, ImageProtocol.halfBlock);
      expect(tmuxKitty.tmuxPassthrough, isFalse);
      expect(tmuxKitty.toSurfaceCapabilities().images, InlineImageSupport.none);
    });

    test('custom capability values round-trip without normalization', () {
      const caps = TerminalCapabilities(
        imageProtocol: ImageProtocol.kitty,
        tmuxPassthrough: true,
      );
      final restored = TerminalCapabilityReport.fromCapabilities(
        caps,
      ).toCapabilities();

      expect(caps.imageProtocol, ImageProtocol.kitty);
      expect(restored.imageProtocol, ImageProtocol.kitty);
      expect(restored.tmuxPassthrough, isTrue);
    });

    test('diagnoses the multiplexer image fallback explicitly', () {
      const environment = <String, String>{
        'TERM': 'tmux-256color',
        'TERM_PROGRAM': 'iTerm.app',
        'LC_TERMINAL': 'iTerm2',
        'TMUX': '/tmp/tmux-501/default,123,0',
      };
      final capabilities = detectTerminalCapabilitiesFromEnvironment(
        environment,
      );
      final diagnosis = diagnoseTerminal(
        FakeTerminalDriver(
          size: const CellSize(100, 30),
          capabilities: capabilities,
        ),
        environment: environment,
      );

      expect(capabilities.imageProtocol, ImageProtocol.halfBlock);
      expect(capabilities.tmuxPassthrough, isFalse);
      expect(
        diagnosis.toJson()['fallbacks'],
        containsMessageCode('image_multiplexer_fallback'),
      );
    });

    test('the capability report round-trips ambiguousCharWidth', () {
      // Every structured capability field survives fromCapabilities →
      // toCapabilities; a probed narrow result must not silently revert to wide.
      const caps = TerminalCapabilities(
        ambiguousCharWidth: AmbiguousCharWidth.narrow,
      );
      final restored = TerminalCapabilityReport.fromCapabilities(
        caps,
      ).toCapabilities();
      expect(restored.ambiguousCharWidth, AmbiguousCharWidth.narrow);
    });

    test('detects ASCII glyph tier from explicit override and locale', () {
      expect(
        detectTerminalCapabilitiesFromEnvironment(const <String, String>{
          'FLEURY_GLYPH_TIER': 'ascii',
        }).glyphTier,
        GlyphTier.ascii,
      );
      expect(
        detectTerminalCapabilitiesFromEnvironment(const <String, String>{
          'TERM': 'xterm-256color',
          'LANG': 'C',
        }).glyphTier,
        GlyphTier.ascii,
      );
      expect(
        detectTerminalCapabilitiesFromEnvironment(const <String, String>{
          'TERM': 'xterm-256color',
          'LANG': 'en_US.UTF-8',
        }).glyphTier,
        GlyphTier.unicode,
      );
    });

    test('honors NO_COLOR over forced color', () {
      final capabilities = detectTerminalCapabilitiesFromEnvironment(
        const <String, String>{
          'NO_COLOR': '1',
          'CLICOLOR_FORCE': '1',
          'TERM': 'xterm-256color',
        },
      );

      expect(capabilities.colorMode, ColorMode.none);
    });

    test('falls back to ansi16 when color is forced without TERM', () {
      final capabilities = detectTerminalCapabilitiesFromEnvironment(
        const <String, String>{'CLICOLOR_FORCE': '1'},
      );

      expect(capabilities.colorMode, ColorMode.ansi16);
    });
  });

  group('diagnoseTerminal', () {
    test('serializes terminal profile and capability report', () {
      final driver = FakeTerminalDriver(
        size: const CellSize(120, 40),
        capabilities: const TerminalCapabilities(
          colorMode: ColorMode.truecolor,
          glyphTier: GlyphTier.unicode,
          imageProtocol: ImageProtocol.kitty,
          tmuxPassthrough: true,
        ),
      );

      final diagnosis = diagnoseTerminal(
        driver,
        environment: const <String, String>{
          'TERM': 'xterm-256color',
          'COLORTERM': 'truecolor',
          'TERM_PROGRAM': 'WezTerm',
          'TMUX': '/tmp/tmux-501/default,123,0',
        },
        platform: const TerminalPlatformReport(
          operatingSystem: 'windows',
          operatingSystemVersion: 'Windows 11',
          dartVersion: '3.12.1',
        ),
        stdinIsTerminal: true,
        stdoutIsTerminal: true,
      );
      final json = diagnosis.toJson();
      final terminal = json['terminal'] as Map<String, Object?>;
      final platform = json['platform'] as Map<String, Object?>;
      final capabilities = json['capabilities'] as Map<String, Object?>;
      final environment = json['environment'] as Map<String, Object?>;

      expect(json['schemaVersion'], 1);
      expect(terminal['term'], 'xterm-256color');
      expect(terminal['termProgram'], 'WezTerm');
      expect(terminal['columns'], 120);
      expect(terminal['rows'], 40);
      expect(terminal['isInteractive'], isTrue);
      expect(platform['operatingSystem'], 'windows');
      expect(platform['operatingSystemVersion'], 'Windows 11');
      expect(platform['dartVersion'], '3.12.1');
      expect(capabilities['colorMode'], 'truecolor');
      expect(capabilities['glyphTier'], 'unicode');
      expect(capabilities['imageProtocol'], 'kitty');
      expect(capabilities['tmuxPassthrough'], isTrue);
      expect(environment['tmux'], isTrue);
      expect(json['warnings'], containsMessageCode('terminal_multiplexer'));
      expect(json['unsupportedFeatures'], isEmpty);
    });

    test('reports non-interactive and fallback conditions', () {
      final driver = FakeTerminalDriver(
        size: const CellSize(80, 24),
        isInteractive: false,
        capabilities: const TerminalCapabilities(
          colorMode: ColorMode.none,
          glyphTier: GlyphTier.ascii,
          imageProtocol: ImageProtocol.halfBlock,
          supportsAlternateScreen: false,
          supportsHidingCursor: false,
        ),
      );

      final diagnosis = diagnoseTerminal(
        driver,
        environment: const <String, String>{
          'TERM': 'dumb',
          'NO_COLOR': '1',
          'SSH_TTY': '/dev/ttys001',
        },
        stdinIsTerminal: false,
        stdoutIsTerminal: false,
      );
      final json = diagnosis.toJson();
      final unsupported = json['unsupportedFeatures'] as List<String>;

      expect(
        json['fallbacks'],
        containsMessageCode('color_monochrome_fallback'),
      );
      expect(
        json['fallbacks'],
        containsMessageCode('image_half_block_fallback'),
      );
      expect(json['fallbacks'], containsMessageCode('glyph_ascii_fallback'));
      expect(
        json['fallbacks'],
        containsMessageCode('visual_output_unavailable'),
      );
      expect(json['warnings'], containsMessageCode('non_interactive_stdout'));
      expect(json['warnings'], containsMessageCode('non_interactive_stdin'));
      expect(json['warnings'], containsMessageCode('remote_terminal'));
      expect(
        unsupported,
        containsAll(<String>[
          'visualTuiOutput',
          'ansiColor',
          'nativeImages',
          'alternateScreen',
          'cursorHiding',
        ]),
      );
    });

    test('compares active probe evidence with passive capabilities', () {
      final driver = FakeTerminalDriver(
        capabilities: const TerminalCapabilities(
          imageProtocol: ImageProtocol.kitty,
        ),
      );
      final diagnosis = diagnoseTerminal(driver).withActiveProbes(
        const TerminalProbeReport(
          probes: <TerminalProbeResult>[
            TerminalProbeResult(
              id: 'kittyKeyboardStatus',
              label: 'Kitty keyboard status',
              feature: TerminalFeature.kittyKeyboard,
              status: TerminalProbeStatus.confirmed,
              elapsed: Duration(milliseconds: 2),
            ),
            TerminalProbeResult(
              id: 'kittyGraphicsQuery',
              label: 'Kitty graphics query',
              feature: TerminalFeature.imageKitty,
              status: TerminalProbeStatus.unsupported,
              elapsed: Duration(milliseconds: 3),
            ),
          ],
        ),
      );

      final keyboard = diagnosis.compatibility!.findingFor(
        TerminalFeature.kittyKeyboard,
      )!;
      final graphics = diagnosis.compatibility!.findingFor(
        TerminalFeature.imageKitty,
      )!;

      expect(keyboard.status, TerminalCompatibilityStatus.activeConfirmed);
      expect(keyboard.passiveSupported, isFalse);
      expect(graphics.status, TerminalCompatibilityStatus.passiveUnverified);
      expect(graphics.passiveSupported, isTrue);

      final json = diagnosis.toJson();
      final compatibility = json['compatibility'] as Map<String, Object?>;
      final summary = compatibility['summary'] as Map<String, Object?>;
      expect(summary['activeConfirmed'], 1);
      expect(summary['passiveUnverified'], 1);
      expect(
        compatibility['activeConfirmedFeatures'],
        contains('kittyKeyboard'),
      );
      expect(
        compatibility['confirmedAvailableFeatures'],
        contains('kittyKeyboard'),
      );
      expect(
        compatibility['confirmedAvailableFeatures'],
        isNot(contains('imageKitty')),
      );
    });

    test('does not advertise probe-only Kitty through a multiplexer', () {
      const environment = <String, String>{
        'TERM': 'tmux-256color',
        'KITTY_WINDOW_ID': '1',
        'TMUX': '/tmp/tmux-501/default,123,0',
      };
      final capabilities = detectTerminalCapabilitiesFromEnvironment(
        environment,
      );
      final diagnosis =
          diagnoseTerminal(
            FakeTerminalDriver(capabilities: capabilities),
            environment: environment,
          ).withActiveProbes(
            const TerminalProbeReport(
              probes: <TerminalProbeResult>[
                TerminalProbeResult(
                  id: 'kittyGraphicsQuery',
                  label: 'Kitty graphics query',
                  feature: TerminalFeature.imageKitty,
                  status: TerminalProbeStatus.confirmed,
                  elapsed: Duration(milliseconds: 2),
                ),
              ],
            ),
          );

      final graphics = diagnosis.compatibility!.findingFor(
        TerminalFeature.imageKitty,
      )!;
      expect(capabilities.imageProtocol, ImageProtocol.halfBlock);
      expect(graphics.activeStatus, TerminalProbeStatus.confirmed);
      expect(graphics.status, TerminalCompatibilityStatus.inconclusive);
      expect(graphics.detail, contains('not authoritative'));
      expect(
        diagnosis.confirmedAvailableFeatures,
        isNot(contains(TerminalFeature.imageKitty)),
      );
      expect(
        diagnosis.compatibility!.activeConfirmedFeatures,
        isNot(contains(TerminalFeature.imageKitty)),
      );
    });

    test('ignores raw Kitty probe results through any multiplexer', () {
      const environment = <String, String>{
        'TERM': 'xterm-kitty',
        'KITTY_WINDOW_ID': '1',
        'TMUX': '/tmp/tmux-501/default,123,0',
      };
      const capabilities = TerminalCapabilities(
        imageProtocol: ImageProtocol.kitty,
      );
      final diagnosis =
          diagnoseTerminal(
            FakeTerminalDriver(capabilities: capabilities),
            environment: environment,
          ).withActiveProbes(
            const TerminalProbeReport(
              probes: <TerminalProbeResult>[
                TerminalProbeResult(
                  id: 'kittyGraphicsQuery',
                  label: 'Kitty graphics query',
                  feature: TerminalFeature.imageKitty,
                  status: TerminalProbeStatus.unsupported,
                  elapsed: Duration(milliseconds: 2),
                ),
              ],
            ),
          );

      final graphics = diagnosis.compatibility!.findingFor(
        TerminalFeature.imageKitty,
      )!;
      expect(capabilities.imageProtocol, ImageProtocol.kitty);
      expect(graphics.passiveSupported, isTrue);
      expect(graphics.activeStatus, TerminalProbeStatus.unsupported);
      expect(graphics.status, TerminalCompatibilityStatus.inconclusive);
      expect(graphics.detail, contains('not authoritative'));
    });

    test('compatibility findings are inconclusive when probes are skipped', () {
      final diagnosis = diagnoseTerminal(
        FakeTerminalDriver(),
      ).withActiveProbes(TerminalProbeReport.skipped('not a tty'));

      final compatibility = diagnosis.compatibility!;

      expect(compatibility.skippedReason, 'not a tty');
      expect(
        compatibility.findings.map((finding) => finding.status),
        everyElement(TerminalCompatibilityStatus.inconclusive),
      );
      expect(diagnosis.toJson()['compatibility'], isA<Map<String, Object?>>());
    });

    test('active-probe attachment preserves platform evidence', () {
      final diagnosis = diagnoseTerminal(
        FakeTerminalDriver(),
        platform: const TerminalPlatformReport(
          operatingSystem: 'windows',
          operatingSystemVersion: 'Windows 11',
          dartVersion: '3.12.1',
        ),
      ).withActiveProbes(TerminalProbeReport.skipped('not a tty'));

      final platform = diagnosis.toJson()['platform'] as Map<String, Object?>;
      expect(platform['operatingSystem'], 'windows');
      expect(diagnosis.compatibility, isNotNull);
    });

    test('confirmed active probe features can satisfy requirements', () {
      final diagnosis = diagnoseTerminal(FakeTerminalDriver()).withActiveProbes(
        const TerminalProbeReport(
          probes: <TerminalProbeResult>[
            TerminalProbeResult(
              id: 'kittyGraphicsQuery',
              label: 'Kitty graphics query',
              feature: TerminalFeature.imageKitty,
              status: TerminalProbeStatus.confirmed,
              elapsed: Duration(milliseconds: 3),
            ),
          ],
        ),
      );

      final requirement = CapabilityRequirement(
        feature: TerminalFeature.imageKitty,
        level: CapabilityLevel.preferred,
        fallback: const CapabilityFallback(label: 'half-block'),
      );
      final passiveOnly = resolveCapabilityRequirement(
        requirement,
        diagnosis.passiveCapabilities,
      );
      final withActiveEvidence = resolveCapabilityRequirement(
        requirement,
        diagnosis.passiveCapabilities,
        additionalAvailableFeatures: diagnosis.confirmedAvailableFeatures,
      );

      expect(
        diagnosis.passiveCapabilities.imageProtocol,
        ImageProtocol.halfBlock,
      );
      expect(
        diagnosis.compatibility!.activeConfirmedFeatures,
        contains(TerminalFeature.imageKitty),
      );
      expect(passiveOnly.state, CapabilityResolutionState.degraded);
      expect(passiveOnly.fallbackLabel, 'half-block');
      expect(withActiveEvidence.state, CapabilityResolutionState.available);
      expect(withActiveEvidence.fallbackLabel, isNull);
    });
  });
}

Matcher containsMessageCode(String code) {
  return contains(
    predicate<Object?>((Object? value) {
      return value is Map<String, Object?> && value['code'] == code;
    }, 'diagnostic message with code $code'),
  );
}
