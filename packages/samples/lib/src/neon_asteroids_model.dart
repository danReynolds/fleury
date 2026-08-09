import 'dart:math' as math;

/// The top-level state of a [NeonAsteroidsGame].
enum NeonAsteroidsPhase { attract, playing, paused, gameOver }

/// Continuous controls sampled by the fixed-step simulation.
///
/// [fire] is edge-triggered: one `true` value queues one shot even when a
/// delayed rendered frame expands into several physics steps.
class NeonAsteroidsInput {
  const NeonAsteroidsInput({
    this.rotateLeft = false,
    this.rotateRight = false,
    this.thrust = false,
    this.brake = false,
    this.fire = false,
  });

  final bool rotateLeft;
  final bool rotateRight;
  final bool thrust;

  /// Retro-thrust. Classic asteroids has no brake — you turn 180° and burn —
  /// which reads as "the controls are broken" to anyone who has not played
  /// the 1979 cabinet. Held, it bleeds off speed regardless of heading.
  final bool brake;

  final bool fire;

  NeonAsteroidsInput copyWith({
    bool? rotateLeft,
    bool? rotateRight,
    bool? thrust,
    bool? brake,
    bool? fire,
  }) => NeonAsteroidsInput(
    rotateLeft: rotateLeft ?? this.rotateLeft,
    rotateRight: rotateRight ?? this.rotateRight,
    thrust: thrust ?? this.thrust,
    brake: brake ?? this.brake,
    fire: fire ?? this.fire,
  );
}

/// Mutable two-dimensional value used by the deliberately small game model.
class NeonVector {
  NeonVector(this.x, this.y);

  double x;
  double y;

  NeonVector copy() => NeonVector(x, y);
}

/// The player ship.
class NeonShip {
  NeonShip({
    required this.position,
    required this.velocity,
    this.angle = math.pi / 2,
    this.shieldTicks = 0,
  });

  final NeonVector position;
  final NeonVector velocity;
  double angle;
  int shieldTicks;
}

/// One asteroid. [tier] is `3` for large, `2` for medium, and `1` for small.
class NeonAsteroid {
  NeonAsteroid({
    required this.id,
    required this.position,
    required this.velocity,
    required this.radius,
    required this.tier,
    this.angle = 0,
    this.spin = 0,
  }) : assert(tier >= 1 && tier <= 3);

  final int id;
  final NeonVector position;
  final NeonVector velocity;
  final double radius;
  final int tier;
  double angle;
  final double spin;
}

/// One projectile, including its previous point for short rendered trails.
class NeonBullet {
  NeonBullet({
    required this.position,
    required this.velocity,
    required this.lifeTicks,
  }) : previous = position.copy();

  final NeonVector position;
  final NeonVector previous;
  final NeonVector velocity;
  int lifeTicks;
}

/// A short-lived collision/thrust spark.
///
/// Particles never participate in physics or consume randomness conditionally
/// on animation policy. Reduced-motion rendering can omit them without changing
/// a subsequent simulation result.
class NeonParticle {
  NeonParticle({
    required this.position,
    required this.velocity,
    required this.lifeTicks,
    required this.maxLifeTicks,
  });

  final NeonVector position;
  final NeonVector velocity;
  int lifeTicks;
  final int maxLifeTicks;
}

/// Deterministic, fixed-step Asteroids simulation used by the showcase.
///
/// Wall-clock deltas are accumulated as integer microseconds and expanded into
/// 120 Hz physics ticks. A delayed rendered frame therefore runs the same small
/// collision steps as ordinary frames instead of moving bullets directly from
/// one rendered position to the next. A one-second catch-up ceiling prevents a
/// backgrounded browser tab from monopolising the UI thread; retained time is
/// still fully sub-stepped, so the safe degradation is slow motion, not
/// tunnelling.
class NeonAsteroidsGame {
  NeonAsteroidsGame({
    int seed = 0xF1E7,
    this.width = 160,
    this.height = 88,
    bool populate = true,
  }) : assert(width > 0),
       assert(height > 0),
       _seed = seed,
       _random = math.Random(seed),
       ship = NeonShip(
         position: NeonVector(width / 2, height / 2),
         velocity: NeonVector(0, 0),
       ) {
    if (populate) {
      _spawnWave(count: 6, safeCenter: false);
    }
  }

