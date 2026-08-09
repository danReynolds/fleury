// ANSI Sprite Studio: paint a terminal animation and leave with the exact,
// portable asset that was previewed.

import 'dart:async' show unawaited;

import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

import 'ansi_sprite_model.dart';
import 'scaffold.dart';

const _transparentA = RgbColor(0x16, 0x1c, 0x24);
const _transparentB = RgbColor(0x20, 0x28, 0x32);
const _cursor = RgbColor(0xff, 0xff, 0xff);

/// A self-contained sprite editor that runs unchanged in a terminal or the
/// browser host.
class AnsiSpriteStudioApp extends StatelessWidget {
  const AnsiSpriteStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const SampleScaffold(child: _AnsiSpriteStudioBody());
  }
}

class _AnsiSpriteStudioBody extends StatefulWidget {
  const _AnsiSpriteStudioBody();

  @override
  State<_AnsiSpriteStudioBody> createState() => _AnsiSpriteStudioBodyState();
}

class _AnsiSpriteStudioBodyState extends State<_AnsiSpriteStudioBody> {
  late AnsiSpriteModel _model = AnsiSpriteModel.fleury();
  final FocusNode _canvasFocus = FocusNode(debugLabel: 'sprite-canvas');
  final BoundsNotifier _canvasBounds = BoundsNotifier();
  final FocusNode _importFocus = FocusNode(debugLabel: 'sprite-import');
  final TextEditingController _importController = TextEditingController();

  bool _importing = false;
  String? _importError;
  (int, int)? _pointerDown;
  (int, int)? _lastStrokeCell;
  String _status =
      'Ready — arrows move, Space paints, and mouse drag draws one stroke.';

