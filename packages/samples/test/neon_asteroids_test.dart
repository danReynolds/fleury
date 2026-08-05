import 'package:fleury/fleury.dart';
import 'package:fleury_samples/src/neon_asteroids.dart';
import 'package:fleury_samples/src/neon_asteroids_model.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  group('NeonAsteroidsGame', () {
    test(
      'the same recorded input is independent of rendered frame cadence',
      () {
        final delayed = _controlledGame();
        final smooth = _controlledGame();
        const controls = NeonAsteroidsInput(
          rotateLeft: true,
          thrust: true,
          fire: true,
        );

        delayed.advance(const Duration(milliseconds: 240), controls);
        for (var i = 0; i < 24; i++) {
          smooth.advance(
            const Duration(milliseconds: 10),
            controls.copyWith(fire: i == 0),
          );
        }

        expect(_snapshot(delayed), _snapshot(smooth));
      },
    );

    test(
      'a forced frame delay is sub-stepped so fast bullets do not tunnel',
      () {
        final game = NeonAsteroidsGame(
          seed: 7,
          width: 120,
          height: 60,
          populate: false,
        )..start(spawnWave: false);
        game
          ..asteroids.add(
            NeonAsteroid(
              id: 41,
              position: NeonVector(50, 12),
              velocity: NeonVector(0, 0),
              radius: 3,
              tier: 1,
            ),
          )
          ..bullets.add(
            NeonBullet(
              position: NeonVector(8, 12),
              velocity: NeonVector(180, 0),
              lifeTicks: 180,
            ),
          );

        game.advance(
          const Duration(milliseconds: 400),
          const NeonAsteroidsInput(),
        );

        expect(game.score, 100);
        expect(game.asteroids.any((asteroid) => asteroid.id == 41), isFalse);
        expect(game.bullets, isEmpty);
      },
    );

    test('large asteroid collision splits into two deterministic children', () {
      final game = NeonAsteroidsGame(
        seed: 17,
        width: 120,
        height: 60,
        populate: false,
      )..start(spawnWave: false);
      game
        ..asteroids.add(
          NeonAsteroid(
            id: 8,
            position: NeonVector(40, 10),
            velocity: NeonVector(2, 0),
            radius: 9,
            tier: 3,
            spin: 0.2,
          ),
        )
        ..bullets.add(
          NeonBullet(
            position: NeonVector(10, 10),
            velocity: NeonVector(150, 0),
            lifeTicks: 120,
          ),
        );

      game.advance(
        const Duration(milliseconds: 300),
        const NeonAsteroidsInput(),
      );

      expect(game.score, 20);
      expect(game.asteroids, hasLength(2));
      expect(game.asteroids.every((asteroid) => asteroid.tier == 2), isTrue);
    });

    test(
      'ship collisions consume lives, reach game over, and restart cleanly',
      () {
        final game = NeonAsteroidsGame(
          seed: 21,
          width: 120,
          height: 60,
          populate: false,
        )..start(spawnWave: false);

        for (var hit = 0; hit < 3; hit++) {
          game
            ..asteroids.clear()
            ..ship.shieldTicks = 0
            ..asteroids.add(
              NeonAsteroid(
                id: 80 + hit,
                position: game.ship.position.copy(),
                velocity: NeonVector(0, 0),
                radius: 3,
                tier: 1,
              ),
            )
            ..advance(
              const Duration(microseconds: NeonAsteroidsGame.fixedStepMicros),
              const NeonAsteroidsInput(),
            );
        }

        expect(game.lives, 0);
        expect(game.phase, NeonAsteroidsPhase.gameOver);
        expect(game.impactEvent, 3);

        game.restart();
        expect(game.phase, NeonAsteroidsPhase.playing);
        expect(game.lives, 3);
        expect(game.score, 0);
        expect(game.wave, 1);
      },
    );

    test('moving entities wrap across both playfield edges', () {
      final game = NeonAsteroidsGame(
        seed: 31,
        width: 120,
        height: 60,
        populate: false,
      )..start(spawnWave: false);
      game.ship
        ..position.x = 119.9
        ..position.y = 59.9
        ..velocity.x = 30
        ..velocity.y = 30;
      game.asteroids.add(
        NeonAsteroid(
          id: 90,
          position: NeonVector(0.1, 0.1),
          velocity: NeonVector(-30, -30),
          radius: 3,
          tier: 1,
        ),
      );

      game.advance(
        const Duration(microseconds: NeonAsteroidsGame.fixedStepMicros),
        const NeonAsteroidsInput(),
      );

      expect(game.ship.position.x, lessThan(1));
      expect(game.ship.position.y, lessThan(1));
      expect(game.asteroids.single.position.x, greaterThan(119));
      expect(game.asteroids.single.position.y, greaterThan(59));
    });

    test('thrust particles spawn inside the wrapped playfield', () {
      final game = NeonAsteroidsGame(
        seed: 37,
        width: 120,
        height: 60,
        populate: false,
      )..start(spawnWave: false);
      game.ship
        ..position.x = 0.5
        ..position.y = 30
        ..angle = 0;

      game.advance(
        const Duration(microseconds: NeonAsteroidsGame.fixedStepMicros * 2),
        const NeonAsteroidsInput(thrust: true),
      );

      expect(game.particles, isNotEmpty);
      expect(
        game.particles.every(
          (particle) =>
              particle.position.x >= 0 &&
              particle.position.x < game.width &&
              particle.position.y >= 0 &&
              particle.position.y < game.height,
        ),
        isTrue,
      );
    });

    test(
      'pause discards wall time and resize preserves normalized positions',
      () {
        final game = _controlledGame();
        game.advance(
          const Duration(milliseconds: 100),
          const NeonAsteroidsInput(thrust: true),
        );
        game.togglePause();
        final beforePause = _snapshot(game);
        expect(
          game.advance(
            const Duration(seconds: 5),
            const NeonAsteroidsInput(thrust: true, fire: true),
          ),
          0,
        );
        expect(_snapshot(game), beforePause);
        game.togglePause();
        game.advance(
          const Duration(milliseconds: 20),
          const NeonAsteroidsInput(),
        );
        expect(
          game.bullets,
          isEmpty,
          reason: 'paused fire input was discarded',
        );

        final normalizedX = game.ship.position.x / game.width;
        final normalizedY = game.ship.position.y / game.height;
        game.resize(game.width * 1.5, game.height * 0.75);
        expect(game.ship.position.x / game.width, closeTo(normalizedX, 1e-12));
        expect(game.ship.position.y / game.height, closeTo(normalizedY, 1e-12));
      },
    );
  });

  group('NeonAsteroidsApp', () {
    const viewport = CellSize(100, 30);

    testWidgets(
      'renders an animated attract screen and keyboard-driven game states',
      (tester) {
        tester.pumpWidget(const NeonAsteroidsApp());
        tester.pump(const Duration(milliseconds: 500));
        var output = tester.renderToString(size: viewport);
        expect(output, contains('NEON // ASTEROIDS'));
        expect(output, contains('ATTRACT'));
        expect(output, contains('SPACE / ENTER TO LAUNCH'));
        expect(output, contains('● LIVE'));

        // The live Canvas sits directly behind this animated card. Keep the
        // opaque frame outside Reveal: during live fade/reveal progress,
        // background-only spaces can be dropped or masked and expose braille
        // playfield pixels. Only the card's inner content animates.
        final lines = output.split('\n');
        final vectorRow = lines.indexWhere(
          (line) => line.contains('VECTOR FLIGHT / TOROIDAL SECTOR'),
        );
        expect(vectorRow, greaterThanOrEqualTo(0));
        final left = lines[vectorRow].indexOf('│');
        final right = lines[vectorRow].lastIndexOf('│');
        expect(
          lines[vectorRow + 1].substring(left, right + 1),
          '│${List<String>.filled(right - left - 1, ' ').join()}│',
        );
        final buffer = tester.render(size: viewport);
        for (var col = left + 1; col < right; col++) {
          expect(
            buffer.atColRow(col, vectorRow + 1).style.background,
            const RgbColor(0x0B, 0x0F, 0x14),
            reason: 'the settled overlay must cover the live Canvas at $col',
          );
        }

        tester.sendKey(const KeyEvent(KeyCode.space));
        output = tester.renderToString(size: viewport);
        expect(output, contains('WAVE 01'));
        expect(output, contains('LIVES ◇◇◇'));
        expect(output, contains('SCORE 000000'));

        tester.type('p'); // real terminals deliver bare printables as text
        expect(tester.renderToString(size: viewport), contains('PAUSED'));
        tester.type('p');
        expect(tester.renderToString(size: viewport), contains('WAVE 01'));

        tester.type('r');
        output = tester.renderToString(size: viewport);
        expect(output, contains('SCORE 000000'));
        expect(output, contains('WAVE 01'));
      },
      viewportSize: viewport,
    );

    testWidgets(
      'semantic start action launches the same state transition as input',
      (tester) async {
        tester.pumpWidget(const NeonAsteroidsApp());
        tester.render(size: viewport);

        await tester.invokeSemanticAction(
          SemanticAction.start,
          role: SemanticRole.region,
          label: 'Neon Asteroids game',
        );

        expect(tester.renderToString(size: viewport), contains('WAVE 01'));
      },
      viewportSize: viewport,
    );

    testWidgets(
      'clicking the paused playfield resumes without resetting the run',
      (tester) {
        tester.pumpWidget(const NeonAsteroidsApp());
        tester.sendKey(const KeyEvent(KeyCode.space));
        tester.pump(const Duration(milliseconds: 250));
        final beforePause = tester.renderToString(size: viewport);

        tester.type('p');
        expect(tester.renderToString(size: viewport), contains('PAUSED'));
        final playfield = tester.semantics().single(
          role: SemanticRole.region,
          label: 'Neon Asteroids game',
        );
        final bounds = playfield.bounds!;
        final col = bounds.left + bounds.size.cols ~/ 2;
        final row = bounds.top + bounds.size.rows ~/ 2;
        tester.sendMouse(
          MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: col,
            row: row,
          ),
        );
        tester.sendMouse(
          MouseEvent(
            kind: MouseEventKind.up,
            button: MouseButton.left,
            col: col,
            row: row,
          ),
        );

        expect(tester.renderToString(size: viewport), beforePause);
      },
      viewportSize: viewport,
    );

    testWidgets(
      'compact layout keeps controls discoverable after a live resize',
      (tester) {
        tester.pumpWidget(const NeonAsteroidsApp());
        tester.viewportSize = const CellSize(54, 16);

        final output = tester.renderToString();
        expect(output, contains('ASTEROIDS'));
        expect(output, contains('A/D TURN'));
        expect(output, contains('SPACE FIRE'));

        tester.viewportSize = const CellSize(42, 12);
        final tinyOutput = tester.renderToString();
        expect(tinyOutput, contains('ASTRO'));
        expect(tinyOutput, contains('A/D  W  SPACE  P'));
      },
      viewportSize: viewport,
    );

    testWidgets(
      'disabled decorative animation does not disable game physics',
      (tester) {
        tester.pumpWidget(const NeonAsteroidsApp());
        expect(
          tester.scheduler.activeTickerCount,
          0,
          reason: 'disabled attract mode must be static and idle',
        );
        tester.sendKey(const KeyEvent(KeyCode.space));
        expect(
          tester.scheduler.activeTickerCount,
          1,
          reason: 'functional gameplay keeps its fixed-step ticker',
        );
        tester.pump(const Duration(milliseconds: 100));
        final before = tester.renderToString(size: viewport);
        tester.pump(const Duration(milliseconds: 100));
        final after = tester.renderToString(size: viewport);

        expect(after, contains('MOTION REDUCED'));
        expect(after, contains('WAVE 01'));
        expect(after, isNot(before), reason: 'asteroid physics still advances');
      },
      animationPolicy: AnimationPolicy.disabled,
      viewportSize: viewport,
    );
  });
}

