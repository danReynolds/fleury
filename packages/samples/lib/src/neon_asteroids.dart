import 'dart:math' as math;

import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

import 'neon_asteroids_model.dart';
import 'scaffold.dart';

const _void = RgbColor(0x0B, 0x0F, 0x14);
const _cyan = RgbColor(0x45, 0xE8, 0xF2);
const _cyanDim = RgbColor(0x25, 0x78, 0x87);
const _violet = RgbColor(0xB2, 0x7A, 0xFF);
const _violetDim = RgbColor(0x62, 0x43, 0x91);
const _coral = RgbColor(0xFF, 0x6B, 0x7A);
const _amber = RgbColor(0xFF, 0xD1, 0x66);
const _starBright = RgbColor(0x70, 0x91, 0xA8);
const _starDim = RgbColor(0x2C, 0x3C, 0x4A);

/// A real-time, browser-safe Asteroids showcase built entirely from Fleury
/// cells and public animation/input APIs.
class NeonAsteroidsApp extends StatelessWidget {
  const NeonAsteroidsApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const SampleScaffold(child: _NeonAsteroidsBody());
}

class _NeonAsteroidsBody extends StatefulWidget {
  const _NeonAsteroidsBody();

  @override
  State<_NeonAsteroidsBody> createState() => _NeonAsteroidsBodyState();
}

class _NeonAsteroidsBodyState extends State<_NeonAsteroidsBody> {
  // Movement is SPATIAL: the hand shape is the design, so these are physical
  // positions. On AZERTY the W spot is capped Z and the number row is
  // unshifted — declaring them logically would put "thrust" under the wrong
  // finger. Fire/pause/restart are MNEMONIC (the player reads them in the
  // control legend), so those stay logical keys.
  static const _thrustKey = KeyPosition.w;
  static const _leftKey = KeyPosition.a;
  static const _rightKey = KeyPosition.d;

  final NeonAsteroidsGame _game = NeonAsteroidsGame();
  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;
  AnimationPolicy _motionPolicy = AnimationPolicy.enabled;

  /// The surface keyboard, sampled once per simulation frame. Resolved in
  /// [didChangeDependencies] — where inherited lookups belong — so it is
  /// non-null by the time any tick runs, and re-resolves if capabilities
  /// change. The handle itself is stable for the app's lifetime (§15).
  late Keyboard _keyboard;

  /// Pointer-driven controls. The keyboard is one SOURCE of input, not the
  /// game's input model — aiming and firing by mouse feed the same channel.
  bool _pointerThrust = false;
  bool _pointerFire = false;

  /// Legacy fallback: where the surface cannot report held keys, thrust is a
  /// toggle rather than a hold (see [_supportsHeldControls]).
  bool _thrustLatched = false;

  bool get _reducedMotion => _motionPolicy != AnimationPolicy.enabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final binding = TuiBinding.of(context);
    _motionPolicy = binding.animationPolicy;
    _keyboard = Keyboard.of(context);

    // Gameplay is functional, not decorative, so it keeps its fixed-step clock
    // even when animation is disabled. Attract/game-over motion is decorative
    // and stays still under reduced/disabled policies. TickerMode still
    // suspends a hidden route. Reveal/Animate independently obey the policy.
    final ticker = _ticker ??= binding.createTicker(_onTick);
    final tickerModeEnabled = TickerMode.of(context);
    if (ticker.muted && tickerModeEnabled) {
      // A muted ticker keeps its own elapsed clock current. Re-anchor our
      // frame delta before unmuting so a hidden route does not catch up.
      _lastElapsed = ticker.lastElapsed;
    }
    ticker.muted = !tickerModeEnabled;
    final shouldRun =
        tickerModeEnabled &&
        _game.phase != NeonAsteroidsPhase.paused &&
        (_game.phase == NeonAsteroidsPhase.playing || !_reducedMotion);
    if (!ticker.isActive && shouldRun) {
      _lastElapsed = Duration.zero;
      ticker.start();
    } else if (ticker.isActive && !shouldRun) {
      ticker.stop();
    }

    final size = MediaQuery.sizeOf(context);
    final playRows = math.max(8, size.rows - 4);
    _game.resize(
      math.max(64, size.cols * 2).toDouble(),
      math.max(32, playRows * 4).toDouble(),
    );
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    if (delta <= Duration.zero) return;