  @override
  void dispose() {
    _model.dispose();
    _canvasFocus.dispose();
    _canvasBounds.dispose();
    _importFocus.dispose();
    _importController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_importing) return _importSurface(context);
    return KeyBindings(
      // Reading capabilities here is build-legal AND reactive: when a terminal
      // finishes negotiating, this rebuilds and the control scheme upgrades
      // itself (RFC 0020 §7.6).
      bindings: _bindings(Keyboard.of(context).capabilities),
      child: ListenableBuilder(
        listenable: _model,
        builder: (context, _) => _studioSurface(context),
      ),
    );
  }

  List<KeyBinding> _bindings(KeyboardCapabilities keyboard) => <KeyBinding>[
    KeyBinding(
      KeyCode.arrowLeft,
      hideFromHintBar: true,
      onTrigger: (_) => _model.moveCursor(-1, 0),
      // Held arrows walk the canvas — the repeat-reliant class.
      includeRepeats: true,
    ),
    KeyBinding(
      KeyCode.arrowRight,
      hideFromHintBar: true,
      onTrigger: (_) => _model.moveCursor(1, 0),
      // Held arrows walk the canvas — the repeat-reliant class.
      includeRepeats: true,
    ),
    KeyBinding(
      KeyCode.arrowUp,
      hideFromHintBar: true,
      onTrigger: (_) => _model.moveCursor(0, -1),
      // Held arrows walk the canvas — the repeat-reliant class.
      includeRepeats: true,
    ),
    KeyBinding(
      KeyCode.arrowDown,
      hideFromHintBar: true,
      onTrigger: (_) => _model.moveCursor(0, 1),
      // Held arrows walk the canvas — the repeat-reliant class.
      includeRepeats: true,
    ),
    // Space is the pen. Where the surface reports releases we can know the
    // key is still DOWN, so holding it draws continuously as the cursor
    // moves — the same gesture the mouse has always had, as one undo unit.
    //
    // Where it does not, a hold could start and never end, so the studio
    // takes the honest fallback rather than a broken brush: tap to paint one
    // cell. Same key, same label position in the hint bar; only the reach
    // differs.
    if (keyboard.supportsHeldState)
      KeyBinding.hold(
        KeyCode.space,
        label: 'draw (hold)',
        onHoldStart: (_) => _model.beginBrushStroke(),
        onHoldEnd: (_) => _model.endBrushStroke(),
      )
    else
      KeyBinding(
        KeyCode.space,
        label: 'paint',
        onTrigger: (_) => _model.applyAtCursor(),
      ),
    KeyBinding(
      KeyCode.p,
      label: 'pencil',
      onTrigger: (_) => _model.selectTool(AnsiSpriteTool.pencil),
    ),
    KeyBinding(
      KeyCode.e,
      label: 'erase',
      onTrigger: (_) => _model.selectTool(AnsiSpriteTool.erase),
    ),
    KeyBinding(
      KeyCode.f,
      label: 'fill',
      onTrigger: (_) => _model.selectTool(AnsiSpriteTool.fill),
    ),
    KeyBinding(
      KeyCode.r,
      label: 'play/pause',
      onTrigger: (_) => _model.togglePlayback(),
    ),
    KeyBinding(
      KeyCode.o,
      label: 'onion skin',
      onTrigger: (_) => _model.toggleOnionSkin(),
    ),
    KeyBinding(
      KeyCode.n,
      label: 'new frame',
      onTrigger: (_) => _model.addFrame(),
    ),
    KeyBinding(
      KeyCode.d,
      label: 'duplicate',
      onTrigger: (_) => _model.duplicateFrame(),
    ),
    KeyBinding(
      KeyCode.x,
      label: 'delete frame',
      enabled: _model.frames.length > 1,
      onTrigger: (_) => _model.deleteSelectedFrame(),
    ),
    KeyBinding(
      KeyCode.char('['),
      hideFromHintBar: true,
      onTrigger: (_) => _selectRelativeFrame(-1),
    ),
    KeyBinding(
      KeyCode.char(']'),
      hideFromHintBar: true,
      onTrigger: (_) => _selectRelativeFrame(1),
    ),
    KeyBinding(
      KeyCode.char('-'),
      hideFromHintBar: true,
      onTrigger: (_) => _model.adjustDuration(-20),
    ),
    KeyBinding(
      KeyCode.char('+'),
      hideFromHintBar: true,
      onTrigger: (_) => _model.adjustDuration(20),
    ),
    KeyBinding(
      KeySequence.ctrl.z,
      label: 'undo',
      enabled: _model.canUndo,
      onTrigger: (_) => _model.undo(),
    ),
    KeyBinding(
      KeySequence.ctrl.y,
      label: 'redo',
      enabled: _model.canRedo,
      onTrigger: (_) => _model.redo(),
    ),
    KeyBinding(
      KeySequence.ctrl.c,
      label: 'copy JSON',
      onTrigger: (_) => unawaited(_copyPortable()),
    ),
    KeyBinding(KeyCode.i, label: 'import', onTrigger: (_) => _openImport()),
  ];

  Widget _studioSurface(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _header(theme),
          const SizedBox(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = (constraints.maxCols ?? 100) >= 90;
                final editor = _editorPanel(theme);
                final preview = _previewPanel(theme);
                final controls = _controlsPanel(theme);
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(flex: 5, child: editor),
                      const SizedBox(width: 1),
                      Expanded(flex: 3, child: preview),
                      const SizedBox(width: 1),
                      Expanded(flex: 3, child: controls),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(flex: 3, child: editor),
                    const SizedBox(width: 1),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(child: preview),
                          const SizedBox(height: 1),
                          Expanded(child: controls),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 1),
          _timeline(theme),
          const SizedBox(height: 1),
          Text(_status, softWrap: false, style: theme.mutedStyle),
          const KeyHintBar(maxBindings: 9),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Row(
      children: <Widget>[
        Text('✦ ', style: CellStyle(foreground: theme.colorScheme.warning)),
        Text(
          'ANSI Sprite Studio',
          style: CellStyle(bold: true, foreground: theme.colorScheme.primary),
        ),
        const SizedBox(width: 2),
        Text('paint → preview → portable JSON', style: theme.mutedStyle),
        const Expanded(child: SizedBox.shrink()),
        Text(
          '${_model.width}×${_model.height}  '
          '${_model.frames.length} frames',
          style: CellStyle(foreground: theme.colorScheme.info),
        ),
      ],
    );
  }

  Widget _editorPanel(ThemeData theme) {
    return Panel(
      title: 'Cell canvas',
      trailing: Text(
        '${_model.cursorX + 1},${_model.cursorY + 1}',
        style: theme.mutedStyle,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Focus(
              focusNode: _canvasFocus,
              autofocus: true,
              child: BoundsObserver(
                notifier: _canvasBounds,
                child: GestureDetector(
                  onPointerDown: _armPointerStroke,
                  onTap: _commitPointerTap,
                  onDragStart: _beginPointerDrag,
                  onDragUpdate: _paintAtScreenCell,
                  onDragEnd: _endPointerStroke,
                  child: Semantics(
                    role: SemanticRole.image,
                    label: 'Editable sprite canvas',
                    value:
                        '${_model.selectedFrame.id}, '
                        'cursor ${_model.cursorX + 1},${_model.cursorY + 1}',
                    hint: 'Arrow keys move. Space paints. Mouse drag draws.',
                    state: SemanticState(<String, Object?>{
                      'spriteWidth': _model.width,
                      'spriteHeight': _model.height,
                      'frameId': _model.selectedFrame.id,
                      'tool': _model.tool.name,
                    }),
                    child: _SpriteGrid(
                      width: _model.width,
                      height: _model.height,
                      cells: _model.selectedFrame.cells,
                      onionCells: _model.onionFrame?.cells,
                      paletteRgb: _model.paletteRgb,
                      cursorX: _model.cursorX,
                      cursorY: _model.cursorY,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 1),
            _palette(theme),
          ],
        ),
      ),
    );
  }

  Widget _palette(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('palette ', style: theme.mutedStyle),
        for (var i = 0; i < _model.paletteRgb.length; i++) ...<Widget>[
          _PaletteChip(
            color: _rgb(_model.paletteRgb[i]),
            label: 'Color ${i + 1}',
            selected:
                _model.tool == AnsiSpriteTool.pencil &&
                _model.selectedColorIndex == i + 1,
            onPressed: () => _model.selectColor(i + 1),
          ),
          if (i + 1 < _model.paletteRgb.length) const SizedBox(width: 1),
        ],
      ],
    );
  }

  Widget _previewPanel(ThemeData theme) {
    final playing = _model.isPlaying;
    return Panel(
      title: 'Live preview',
      focused: playing,
      trailing: Text(
        playing ? '● PLAY' : '■ PAUSED',
        style: CellStyle(
          bold: playing,
          foreground: playing
              ? theme.colorScheme.success
              : theme.colorScheme.foreground,
        ),
      ),
      child: Center(
        child: FrameBuilder(
          interval: const Duration(milliseconds: 40),
          enabled: playing,
          builder: (context, frame, elapsed, delta) {
            final index = playing
                ? _model.playbackFrameIndexAt(elapsed)
                : _model.selectedFrameIndex;
            final spriteFrame = _model.frames[index];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _SpriteGrid(
                  width: _model.width,
                  height: _model.height,
                  cells: spriteFrame.cells,
                  paletteRgb: _model.paletteRgb,
                ),
                const SizedBox(height: 1),
                Text(
                  '${spriteFrame.id}  ${spriteFrame.durationMs} ms',
                  style: theme.mutedStyle,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _controlsPanel(ThemeData theme) {
    final frame = _model.selectedFrame;
    return Panel(
      title: 'Studio',
      trailing: Text(
        _model.tool.name.toUpperCase(),
        style: CellStyle(foreground: theme.colorScheme.primary),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Tool', style: theme.mutedStyle),
            Wrap(
              spacing: 1,
              children: <Widget>[
                _ActionChip(
                  label: 'Pencil',
                  selected: _model.tool == AnsiSpriteTool.pencil,
                  onPressed: () => _model.selectTool(AnsiSpriteTool.pencil),
                ),
                _ActionChip(
                  label: 'Erase',
                  selected: _model.tool == AnsiSpriteTool.erase,
                  onPressed: () => _model.selectTool(AnsiSpriteTool.erase),
                ),
                _ActionChip(
                  label: 'Fill',
                  selected: _model.tool == AnsiSpriteTool.fill,
                  onPressed: () => _model.selectTool(AnsiSpriteTool.fill),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text('Frame', style: theme.mutedStyle),
            Wrap(
              spacing: 1,
              runSpacing: 1,
              children: <Widget>[
                _ActionChip(label: '+ Blank', onPressed: _model.addFrame),
                _ActionChip(
                  label: 'Duplicate',
                  onPressed: _model.duplicateFrame,
                ),
                _ActionChip(
                  label: 'Delete',
                  enabled: _model.frames.length > 1,
                  onPressed: _model.deleteSelectedFrame,
                ),
                _ActionChip(
                  label: '←',
                  enabled: _model.selectedFrameIndex > 0,
                  semanticLabel: 'Move frame left',
                  onPressed: () => _model.moveSelectedFrame(-1),
                ),
                _ActionChip(
                  label: '→',
                  enabled: _model.selectedFrameIndex + 1 < _model.frames.length,
                  semanticLabel: 'Move frame right',
                  onPressed: () => _model.moveSelectedFrame(1),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text('Timing', style: theme.mutedStyle),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _ActionChip(
                  label: '−',
                  semanticLabel: 'Decrease frame duration',
                  onPressed: () => _model.adjustDuration(-20),
                ),
                const SizedBox(width: 1),
                Text('${frame.durationMs} ms'),
                const SizedBox(width: 1),
                _ActionChip(
                  label: '+',
                  semanticLabel: 'Increase frame duration',
                  onPressed: () => _model.adjustDuration(20),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Wrap(
              spacing: 1,
              children: <Widget>[
                _ActionChip(
                  label: _model.isPlaying ? 'Pause' : 'Play',
                  selected: _model.isPlaying,
                  onPressed: _model.togglePlayback,
                ),
                _ActionChip(
                  label: 'Onion',
                  selected: _model.onionSkin,
                  onPressed: _model.toggleOnionSkin,
                ),
              ],
            ),
            const Spacer(),
            Wrap(
              spacing: 1,
              children: <Widget>[
                _ActionChip(
                  label: 'Copy JSON',
                  onPressed: () => unawaited(_copyPortable()),
                ),
                _ActionChip(label: 'Import…', onPressed: _openImport),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeline(ThemeData theme) {
    return Panel(
      title: 'Frames',
      expandChild: false,
      trailing: Text('[ / ] select', style: theme.mutedStyle),
      child: Wrap(
        spacing: 1,
        runSpacing: 1,
        children: <Widget>[
          for (var i = 0; i < _model.frames.length; i++)
            _ActionChip(
              key: ValueKey<String>(_model.frames[i].id),
              label: '${i + 1} · ${_model.frames[i].durationMs}ms',
              semanticLabel:
                  'Frame ${i + 1}, ${_model.frames[i].durationMs} milliseconds',
              selected: i == _model.selectedFrameIndex,
              onPressed: () => _model.selectFrame(i),
            ),
        ],
      ),
    );
  }

  Widget _importSurface(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'ANSI Sprite Studio · Import',
            style: CellStyle(bold: true, foreground: theme.colorScheme.primary),
          ),
          const SizedBox(height: 1),
          Expanded(
            child: Center(
              child: Container(
                width: 76,
                border: BoxBorder(
                  style: theme.borderStyle,
                  cellStyle: CellStyle(
                    foreground: _importError == null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                ),
                padding: const EdgeInsets.all(1),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'Paste portable sprite JSON',
                      style: CellStyle(bold: true),
                    ),
                    const SizedBox(height: 1),
                    const Text(
                      'System clipboard reads are intentionally unavailable. '
                      'Focus this field, Ctrl+A, paste, then press Enter.',
                      softWrap: true,
                    ),
                    const SizedBox(height: 1),
                    TextInput(
                      controller: _importController,
                      focusNode: _importFocus,
                      autofocus: true,
                      semanticLabel: 'Portable sprite JSON',
                      validationError: _importError,
                      enableBlink: false,
                      onSubmit: _applyImport,
                      onEscape: _cancelImport,
                    ),
                    if (_importError != null) ...<Widget>[
                      const SizedBox(height: 1),
                      Text(
                        _importError!,
                        style: CellStyle(foreground: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 1),
                    Row(
                      children: <Widget>[
                        Button(
                          label: 'Import',
                          variant: ButtonVariant.primary,
                          onPressed: () => _applyImport(_importController.text),
                        ),
                        const SizedBox(width: 1),
                        Button(label: 'Cancel', onPressed: _cancelImport),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text(
            'Enter imports · Esc cancels · Ctrl+V pastes normally',
            style: theme.mutedStyle,
          ),
        ],
      ),
    );
  }

  void _armPointerStroke(PointerDownDetails details) {
    _canvasFocus.requestFocus();
    if (details.button != MouseButton.left) return;
    _pointerDown = (details.col, details.row);
    _lastStrokeCell = null;
    _model.beginStroke();
  }

  void _commitPointerTap() {
    final down = _pointerDown;
    if (down != null) _paintAtScreenCell(down.$1, down.$2);
    _endPointerStroke();
  }

  void _beginPointerDrag(int col, int row) {
    final down = _pointerDown;
    if (down != null) _paintAtScreenCell(down.$1, down.$2);
    _pointerDown = null;
    _paintAtScreenCell(col, row);
  }

  void _endPointerStroke() {
    _pointerDown = null;
    _lastStrokeCell = null;
    _model.endStroke();
  }

  void _paintAtScreenCell(int col, int row) {
    final next = _spriteCellAtScreen(col, row);
    if (next == null) {
      _lastStrokeCell = null;
      return;
    }
    final previous = _lastStrokeCell;
    if (previous == null) {
      _model.paintStrokeCell(next.$1, next.$2);
    } else {
      _paintGridLine(previous, next);
    }
    _lastStrokeCell = next;
  }

  (int, int)? _spriteCellAtScreen(int col, int row) {
    final bounds = _canvasBounds.bounds;
    if (bounds == null) return null;
    final localCol = col - bounds.left;
    final localRow = row - bounds.top;
    if (localCol < 0 ||
        localCol >= _model.width * 2 ||
        localRow < 0 ||
        localRow >= _model.height) {
      return null;
    }
    return (localCol ~/ 2, localRow);
  }

  void _paintGridLine((int, int) from, (int, int) to) {
    var x = from.$1;
    var y = from.$2;
    final dx = (to.$1 - x).abs();
    final dy = (to.$2 - y).abs();
    final sx = x < to.$1 ? 1 : -1;
    final sy = y < to.$2 ? 1 : -1;
    var error = dx - dy;
    while (true) {
      _model.paintStrokeCell(x, y);
      if (x == to.$1 && y == to.$2) return;
      final doubled = error * 2;
      if (doubled > -dy) {
        error -= dy;
        x += sx;
      }
      if (doubled < dx) {
        error += dx;
        y += sy;
      }
    }
  }

  void _selectRelativeFrame(int delta) {
    final count = _model.frames.length;
    final index = (_model.selectedFrameIndex + delta) % count;
    _model.selectFrame(index);
  }

  Future<void> _copyPortable() async {
    final report = await ClipboardScope.of(
      context,
    ).writeWithReport(_model.exportPortable());
    if (!mounted) return;
    setState(() {
      _status =
          'Copied ${report.payloadBytes} bytes · '
          '${report.result.name}. Paste it back with Import.';
    });
  }

  void _openImport() {
    setState(() {
      _importController.text = _model.exportPortable();
      _importError = null;
      _importing = true;
    });
    _importFocus.requestFocus();
  }

  void _cancelImport() {
    setState(() {
      _importing = false;
      _importError = null;
    });
    _canvasFocus.requestFocus();
  }

  void _applyImport(String source) {
    try {
      final imported = AnsiSpriteModel.fromPortable(source);
      final old = _model;
      setState(() {
        _model = imported;
        _importing = false;
        _importError = null;
        _status =
            'Imported ${imported.frames.length} frames losslessly from JSON.';
      });
      old.dispose();
      _canvasFocus.requestFocus();
    } on FormatException catch (error) {
      setState(() => _importError = error.message);
      _importFocus.requestFocus();
    }
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    super.key,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
    this.selected = false,
    this.enabled = true,
  });

  final String label;
  final String? semanticLabel;
  final VoidCallback onPressed;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = !enabled
        ? theme.mutedStyle.merge(const CellStyle(dim: true))
        : selected
        ? theme.selectionStyle
        : CellStyle(foreground: theme.colorScheme.foreground);
    final content = Text(
      selected ? '[$label]' : ' $label ',
      allowSelect: false,
      style: style,
    );
    return Semantics(
      role: SemanticRole.button,
      label: semanticLabel ?? label,
      enabled: enabled,
      selected: selected,
      actions: enabled
          ? const <SemanticAction>{SemanticAction.activate}
          : const <SemanticAction>{},
      onAction: (action) {
        if (enabled && action == SemanticAction.activate) onPressed();
      },
      child: enabled
          ? GestureDetector(onTap: onPressed, child: content)
          : content,
    );
  }
}

class _PaletteChip extends StatelessWidget {
  const _PaletteChip({
    required this.color,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final swatch = Container(
      width: 4,
      color: color,
      child: Text(
        selected ? ' ◆  ' : '    ',
        allowSelect: false,
        style: const CellStyle(foreground: _cursor, bold: true),
      ),
    );
    return Semantics(
      role: SemanticRole.button,
      label: label,
      selected: selected,
      actions: const <SemanticAction>{SemanticAction.activate},
      onAction: (action) {
        if (action == SemanticAction.activate) onPressed();
      },
      child: GestureDetector(onTap: onPressed, child: swatch),
    );
  }
}

class _SpriteGrid extends LeafRenderObjectWidget {
  const _SpriteGrid({
    required this.width,
    required this.height,
    required this.cells,
    required this.paletteRgb,
    this.onionCells,
    this.cursorX,
    this.cursorY,
  });

  final int width;
  final int height;
  final List<int> cells;
  final List<int> paletteRgb;
  final List<int>? onionCells;
  final int? cursorX;
  final int? cursorY;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSpriteGrid(
      width: width,
      height: height,
      cells: cells,
      paletteRgb: paletteRgb,
      onionCells: onionCells,
      cursorX: cursorX,
      cursorY: cursorY,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSpriteGrid renderObject,
  ) {
    renderObject
      ..dimensions = (width, height)
      ..cells = cells
      ..paletteRgb = paletteRgb
      ..onionCells = onionCells
      ..cursor = (cursorX, cursorY);
  }
}

class _RenderSpriteGrid extends RenderObject {
  _RenderSpriteGrid({
    required int width,
    required int height,
    required List<int> cells,
    required List<int> paletteRgb,
    required List<int>? onionCells,
    required int? cursorX,
    required int? cursorY,
  }) : _width = width,
       _height = height,
       _cells = cells,
       _paletteRgb = paletteRgb,
       _onionCells = onionCells,
       _cursorX = cursorX,
       _cursorY = cursorY;

  int _width;
  int _height;
  List<int> _cells;
  List<int> _paletteRgb;
  List<int>? _onionCells;
  int? _cursorX;
  int? _cursorY;

  set dimensions((int, int) value) {
    if (_width == value.$1 && _height == value.$2) return;
    _width = value.$1;
    _height = value.$2;
    markNeedsLayout();
  }

  set cells(List<int> value) {
    if (identical(_cells, value)) return;
    _cells = value;
    markNeedsPaintOnly();
  }

  set paletteRgb(List<int> value) {
    if (identical(_paletteRgb, value)) return;
    _paletteRgb = value;
    markNeedsPaintOnly();
  }

  set onionCells(List<int>? value) {
    if (identical(_onionCells, value)) return;
    _onionCells = value;
    markNeedsPaintOnly();
  }

  set cursor((int?, int?) value) {
    if (_cursorX == value.$1 && _cursorY == value.$2) return;
    _cursorX = value.$1;
    _cursorY = value.$2;
    markNeedsPaintOnly();
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    return constraints.constrain(CellSize(_width * 2, _height));
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final visibleWidth = size.cols ~/ 2;
    final visibleHeight = size.rows;
    for (var y = 0; y < _height && y < visibleHeight; y++) {
      for (var x = 0; x < _width && x < visibleWidth; x++) {
        final index = y * _width + x;
        final value = _cells[index];
        final checker = (x + y).isEven ? _transparentA : _transparentB;
        final color = _colorAt(value);
        final onionValue = _onionCells?[index] ?? 0;
        final onionColor = value == 0 ? _colorAt(onionValue) : null;
        final isCursor = x == _cursorX && y == _cursorY;
        final style = CellStyle(
          foreground: isCursor ? _cursor : onionColor,
          background: color ?? checker,
          bold: isCursor,
          dim: onionColor != null,
        );
        final left = isCursor
            ? '['
            : onionColor == null
            ? ' '
            : '░';
        final right = isCursor
            ? ']'
            : onionColor == null
            ? ' '
            : '░';
        buffer.writeGrapheme(
          CellOffset(offset.col + x * 2, offset.row + y),
          left,
          style: style,
        );
        buffer.writeGrapheme(
          CellOffset(offset.col + x * 2 + 1, offset.row + y),
          right,
          style: style,
        );
      }
    }
  }

  Color? _colorAt(int value) {
    if (value <= 0 || value > _paletteRgb.length) return null;
    return _rgb(_paletteRgb[value - 1]);
  }
}

RgbColor _rgb(int value) {
  return RgbColor((value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff);
}