NeonAsteroidsGame _controlledGame() {
  final game = NeonAsteroidsGame(
    seed: 99,
    width: 120,
    height: 60,
    populate: false,
  )..start(spawnWave: false);
  game.asteroids.add(
    NeonAsteroid(
      id: 700,
      position: NeonVector(105, 48),
      velocity: NeonVector(0.5, -0.25),
      radius: 4,
      tier: 1,
      spin: 0.1,
    ),
  );
  return game;
}

String _snapshot(NeonAsteroidsGame game) {
  String number(double value) => value.toStringAsFixed(12);
  final asteroidState = game.asteroids
      .map(
        (asteroid) =>
            '${asteroid.id}:${number(asteroid.position.x)},'
            '${number(asteroid.position.y)},${number(asteroid.angle)}',
      )
      .join('|');
  final bulletState = game.bullets
      .map(
        (bullet) =>
            '${number(bullet.position.x)},${number(bullet.position.y)},'
            '${bullet.lifeTicks}',
      )
      .join('|');
  return <Object>[
    game.phase.name,
    game.tickCount,
    game.score,
    game.lives,
    number(game.ship.position.x),
    number(game.ship.position.y),
    number(game.ship.velocity.x),
    number(game.ship.velocity.y),
    number(game.ship.angle),
    asteroidState,
    bulletState,
    game.particles.length,
  ].join(';');

  group('NeonAsteroids input (RFC 0020 sampled controls)', () {
    testWidgets('the app mounts and accepts sampled held keys', (tester) async {
      // A smoke test over the real widget: the rewrite reads its controls
      // from Keyboard.snapshot inside the ticker, so a held key must flow
      // all the way through without throwing (the sampled read asserts if
      // it is ever performed during build).
      tester.keyboardCapabilities = KeyboardCapabilities.full;
      tester.pumpWidget(const NeonAsteroidsApp());
      tester.pump();
      tester.sendKey(const KeyEvent(KeyCode.enter));
      tester.pump(const Duration(milliseconds: 16));

      tester.holdKey(KeyPosition.w);
      tester.pump(const Duration(milliseconds: 200));
      tester.releaseKey(KeyPosition.w);
      tester.pump(const Duration(milliseconds: 200));

      expect(tester.renderToString(), isNotEmpty);
    });

    test('thrust is independent of key-repeat cadence', () {
      // The regression the 170ms latch caused: turn/thrust rate tracked the
      // user's OS auto-repeat setting, so the game played differently on
      // different machines. Sampled state is level-triggered, so the same
      // held input produces the same physics regardless of how many key
      // events the terminal happened to deliver.
      final a = NeonAsteroidsGame()..start();
      final b = NeonAsteroidsGame()..start();
      const held = NeonAsteroidsInput(thrust: true);
      for (var i = 0; i < 30; i++) {
        a.advanceWithTimeline(const Duration(milliseconds: 16), (_) => held);
      }
      // Same total time, different frame cadence.
      for (var i = 0; i < 10; i++) {
        b.advanceWithTimeline(const Duration(milliseconds: 48), (_) => held);
      }
      expect(a.ship.position.x, closeTo(b.ship.position.x, 1e-6));
      expect(a.ship.position.y, closeTo(b.ship.position.y, 1e-6));
    });
  });
}