    // One immutable read for the whole frame, so every fixed simulation step
    // below agrees about what was held (RFC 0020 §5.6).
    final keys = _keyboard.snapshot;
    final left = keys.isHeld(_leftKey) || keys.isHeld(KeyCode.arrowLeft);
    final right = keys.isHeld(_rightKey) || keys.isHeld(KeyCode.arrowRight);
    final thrust =
        keys.isHeld(_thrustKey) ||
        keys.isHeld(KeyCode.arrowUp) ||
        _thrustLatched ||
        _pointerThrust;

    // An EDGE, not a level: `wasPressed` survives a press+release that lands
    // entirely between two frames, so a quick tap is never swallowed — and it
    // is consumed at exactly one simulation step, so one press is one shot.
    var fire = keys.wasPressed(KeyCode.space) || _pointerFire;
    _pointerFire = false;
    final steps = _game.advanceWithTimeline(delta, (_) {
      final shoot = fire;
      fire = false;
      return NeonAsteroidsInput(
        rotateLeft: left,
        rotateRight: right,
        thrust: thrust,
        fire: shoot,
      );
    });
    if (_reducedMotion && _game.phase == NeonAsteroidsPhase.gameOver) {
      _ticker?.stop();
    }
    if (steps > 0 && mounted) setState(() {});
  }

  /// The discrete actions. Movement is NOT here — it is sampled in
  /// [_onTick], because "is it held right now" is a state question, not an
  /// event one.
  List<KeyBinding> _bindings() => [
    KeyBinding(KeyCode.space, label: 'Fire', onTrigger: (_) => _launchOrFire()),
    KeyBinding(
      KeyCode.enter,
      hideFromHintBar: true,
      onTrigger: (_) {
        if (_game.phase == NeonAsteroidsPhase.attract ||
            _game.phase == NeonAsteroidsPhase.gameOver) {
          _start();
        }
      },
    ),
    KeyBinding(
      KeyCode.p,
      aliases: [KeyCode.escape],
      label: 'Pause',
      onTrigger: (_) => _togglePause(),
    ),
    KeyBinding(KeyCode.r, label: 'Restart', onTrigger: (_) => _start()),
    // Legacy surfaces only: thrust becomes a toggle, because hold-to-thrust
    // while turning is impossible there. The capability read is reactive, so
    // this appears if a surface negotiates down mid-session.
    if (!_supportsHeldControls)
      KeyBinding(
        // The same positional identity the sampled control uses. Where the
        // surface reports no positions it degrades to the US twin, so one
        // declaration covers both worlds (§13.3).
        _thrustKey,
        label: 'Thrust',
        onTrigger: (_) => setState(() => _thrustLatched = !_thrustLatched),
      ),
  ];

  /// Whether this surface reports real held keys. Where it does not (a
  /// legacy terminal), holding two directions at once is impossible — the OS
  /// only auto-repeats the most recent key — so the game offers a DIFFERENT
  /// control scheme rather than a worse version of the same one.
  bool get _supportsHeldControls => _keyboard.capabilities.supportsHeldState;

  void _clearControls() {
    _pointerThrust = false;
    _pointerFire = false;
    _thrustLatched = false;
  }

  void _start() {
    setState(() {
      _clearControls();
      _game.start();
      _resumeTicker();
    });
  }

  void _launchOrFire() {
    if (_game.phase == NeonAsteroidsPhase.attract ||
        _game.phase == NeonAsteroidsPhase.gameOver) {
      _start();
    } else if (_game.phase == NeonAsteroidsPhase.playing) {
      // Fire is edge-triggered from the snapshot during play; this path is
      // the pointer/semantic-action entry point.
      _pointerFire = true;
    }
  }

  void _togglePause() {
    if (_game.phase != NeonAsteroidsPhase.playing &&
        _game.phase != NeonAsteroidsPhase.paused) {
      return;
    }
    setState(() {
      _clearControls();
      _game.togglePause();
      final ticker = _ticker;
      if (_game.phase == NeonAsteroidsPhase.paused) {
        ticker?.stop();
      } else {
        _resumeTicker();
      }
    });
  }

  void _resumeTicker() {
    final ticker = _ticker;
    if (ticker == null || ticker.isActive) return;
    _lastElapsed = Duration.zero;
    ticker.start();
  }

  void _pointerDown(PointerDownDetails details) {
    if (details.button != MouseButton.left) return;
    if (_game.phase == NeonAsteroidsPhase.paused) {
      _togglePause();
      return;
    }
    if (_game.phase == NeonAsteroidsPhase.attract ||
        _game.phase == NeonAsteroidsPhase.gameOver) {
      _start();
      return;
    }
    _aimAt(details.col, details.row);
    _pointerFire = true;
  }

  void _pointerDrag(int col, int row) {
    if (_game.phase != NeonAsteroidsPhase.playing) return;
    _aimAt(col, row);
    _pointerThrust = true;
  }

  void _aimAt(int col, int row) {
    final size = MediaQuery.sizeOf(context);
    final gameRows = math.max(1, size.rows - 4);
    final localRow = (row - 2).clamp(0, gameRows - 1);
    final x =
        col.clamp(0, math.max(0, size.cols - 1)) /
        math.max(1, size.cols - 1) *
        _game.width;
    final y = (1 - localRow / math.max(1, gameRows - 1)) * _game.height;
    final dx = _shortestDelta(x - _game.ship.position.x, _game.width);
    final dy = _shortestDelta(y - _game.ship.position.y, _game.height);
    setState(() => _game.ship.angle = math.atan2(dy, dx));
  }

  static double _shortestDelta(double delta, double extent) {
    if (delta > extent / 2) return delta - extent;
    if (delta < -extent / 2) return delta + extent;
    return delta;
  }

  void _onSemanticAction(SemanticAction action) {
    if (action == SemanticAction.start || action == SemanticAction.activate) {
      _launchOrFire();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Reading capabilities here (not the snapshot) is what subscribes this
    // widget to negotiation: if a surface confirms or loses held-key support
    // mid-session, the control scheme and its legend follow.
    return KeyBindings(
      bindings: _bindings(),
      // Sampled input is surface-wide, so a scene that keeps ticking while
      // focus is elsewhere acts on keys meant for whatever took focus.
      // Gating the SIMULATION is the fix — a paused ship neither thrusts
      // nor drifts into a rock. Stacks with the route-visibility TickerMode
      // read in didChangeDependencies: hidden OR unfocused means muted.
      child: TickerMode.whileFocused(
        child: Focus(
          autofocus: true,
          debugLabel: 'neon-asteroids',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _hud(size),
              const SizedBox(height: 1),
              Expanded(child: _playfield(size)),
              const SizedBox(height: 1),
              _controls(size),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hud(CellSize size) {
    final compact = size.cols < 72;
    final tiny = size.cols < 52;
    final phaseLabel = tiny
        ? switch (_game.phase) {
            NeonAsteroidsPhase.attract => 'DEMO',
            NeonAsteroidsPhase.playing => 'W${_game.wave}',
            NeonAsteroidsPhase.paused => 'PAUSE',
            NeonAsteroidsPhase.gameOver => 'LOST',
          }
        : switch (_game.phase) {
            NeonAsteroidsPhase.attract => 'ATTRACT',
            NeonAsteroidsPhase.playing =>
              'WAVE ${_game.wave.toString().padLeft(2, '0')}',
            NeonAsteroidsPhase.paused => 'PAUSED',
            NeonAsteroidsPhase.gameOver => 'SIGNAL LOST',
          };
    final lives = List<String>.filled(_game.lives, '◇').join();
    final scoreText = _game.score.toString().padLeft(6, '0');

    return Row(
      children: <Widget>[
        Text('▌', style: const CellStyle(foreground: _cyan, bold: true)),
        const SizedBox(width: 1),
        Text(
          tiny ? 'ASTRO' : (compact ? 'ASTEROIDS' : 'NEON // ASTEROIDS'),
          style: const CellStyle(foreground: _cyan, bold: true),
        ),
        const Expanded(child: SizedBox.shrink()),
        Reveal(
          visible:
              _game.ship.shieldTicks > 0 &&
              _game.phase == NeonAsteroidsPhase.playing,
          enter: Effects.reveal(from: Edge.left),
          exit: Effects.conceal(to: Edge.right),
          duration: const Duration(milliseconds: 220),
          child: _shieldLabel(),
        ),
        if (!compact) const SizedBox(width: 2),
        Text(phaseLabel, style: const CellStyle(foreground: _violet)),
        SizedBox(width: tiny ? 1 : 2),
        Animate(
          key: ValueKey<String>('lives-${_game.impactEvent}'),
          play: _game.impactEvent > 0,
          effects: <Effect>[Effects.flash(color: _coral)],
          duration: const Duration(milliseconds: 280),
          child: Text(
            compact ? lives : 'LIVES $lives',
            style: const CellStyle(foreground: _coral, bold: true),
          ),
        ),
        SizedBox(width: tiny ? 1 : 2),
        Animate(
          key: ValueKey<String>('score-${_game.scoreEvent}'),
          play: _game.scoreEvent > 0,
          effects: <Effect>[Effects.flash(color: _amber)],
          duration: const Duration(milliseconds: 320),
          child: Text(
            compact ? scoreText : 'SCORE $scoreText',
            style: const CellStyle(foreground: _amber, bold: true),
          ),
        ),
      ],
    );
  }

  Widget _shieldLabel() {
    const label = Text(
      'SHIELD',
      style: CellStyle(foreground: _cyan, bold: true),
    );
    if (_reducedMotion) return label;
    return Animate(
      key: ValueKey<int>(_game.lives),
      repeat: true,
      effects: <Effect>[Effects.pulse(to: _starBright)],
      duration: const Duration(milliseconds: 900),
      child: label,
    );
  }

  Widget _playfield(CellSize size) {
    final canvas = Canvas(
      marker: CanvasMarker.braille,
      bounds: CanvasBounds(
        minX: 0,
        maxX: _game.width,
        minY: 0,
        maxY: _game.height,
      ),
      painter: _AsteroidsPainter(_game, reducedMotion: _reducedMotion),
      semanticLabel: 'Neon Asteroids playfield',
      semanticValue:
          '${_game.phase.name}, score ${_game.score}, '
          '${_game.asteroids.length} asteroids',
      semanticHint:
          'Arrow keys or A D W steer; Space fires; P pauses; R restarts.',
    );

    return Semantics(
      key: const ValueKey<String>('neon-asteroids-playfield'),
      role: SemanticRole.region,
      label: 'Neon Asteroids game',
      value: _game.phase.name,
      actions: const <SemanticAction>{
        SemanticAction.activate,
        SemanticAction.start,
      },
      onAction: _onSemanticAction,
      child: GestureDetector(
        onPointerDown: _pointerDown,
        onDragStart: _pointerDrag,
        onDragUpdate: _pointerDrag,
        onDragEnd: () => _pointerThrust = false,
        child: Stack(
          children: <Widget>[
            canvas,
            if (_game.phase == NeonAsteroidsPhase.attract)
              Center(
                key: const ValueKey<String>('attract-card'),
                child: _attractCard(size),
              ),
            if (_game.phase == NeonAsteroidsPhase.paused)
              Center(
                key: const ValueKey<String>('paused-card'),
                child: _messageCard(
                  width: math.min(38, math.max(24, size.cols - 6)),
                  title: 'SIMULATION PAUSED',
                  body: 'P / ESC TO RESUME',
                  color: _amber,
                ),
              ),
            if (_game.phase == NeonAsteroidsPhase.gameOver)
              Center(
                key: const ValueKey<String>('game-over-card'),
                child: _messageCard(
                  width: math.min(42, math.max(24, size.cols - 6)),
                  title: 'SIGNAL LOST',
                  body:
                      'FINAL ${_game.score.toString().padLeft(6, '0')}  ·  R / SPACE',
                  color: _coral,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _attractCard(CellSize size) {
    final narrow = size.cols < 60;
    return Container.framed(
      width: math.min(narrow ? 38 : 50, math.max(24, size.cols - 6)),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      color: _void,
      border: const BoxBorder(
        style: BorderStyle.rounded,
        cellStyle: CellStyle(foreground: _cyanDim),
      ),
      child: Reveal(
        visible: true,
        enter: Effects.fadeIn(surface: _void) + Effects.reveal(from: Edge.left),
        duration: const Duration(milliseconds: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            const Text(
              'N E O N   A S T E R O I D S',
              style: CellStyle(foreground: _cyan, bold: true),
            ),
            if (!narrow)
              const Text(
                'VECTOR FLIGHT / TOROIDAL SECTOR',
                style: CellStyle(foreground: _violetDim),
              ),
            const SizedBox(height: 1),
            const Text(
              'SPACE / ENTER TO LAUNCH',
              style: CellStyle(foreground: _amber, bold: true),
            ),
            if (!narrow)
              const Text(
                'or click the field',
                style: CellStyle(foreground: _starBright),
              ),
          ],
        ),
      ),
    );
  }

  Widget _messageCard({
    required int width,
    required String title,
    required String body,
    required RgbColor color,
  }) {
    return Container.framed(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      color: _void,
      border: BoxBorder(
        style: BorderStyle.rounded,
        cellStyle: CellStyle(foreground: color),
      ),
      child: Reveal(
        visible: true,
        enter: Effects.fadeIn(surface: _void),
        duration: const Duration(milliseconds: 220),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(title, style: CellStyle(foreground: color, bold: true)),
            Text(body, style: const CellStyle(foreground: _starBright)),
          ],
        ),
      ),
    );
  }

  Widget _controls(CellSize size) {
    final narrow = size.cols < 74;
    final controls = size.cols < 48
        ? 'A/D  W  SPACE  P'
        : (_reducedMotion && size.cols < 64)
        ? 'A/D TURN  W THRUST  SPACE FIRE'
        : narrow
        ? 'A/D TURN  W THRUST  SPACE FIRE  P PAUSE  R RESET'
        : '←/A TURN LEFT   →/D TURN RIGHT   ↑/W THRUST   SPACE FIRE   P PAUSE   R RESTART';
    return Row(
      children: <Widget>[
        Text(controls, style: const CellStyle(foreground: _starBright)),
        const Expanded(child: SizedBox.shrink()),
        if (_reducedMotion)
          const Text(
            'MOTION REDUCED',
            style: CellStyle(foreground: _amber, bold: true),
          )
        else
          const Text('● LIVE', style: CellStyle(foreground: _cyan, bold: true)),
      ],
    );
  }
}

class _AsteroidsPainter extends CanvasPainter {
  _AsteroidsPainter(this.game, {required this.reducedMotion});

  final NeonAsteroidsGame game;
  final bool reducedMotion;

  @override
  void paint(CanvasContext ctx) {
    _paintStars(ctx);
    for (final asteroid in game.asteroids) {
      _paintAsteroid(ctx, asteroid);
    }
    for (final bullet in game.bullets) {
      _paintBullet(ctx, bullet);
    }
    if (!reducedMotion) {
      for (final particle in game.particles) {
        _paintParticle(ctx, particle);
      }
    }
    _paintShip(ctx);
  }

  void _paintStars(CanvasContext ctx) {
    for (var i = 0; i < 48; i++) {
      final layer = i % 3;
      final baseX = ((i * 47 + 13) % 211) / 211;
      final baseY = ((i * 83 + 29) % 197) / 197;
      final drift = reducedMotion
          ? 0.0
          : game.tickCount * (0.000012 + layer * 0.000008);
      final x = ((baseX + drift) % 1) * game.width;
      final y = baseY * game.height;
      ctx.drawDot(x, y, color: layer == 2 ? _starBright : _starDim);
    }
  }

  void _paintAsteroid(CanvasContext ctx, NeonAsteroid asteroid) {
    _wrappedCopies(asteroid.position, asteroid.radius, (cx, cy) {
      const vertices = 10;
      var previousX = 0.0;
      var previousY = 0.0;
      var firstX = 0.0;
      var firstY = 0.0;
      for (var i = 0; i < vertices; i++) {
        final angle = asteroid.angle + i * math.pi * 2 / vertices;
        final roughness = 0.76 + _hashUnit(asteroid.id * 37 + i * 19) * 0.34;
        final x = cx + math.cos(angle) * asteroid.radius * roughness;
        final y = cy + math.sin(angle) * asteroid.radius * roughness;
        if (i == 0) {
          firstX = x;
          firstY = y;
        } else {
          ctx.drawLine(
            previousX,
            previousY,
            x,
            y,
            color: asteroid.tier == 1 ? _violet : _violetDim,
          );
        }
        previousX = x;
        previousY = y;
      }
      ctx.drawLine(
        previousX,
        previousY,
        firstX,
        firstY,
        color: asteroid.tier == 1 ? _violet : _violetDim,
      );

      // One sparse internal facet gives the rocks depth without filling them.
      final facet = asteroid.angle + asteroid.id * 0.31;
      ctx.drawLine(
        cx + math.cos(facet) * asteroid.radius * 0.18,
        cy + math.sin(facet) * asteroid.radius * 0.18,
        cx + math.cos(facet + 1.8) * asteroid.radius * 0.62,
        cy + math.sin(facet + 1.8) * asteroid.radius * 0.62,
        color: _violetDim,
      );
    });
  }

  void _paintShip(CanvasContext ctx) {
    final ship = game.ship;
    _wrappedCopies(ship.position, 4.0, (cx, cy) {
      final noseX = cx + math.cos(ship.angle) * 3.6;
      final noseY = cy + math.sin(ship.angle) * 3.6;
      final leftX = cx + math.cos(ship.angle + 2.48) * 2.8;
      final leftY = cy + math.sin(ship.angle + 2.48) * 2.8;
      final rightX = cx + math.cos(ship.angle - 2.48) * 2.8;
      final rightY = cy + math.sin(ship.angle - 2.48) * 2.8;
      ctx
        ..drawLine(noseX, noseY, leftX, leftY, color: _cyan)
        ..drawLine(leftX, leftY, cx, cy, color: _cyanDim)
        ..drawLine(cx, cy, rightX, rightY, color: _cyanDim)
        ..drawLine(rightX, rightY, noseX, noseY, color: _cyan);

      if (game.thrusting && game.phase == NeonAsteroidsPhase.playing) {
        final flicker = reducedMotion
            ? 3.2
            : 2.6 + 1.4 * (0.5 + 0.5 * math.sin(game.tickCount * 0.9));
        ctx.drawLine(
          cx + math.cos(ship.angle + math.pi) * 1.2,
          cy + math.sin(ship.angle + math.pi) * 1.2,
          cx + math.cos(ship.angle + math.pi) * flicker,
          cy + math.sin(ship.angle + math.pi) * flicker,
          color: _coral,
        );
      }

      if (ship.shieldTicks > 0 && game.phase == NeonAsteroidsPhase.playing) {
        final pulse = reducedMotion
            ? 4.7
            : 4.7 + math.sin(game.tickCount * 0.08) * 0.35;
        var px = cx + pulse;
        var py = cy;
        for (var i = 1; i <= 18; i++) {
          final angle = i * math.pi * 2 / 18;
          final x = cx + math.cos(angle) * pulse;
          final y = cy + math.sin(angle) * pulse;
          ctx.drawLine(px, py, x, y, color: _cyanDim);
          px = x;
          py = y;
        }
      }
    });
  }

  void _paintBullet(CanvasContext ctx, NeonBullet bullet) {
    ctx.drawDot(bullet.position.x, bullet.position.y, color: _amber);
    if (reducedMotion) return;
    final dx = bullet.position.x - bullet.previous.x;
    final dy = bullet.position.y - bullet.previous.y;
    if (dx.abs() < game.width / 2 && dy.abs() < game.height / 2) {
      ctx.drawLine(
        bullet.previous.x,
        bullet.previous.y,
        bullet.position.x,
        bullet.position.y,
        color: _coral,
      );
    }
  }

  void _paintParticle(CanvasContext ctx, NeonParticle particle) {
    final remaining = particle.lifeTicks / particle.maxLifeTicks;
    ctx.drawDot(
      particle.position.x,
      particle.position.y,
      color: remaining > 0.58 ? _coral : _violetDim,
    );
  }

  void _wrappedCopies(
    NeonVector center,
    double radius,
    void Function(double x, double y) draw,
  ) {
    final xs = <double>[center.x];
    final ys = <double>[center.y];
    if (center.x < radius) xs.add(center.x + game.width);
    if (center.x > game.width - radius) xs.add(center.x - game.width);
    if (center.y < radius) ys.add(center.y + game.height);
    if (center.y > game.height - radius) ys.add(center.y - game.height);
    for (final x in xs) {
      for (final y in ys) {
        draw(x, y);
      }
    }
  }

  static double _hashUnit(int value) {
    var x = value & 0x7fffffff;
    x = ((x >> 16) ^ x) * 0x45d9f3b;
    x = ((x >> 16) ^ x) * 0x45d9f3b;
    x = (x >> 16) ^ x;
    return (x & 0xffff) / 0xffff;
  }
}