  /// Physics cadence. Rendering may run at any cadence.
  static const int fixedStepMicros = 8333;
  static const double fixedDt = 1 / 120;
  static const int maxCatchUpMicros = 1000000;

  static const double _turnSpeed = 3.7;

  /// Per fixed step. Strong enough to feel immediate, gentle enough that the
  /// ship coasts to rest rather than stopping dead.
  static const double _brakeDamping = 0.94;
  static const double _thrustAcceleration = 27;
  static const double _bulletSpeed = 68;
  static const int _bulletLifeTicks = 150;
  static const int _shotCooldownTicks = 13;
  static const int _respawnShieldTicks = 240;

  final int _seed;
  math.Random _random;

  double width;
  double height;
  final NeonShip ship;
  final List<NeonAsteroid> asteroids = <NeonAsteroid>[];
  final List<NeonBullet> bullets = <NeonBullet>[];
  final List<NeonParticle> particles = <NeonParticle>[];

  NeonAsteroidsPhase phase = NeonAsteroidsPhase.attract;
  int score = 0;
  int lives = 3;
  int wave = 0;
  int tickCount = 0;
  int lastScoreDelta = 0;
  int scoreEvent = 0;
  int impactEvent = 0;

  int _accumulatorMicros = 0;
  int _nextAsteroidId = 1;
  int _shotCooldown = 0;
  bool _fireQueued = false;
  bool _thrusting = false;

  /// Whether the last physics step applied thrust; useful to render the flame.
  bool get thrusting => _thrusting;

  /// Simulation time, independent of render cadence.
  Duration get simulationTime =>
      Duration(microseconds: tickCount * fixedStepMicros);

  /// Starts a fresh run.
  ///
  /// [spawnWave] exists so focused model tests can install a tiny explicit
  /// scenario; the app always uses the default.
  void start({bool spawnWave = true}) {
    _resetRun();
    phase = NeonAsteroidsPhase.playing;
    if (spawnWave) {
      _spawnWave(count: 5, safeCenter: true);
      wave = 1;
    }
  }

  void restart() => start();

  void togglePause() {
    if (phase == NeonAsteroidsPhase.playing) {
      phase = NeonAsteroidsPhase.paused;
    } else if (phase == NeonAsteroidsPhase.paused) {
      phase = NeonAsteroidsPhase.playing;
    }
  }

  /// Changes the toroidal playfield while preserving normalized positions.
  void resize(double newWidth, double newHeight) {
    if (newWidth <= 0 || newHeight <= 0) return;
    if (newWidth == width && newHeight == height) return;
    final sx = newWidth / width;
    final sy = newHeight / height;
    ship.position
      ..x *= sx
      ..y *= sy;
    for (final asteroid in asteroids) {
      asteroid.position
        ..x *= sx
        ..y *= sy;
    }
    for (final bullet in bullets) {
      bullet.position
        ..x *= sx
        ..y *= sy;
      bullet.previous
        ..x *= sx
        ..y *= sy;
    }
    for (final particle in particles) {
      particle.position
        ..x *= sx
        ..y *= sy;
    }
    width = newWidth;
    height = newHeight;
  }

  /// Advances by [elapsed], expanding it into deterministic fixed steps.
  ///
  /// Returns the number of simulated ticks. Paused games discard elapsed time
  /// so resuming never produces a catch-up jump.
  int advance(Duration elapsed, NeonAsteroidsInput input) {
    if (phase == NeonAsteroidsPhase.paused) {
      _accumulatorMicros = 0;
      return 0;
    }
    if (input.fire) _fireQueued = true;
    return _advanceWith(elapsed, (_) => input.copyWith(fire: false));
  }

  /// Internal timeline-sampling lane used by the widget's short key latches.
  ///
  /// Sampling for every fixed tick ensures a long rendered frame cannot turn a
  /// brief key press into a long burn. Tests use [advance], whose constant
  /// input goes through the exact same integrator.
  int advanceWithTimeline(
    Duration elapsed,
    NeonAsteroidsInput Function(Duration simulationTime) inputAt,
  ) => _advanceWith(elapsed, (micros) {
    final input = inputAt(Duration(microseconds: micros));
    if (input.fire) _fireQueued = true;
    return input.copyWith(fire: false);
  });

  int _advanceWith(
    Duration elapsed,
    NeonAsteroidsInput Function(int simulationMicros) inputAt,
  ) {
    if (phase == NeonAsteroidsPhase.paused) {
      _accumulatorMicros = 0;
      return 0;
    }
    final incoming = elapsed.inMicroseconds.clamp(0, maxCatchUpMicros);
    _accumulatorMicros += incoming;
    var steps = 0;
    while (_accumulatorMicros >= fixedStepMicros) {
      final input = inputAt(tickCount * fixedStepMicros);
      _tick(input);
      _accumulatorMicros -= fixedStepMicros;
      steps++;
    }
    return steps;
  }

  void _tick(NeonAsteroidsInput input) {
    tickCount++;
    _tickParticles();

    if (phase == NeonAsteroidsPhase.attract) {
      ship.angle = _normalAngle(ship.angle + fixedDt * 0.55);
      for (final asteroid in asteroids) {
        _moveAsteroid(asteroid);
      }
      return;
    }
    if (phase == NeonAsteroidsPhase.gameOver) {
      ship.angle = _normalAngle(ship.angle + fixedDt * 0.28);
      for (final asteroid in asteroids) {
        _moveAsteroid(asteroid);
      }
      return;
    }
    if (phase != NeonAsteroidsPhase.playing) return;

    _thrusting = input.thrust;
    final turn = (input.rotateLeft ? 1 : 0) - (input.rotateRight ? 1 : 0);
    ship.angle = _normalAngle(ship.angle + turn * _turnSpeed * fixedDt);

    if (input.thrust) {
      ship.velocity
        ..x += math.cos(ship.angle) * _thrustAcceleration * fixedDt
        ..y += math.sin(ship.angle) * _thrustAcceleration * fixedDt;
      if (tickCount.isEven) _spawnThrustParticle();
    }

    // Retro-thrust bleeds speed off along the current velocity, so it slows
    // you without needing to point anywhere particular.
    if (input.brake) {
      ship.velocity
        ..x *= _brakeDamping
        ..y *= _brakeDamping;
    }

    // Per-second drag expressed at the fixed cadence.
    ship.velocity
      ..x *= 0.9975
      ..y *= 0.9975;
    ship.position
      ..x += ship.velocity.x * fixedDt
      ..y += ship.velocity.y * fixedDt;
    _wrap(ship.position);

    if (_shotCooldown > 0) _shotCooldown--;
    if (ship.shieldTicks > 0) ship.shieldTicks--;
    if (_fireQueued && _shotCooldown == 0) {
      _fireQueued = false;
      _fire();
    }

    for (final asteroid in asteroids) {
      _moveAsteroid(asteroid);
    }
    _moveBulletsAndCollide();
    _collideShip();

    if (phase == NeonAsteroidsPhase.playing && asteroids.isEmpty) {
      wave++;
      _spawnWave(count: math.min(4 + wave, 10), safeCenter: true);
    }
  }

  void _moveAsteroid(NeonAsteroid asteroid) {
    asteroid.position
      ..x += asteroid.velocity.x * fixedDt
      ..y += asteroid.velocity.y * fixedDt;
    asteroid.angle = _normalAngle(asteroid.angle + asteroid.spin * fixedDt);
    _wrap(asteroid.position);
  }

  void _moveBulletsAndCollide() {
    for (
      var bulletIndex = bullets.length - 1;
      bulletIndex >= 0;
      bulletIndex--
    ) {
      final bullet = bullets[bulletIndex];
      bullet.previous
        ..x = bullet.position.x
        ..y = bullet.position.y;
      final endX = bullet.position.x + bullet.velocity.x * fixedDt;
      final endY = bullet.position.y + bullet.velocity.y * fixedDt;

      var hitIndex = -1;
      for (
        var asteroidIndex = asteroids.length - 1;
        asteroidIndex >= 0;
        asteroidIndex--
      ) {
        if (_segmentHitsWrappedCircle(
          bullet.position.x,
          bullet.position.y,
          endX,
          endY,
          asteroids[asteroidIndex],
        )) {
          hitIndex = asteroidIndex;
          break;
        }
      }

      bullet.position
        ..x = endX
        ..y = endY;
      _wrap(bullet.position);
      bullet.lifeTicks--;

      if (hitIndex >= 0) {
        bullets.removeAt(bulletIndex);
        _destroyAsteroid(hitIndex, awardScore: true);
      } else if (bullet.lifeTicks <= 0) {
        bullets.removeAt(bulletIndex);
      }
    }
  }

  bool _segmentHitsWrappedCircle(
    double x1,
    double y1,
    double x2,
    double y2,
    NeonAsteroid asteroid,
  ) {
    // Check the 3×3 toroidal images around the segment. This also handles a
    // shot crossing an edge during one fixed step without constructing a long
    // wrapped chord across the whole playfield.
    for (final ox in <double>[-width, 0, width]) {
      for (final oy in <double>[-height, 0, height]) {
        final cx = asteroid.position.x + ox;
        final cy = asteroid.position.y + oy;
        if (_segmentDistanceSquared(x1, y1, x2, y2, cx, cy) <=
            asteroid.radius * asteroid.radius) {
          return true;
        }
      }
    }
    return false;
  }

  static double _segmentDistanceSquared(
    double x1,
    double y1,
    double x2,
    double y2,
    double px,
    double py,
  ) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) {
      final ex = px - x1;
      final ey = py - y1;
      return ex * ex + ey * ey;
    }
    final t = (((px - x1) * dx + (py - y1) * dy) / lengthSquared).clamp(
      0.0,
      1.0,
    );
    final ex = px - (x1 + dx * t);
    final ey = py - (y1 + dy * t);
    return ex * ex + ey * ey;
  }

  void _collideShip() {
    if (ship.shieldTicks > 0) return;
    for (var i = asteroids.length - 1; i >= 0; i--) {
      final asteroid = asteroids[i];
      final dx = _wrappedDelta(ship.position.x - asteroid.position.x, width);
      final dy = _wrappedDelta(ship.position.y - asteroid.position.y, height);
      final hitRadius = asteroid.radius + 2.5;
      if (dx * dx + dy * dy > hitRadius * hitRadius) continue;

      _spawnBurst(ship.position, count: 12);
      impactEvent++;
      lives--;
      _destroyAsteroid(i, awardScore: false);
      bullets.clear();
      if (lives <= 0) {
        phase = NeonAsteroidsPhase.gameOver;
        _thrusting = false;
      } else {
        ship.position
          ..x = width / 2
          ..y = height / 2;
        ship.velocity
          ..x = 0
          ..y = 0;
        ship.angle = math.pi / 2;
        ship.shieldTicks = _respawnShieldTicks;
      }
      return;
    }
  }

  void _fire() {
    final cosAngle = math.cos(ship.angle);
    final sinAngle = math.sin(ship.angle);
    bullets.add(
      NeonBullet(
        position: NeonVector(
          ship.position.x + cosAngle * 3.2,
          ship.position.y + sinAngle * 3.2,
        ),
        velocity: NeonVector(
          ship.velocity.x + cosAngle * _bulletSpeed,
          ship.velocity.y + sinAngle * _bulletSpeed,
        ),
        lifeTicks: _bulletLifeTicks,
      ),
    );
    _shotCooldown = _shotCooldownTicks;
  }

  void _destroyAsteroid(int index, {required bool awardScore}) {
    final asteroid = asteroids.removeAt(index);
    _spawnBurst(asteroid.position, count: 3 + asteroid.tier * 3);

    if (awardScore) {
      lastScoreDelta = switch (asteroid.tier) {
        3 => 20,
        2 => 50,
        _ => 100,
      };
      score += lastScoreDelta;
      scoreEvent++;
    }

    if (asteroid.tier == 1) return;
    final childTier = asteroid.tier - 1;
    final childRadius = asteroid.radius * 0.58;
    final baseAngle = math.atan2(asteroid.velocity.y, asteroid.velocity.x);
    for (final sign in <int>[-1, 1]) {
      final angle = baseAngle + sign * (0.7 + _random.nextDouble() * 0.18);
      final speed =
          math.sqrt(
            asteroid.velocity.x * asteroid.velocity.x +
                asteroid.velocity.y * asteroid.velocity.y,
          ) +
          4 +
          _random.nextDouble() * 3;
      asteroids.add(
        NeonAsteroid(
          id: _nextAsteroidId++,
          position: asteroid.position.copy(),
          velocity: NeonVector(
            math.cos(angle) * speed,
            math.sin(angle) * speed,
          ),
          radius: childRadius,
          tier: childTier,
          angle: asteroid.angle + sign * 0.4,
          spin: -asteroid.spin + sign * (0.25 + _random.nextDouble() * 0.3),
        ),
      );
    }
  }

  void _spawnWave({required int count, required bool safeCenter}) {
    for (var i = 0; i < count; i++) {
      var x = _random.nextDouble() * width;
      var y = _random.nextDouble() * height;
      if (safeCenter) {
        var attempts = 0;
        while (_distanceSquared(x, y, width / 2, height / 2) <
                math.pow(math.min(width, height) * 0.24, 2) &&
            attempts < 12) {
          x = _random.nextDouble() * width;
          y = _random.nextDouble() * height;
          attempts++;
        }
      }
      final angle = _random.nextDouble() * math.pi * 2;
      final speed = 5.5 + _random.nextDouble() * 5.5;
      asteroids.add(
        NeonAsteroid(
          id: _nextAsteroidId++,
          position: NeonVector(x, y),
          velocity: NeonVector(
            math.cos(angle) * speed,
            math.sin(angle) * speed,
          ),
          radius: 7.5 + _random.nextDouble() * 2.5,
          tier: 3,
          angle: _random.nextDouble() * math.pi * 2,
          spin: (_random.nextDouble() - 0.5) * 0.75,
        ),
      );
    }
  }

  void _spawnThrustParticle() {
    final backwards = ship.angle + math.pi;
    final jitter = (_random.nextDouble() - 0.5) * 0.35;
    final speed = 10 + _random.nextDouble() * 8;
    final position = NeonVector(
      ship.position.x + math.cos(backwards) * 2.2,
      ship.position.y + math.sin(backwards) * 2.2,
    );
    _wrap(position);
    particles.add(
      NeonParticle(
        position: position,
        velocity: NeonVector(
          ship.velocity.x + math.cos(backwards + jitter) * speed,
          ship.velocity.y + math.sin(backwards + jitter) * speed,
        ),
        lifeTicks: 22,
        maxLifeTicks: 22,
      ),
    );
    _trimParticles();
  }

  void _spawnBurst(NeonVector origin, {required int count}) {
    for (var i = 0; i < count; i++) {
      final angle = _random.nextDouble() * math.pi * 2;
      final speed = 5 + _random.nextDouble() * 18;
      final life = 22 + _random.nextInt(28);
      particles.add(
        NeonParticle(
          position: origin.copy(),
          velocity: NeonVector(
            math.cos(angle) * speed,
            math.sin(angle) * speed,
          ),
          lifeTicks: life,
          maxLifeTicks: life,
        ),
      );
    }
    _trimParticles();
  }

  void _tickParticles() {
    for (var i = particles.length - 1; i >= 0; i--) {
      final particle = particles[i];
      particle.position
        ..x += particle.velocity.x * fixedDt
        ..y += particle.velocity.y * fixedDt;
      particle.velocity
        ..x *= 0.985
        ..y *= 0.985;
      _wrap(particle.position);
      particle.lifeTicks--;
      if (particle.lifeTicks <= 0) particles.removeAt(i);
    }
  }

  void _trimParticles() {
    const limit = 90;
    if (particles.length > limit) {
      particles.removeRange(0, particles.length - limit);
    }
  }

  void _resetRun() {
    _random = math.Random(_seed);
    asteroids.clear();
    bullets.clear();
    particles.clear();
    score = 0;
    lives = 3;
    wave = 0;
    tickCount = 0;
    lastScoreDelta = 0;
    scoreEvent = 0;
    impactEvent = 0;
    _accumulatorMicros = 0;
    _nextAsteroidId = 1;
    _shotCooldown = 0;
    _fireQueued = false;
    _thrusting = false;
    ship
      ..angle = math.pi / 2
      ..shieldTicks = _respawnShieldTicks;
    ship.position
      ..x = width / 2
      ..y = height / 2;
    ship.velocity
      ..x = 0
      ..y = 0;
  }

  void _wrap(NeonVector point) {
    point
      ..x = _wrapValue(point.x, width)
      ..y = _wrapValue(point.y, height);
  }

  static double _wrapValue(double value, double extent) {
    var result = value % extent;
    if (result < 0) result += extent;
    return result;
  }

  static double _wrappedDelta(double delta, double extent) {
    if (delta > extent / 2) return delta - extent;
    if (delta < -extent / 2) return delta + extent;
    return delta;
  }

  static double _normalAngle(double value) {
    final full = math.pi * 2;
    var angle = value % full;
    if (angle < 0) angle += full;
    return angle;
  }

  static double _distanceSquared(double x1, double y1, double x2, double y2) {
    final dx = x1 - x2;
    final dy = y1 - y2;
    return dx * dx + dy * dy;
  }
}
