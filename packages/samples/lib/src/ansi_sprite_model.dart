// Browser-safe model and portable document contract for ANSI Sprite Studio.

import 'dart:convert';

import 'package:fleury/fleury_core.dart';

/// Editing operation applied to a sprite cell.
enum AnsiSpriteTool { pencil, erase, fill }

/// One immutable animation frame.
final class AnsiSpriteFrame {
  AnsiSpriteFrame({
    required this.id,
    required this.durationMs,
    required List<int> cells,
  }) : cells = List<int>.unmodifiable(cells);

  final String id;
  final int durationMs;
  final List<int> cells;

  AnsiSpriteFrame copyWith({String? id, int? durationMs, List<int>? cells}) {
    return AnsiSpriteFrame(
      id: id ?? this.id,
      durationMs: durationMs ?? this.durationMs,
      cells: cells ?? this.cells,
    );
  }
}

/// State and lossless edit history for the sprite studio.
///
/// Palette index zero is transparent. Opaque palette entries are one-based:
/// a cell value of `1` refers to `paletteRgb[0]`.
class AnsiSpriteModel with ChangeNotifier {
  AnsiSpriteModel._({
    required this.width,
    required this.height,
    required List<int> paletteRgb,
    required List<AnsiSpriteFrame> frames,
    int selectedFrameIndex = 0,
  }) : paletteRgb = List<int>.unmodifiable(paletteRgb),
       _frames = List<AnsiSpriteFrame>.of(frames),
       _selectedFrameIndex = selectedFrameIndex {
    _validateDocument(
      width: width,
      height: height,
      paletteRgb: this.paletteRgb,
      frames: _frames,
    );
    _cursorX = width ~/ 2;
    _cursorY = height ~/ 2;
    _selectedColorIndex = paletteRgb.isEmpty ? 0 : 1;
  }

  /// A polished four-frame Fleury flower, ready to edit and play.
  factory AnsiSpriteModel.fleury() {
    const rows = <List<String>>[
      <String>[
        '000330000000',
        '003443000000',
        '034114300000',
        '031111300000',
        '003113000000',
        '000110000000',
        '002112200000',
        '000222000000',
      ],
      <String>[
        '003443000000',
        '034554300000',
        '345115430000',
        '041111400000',
        '004114000000',
        '000110000000',
        '002112200000',
        '000222000000',
      ],
      <String>[
        '000440000000',
        '004554000000',
        '045115400000',
        '041111400000',
        '004114000000',
        '000110000000',
        '000112200000',
        '000222000000',
      ],
      <String>[
        '000330000000',
        '003443000000',
        '034114300000',
        '031111300000',
        '003113000000',
        '000110000000',
        '002110000000',
        '000222000000',
      ],
    ];
    return AnsiSpriteModel._(
      width: 12,
      height: 8,
      paletteRgb: const <int>[
        0x3DDC97, // Fleury mint
        0x56C2FF, // sky
        0xFF5C8A, // petal
        0xF5C211, // glow
        0xB388FF, // bloom highlight
      ],
      frames: <AnsiSpriteFrame>[
        for (var i = 0; i < rows.length; i++)
          AnsiSpriteFrame(
            id: 'frame-${i + 1}',
            durationMs: i == 1 ? 180 : 140,
            cells: _decodeRows(rows[i], width: 12, height: 8, paletteLength: 5),
          ),
      ],
    );
  }

  /// Decodes the canonical, browser-safe portable representation.
  factory AnsiSpriteModel.fromPortable(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Invalid sprite JSON: ${error.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Sprite document must be a JSON object.');
    }
    if (decoded['format'] != 'fleury.ansi-sprite' || decoded['version'] != 1) {
      throw const FormatException(
        'Expected a fleury.ansi-sprite version 1 document.',
      );
    }
    final width = _requiredInt(decoded, 'width');
    final height = _requiredInt(decoded, 'height');
    final rawPalette = decoded['palette'];
    if (rawPalette is! List<Object?> || rawPalette.isEmpty) {
      throw const FormatException(
        'Sprite palette must be a non-empty JSON array.',
      );
    }
    if (rawPalette.length > 35) {
      throw const FormatException(
        'Sprite palette cannot contain more than 35 colors.',
      );
    }
    final palette = <int>[for (final value in rawPalette) _parseRgb(value)];
    final rawFrames = decoded['frames'];
    if (rawFrames is! List<Object?> || rawFrames.isEmpty) {
      throw const FormatException(
        'Sprite frames must be a non-empty JSON array.',
      );
    }
    final frames = <AnsiSpriteFrame>[];
    for (final rawFrame in rawFrames) {
      if (rawFrame is! Map<String, Object?>) {
        throw const FormatException('Every frame must be a JSON object.');
      }
      final id = rawFrame['id'];
      if (id is! String || id.trim().isEmpty) {
        throw const FormatException('Every frame needs a non-empty id.');
      }
      final durationMs = _requiredInt(rawFrame, 'durationMs');
      final rawRows = rawFrame['rows'];
      if (rawRows is! List<Object?> || rawRows.any((row) => row is! String)) {
        throw FormatException('Frame "$id" rows must be strings.');
      }
      frames.add(
        AnsiSpriteFrame(
          id: id,
          durationMs: durationMs,
          cells: _decodeRows(
            rawRows.cast<String>(),
            width: width,
            height: height,
            paletteLength: palette.length,
          ),
        ),
      );
    }
    return AnsiSpriteModel._(
      width: width,
      height: height,
      paletteRgb: palette,
      frames: frames,
    );
  }

  final int width;
  final int height;
  final List<int> paletteRgb;
  List<AnsiSpriteFrame> _frames;
  int _selectedFrameIndex;
  int _cursorX = 0;
  int _cursorY = 0;
  int _selectedColorIndex = 1;
  AnsiSpriteTool _tool = AnsiSpriteTool.pencil;
  bool _onionSkin = true;
  bool _playing = false;

  final List<_SpriteSnapshot> _undo = <_SpriteSnapshot>[];
  final List<_SpriteSnapshot> _redo = <_SpriteSnapshot>[];
  _SpriteSnapshot? _strokeStart;
  bool _strokeChanged = false;

  List<AnsiSpriteFrame> get frames =>
      List<AnsiSpriteFrame>.unmodifiable(_frames);
  int get selectedFrameIndex => _selectedFrameIndex;
  AnsiSpriteFrame get selectedFrame => _frames[_selectedFrameIndex];
  int get cursorX => _cursorX;
  int get cursorY => _cursorY;
  int get selectedColorIndex => _selectedColorIndex;
  AnsiSpriteTool get tool => _tool;
  bool get onionSkin => _onionSkin;
  bool get isPlaying => _playing;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  AnsiSpriteFrame? get onionFrame {
    if (!_onionSkin || _frames.length < 2) return null;
    final index = (_selectedFrameIndex - 1) % _frames.length;
    return _frames[index];
  }

  Color? colorForCell(int value) {
    if (value <= 0 || value > paletteRgb.length) return null;
    final rgb = paletteRgb[value - 1];
    return RgbColor((rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff);
  }

  int cellAt(int x, int y, {int? frameIndex}) {
    _checkCell(x, y);
    final frame = _frames[frameIndex ?? _selectedFrameIndex];
    return frame.cells[y * width + x];
  }

  void selectFrame(int index) {
    if (index < 0 || index >= _frames.length) return;
    if (_selectedFrameIndex == index) return;
    _selectedFrameIndex = index;
    _playing = false;
    notifyListeners();
  }

  void selectColor(int index) {
    if (index < 1 || index > paletteRgb.length) return;
    if (_selectedColorIndex == index && _tool == AnsiSpriteTool.pencil) {
      return;
    }
    _selectedColorIndex = index;
    _tool = AnsiSpriteTool.pencil;
    notifyListeners();
  }

  void selectTool(AnsiSpriteTool value) {
    if (_tool == value) return;
    _tool = value;
    notifyListeners();
  }

  void toggleOnionSkin() {
    _onionSkin = !_onionSkin;
    notifyListeners();
  }

  void moveCursor(int dx, int dy) {
    final x = (_cursorX + dx).clamp(0, width - 1);
    final y = (_cursorY + dy).clamp(0, height - 1);
    if (x == _cursorX && y == _cursorY) return;
    _cursorX = x;
    _cursorY = y;
    notifyListeners();
  }

  void setCursor(int x, int y) {
    final nextX = x.clamp(0, width - 1);
    final nextY = y.clamp(0, height - 1);
    if (nextX == _cursorX && nextY == _cursorY) return;
    _cursorX = nextX;
    _cursorY = nextY;
    notifyListeners();
  }

  /// Applies the selected tool as one undoable keyboard edit.
  void applyAtCursor() {
    _mutate(() => _applyTool(_cursorX, _cursorY));
  }

  /// Starts one mouse gesture. Every changed cell until [endStroke] is one
  /// undo unit.
  void beginStroke() {
    if (_strokeStart != null) return;
    _strokeStart = _capture();
    _strokeChanged = false;
  }

  void paintStrokeCell(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return;
    beginStroke();
    setCursor(x, y);
    if (_applyTool(x, y)) {
      _strokeChanged = true;
      _playing = false;
      notifyListeners();
    }
  }

  void endStroke() {
    final before = _strokeStart;
    if (before == null) return;
    _strokeStart = null;
    if (_strokeChanged) {
      _undo.add(before);
      _redo.clear();
    }
    _strokeChanged = false;
  }

  void addFrame() {
    _mutate(() {
      final index = _selectedFrameIndex + 1;
      _frames.insert(
        index,
        AnsiSpriteFrame(
          id: _nextFrameId(),
          durationMs: selectedFrame.durationMs,
          cells: List<int>.filled(width * height, 0),
        ),
      );
      _selectedFrameIndex = index;
      return true;
    });
  }

  void duplicateFrame() {
    _mutate(() {
      final source = selectedFrame;
      final index = _selectedFrameIndex + 1;
      _frames.insert(
        index,
        source.copyWith(id: _nextFrameId(), cells: source.cells),
      );
      _selectedFrameIndex = index;
      return true;
    });
  }

  void deleteSelectedFrame() {
    if (_frames.length == 1) return;
    _mutate(() {
      _frames.removeAt(_selectedFrameIndex);
      _selectedFrameIndex = _selectedFrameIndex.clamp(0, _frames.length - 1);
      return true;
    });
  }

  void moveSelectedFrame(int delta) {
    final target = (_selectedFrameIndex + delta).clamp(0, _frames.length - 1);
    if (target == _selectedFrameIndex) return;
    _mutate(() {
      final frame = _frames.removeAt(_selectedFrameIndex);
      _frames.insert(target, frame);
      _selectedFrameIndex = target;
      return true;
    });
  }

  void adjustDuration(int deltaMs) {
    final duration = (selectedFrame.durationMs + deltaMs).clamp(40, 2000);
    if (duration == selectedFrame.durationMs) return;
    _mutate(() {
      _replaceSelected(selectedFrame.copyWith(durationMs: duration));
      return true;
    });
  }

  void togglePlayback() {
    _playing = !_playing;
    notifyListeners();
  }

  /// Resolves the displayed frame from elapsed playback time. No wall clock is
  /// consulted, so tests and browser/native hosts get identical sequencing.
  int playbackFrameIndexAt(Duration elapsed) {
    if (_frames.length == 1) return 0;
    final cycleMs = _frames.fold<int>(
      0,
      (total, frame) => total + frame.durationMs,
    );
    var remaining = elapsed.inMilliseconds % cycleMs;
    for (var offset = 0; offset < _frames.length; offset++) {
      final index = (_selectedFrameIndex + offset) % _frames.length;
      final duration = _frames[index].durationMs;
      if (remaining < duration) return index;
      remaining -= duration;
    }
    return _selectedFrameIndex;
  }

  void undo() {
    endStroke();
    if (_undo.isEmpty) return;
    _redo.add(_capture());
    _restore(_undo.removeLast());
    notifyListeners();
  }

  void redo() {
    endStroke();
    if (_redo.isEmpty) return;
    _undo.add(_capture());
    _restore(_redo.removeLast());
    notifyListeners();
  }

  /// Stable, canonical JSON. Map insertion order is intentional and tested:
  /// an export-import-export round trip is byte-identical.
  String exportPortable() {
    return jsonEncode(<String, Object?>{
      'format': 'fleury.ansi-sprite',
      'version': 1,
      'width': width,
      'height': height,
      'palette': <String>[
        for (final rgb in paletteRgb)
          rgb.toRadixString(16).padLeft(6, '0').toUpperCase(),
      ],
      'frames': <Object?>[
        for (final frame in _frames)
          <String, Object?>{
            'id': frame.id,
            'durationMs': frame.durationMs,
            'rows': _encodeRows(frame.cells, width: width, height: height),
          },
      ],
    });
  }

  bool _applyTool(int x, int y) {
    _checkCell(x, y);
    return switch (_tool) {
      AnsiSpriteTool.pencil => _writeCell(x, y, _selectedColorIndex),
      AnsiSpriteTool.erase => _writeCell(x, y, 0),
      AnsiSpriteTool.fill => _floodFill(x, y, _selectedColorIndex),
    };
  }

  bool _writeCell(int x, int y, int value) {
    final frame = selectedFrame;
    final index = y * width + x;
    if (frame.cells[index] == value) return false;
    final cells = List<int>.of(frame.cells)..[index] = value;
    _replaceSelected(frame.copyWith(cells: cells));
    return true;
  }

  bool _floodFill(int startX, int startY, int value) {
    final frame = selectedFrame;
    final start = startY * width + startX;
    final target = frame.cells[start];
    if (target == value) return false;
    final cells = List<int>.of(frame.cells);
    final pending = <int>[start];
    cells[start] = value;
    while (pending.isNotEmpty) {
      final index = pending.removeLast();
      final x = index % width;
      final y = index ~/ width;
      void visit(int next) {
        if (cells[next] != target) return;
        cells[next] = value;
        pending.add(next);
      }

      if (x > 0) visit(index - 1);
      if (x + 1 < width) visit(index + 1);
      if (y > 0) visit(index - width);
      if (y + 1 < height) visit(index + width);
    }
    _replaceSelected(frame.copyWith(cells: cells));
    return true;
  }

  void _replaceSelected(AnsiSpriteFrame frame) {
    _frames[_selectedFrameIndex] = frame;
  }

  void _mutate(bool Function() operation) {
    endStroke();
    final before = _capture();
    if (!operation()) return;
    _playing = false;
    _undo.add(before);
    _redo.clear();
    notifyListeners();
  }

  _SpriteSnapshot _capture() {
    return _SpriteSnapshot(
      frames: List<AnsiSpriteFrame>.of(_frames),
      selectedFrameId: selectedFrame.id,
    );
  }

  void _restore(_SpriteSnapshot snapshot) {
    _frames = List<AnsiSpriteFrame>.of(snapshot.frames);
    final selected = _frames.indexWhere(
      (frame) => frame.id == snapshot.selectedFrameId,
    );
    _selectedFrameIndex = selected < 0 ? 0 : selected;
    _playing = false;
  }

  String _nextFrameId() {
    final ids = _frames.map((frame) => frame.id).toSet();
    var number = 1;
    while (ids.contains('frame-$number')) {
      number++;
    }
    return 'frame-$number';
  }

  void _checkCell(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw RangeError('Cell ($x, $y) is outside $width×$height.');
    }
  }

  static void _validateDocument({
    required int width,
    required int height,
    required List<int> paletteRgb,
    required List<AnsiSpriteFrame> frames,
  }) {
    if (width < 1 || width > 16 || height < 1 || height > 12) {
      throw const FormatException(
        'Sprite dimensions must be within 1×1 and 16×12.',
      );
    }
    if (paletteRgb.isEmpty || paletteRgb.length > 35) {
      throw const FormatException(
        'Sprite palette must contain between 1 and 35 colors.',
      );
    }
    if (paletteRgb.any((rgb) => rgb < 0 || rgb > 0xffffff)) {
      throw const FormatException('Palette colors must be 24-bit RGB values.');
    }
    if (frames.isEmpty) {
      throw const FormatException('Sprite must contain at least one frame.');
    }
    final ids = <String>{};
    for (final frame in frames) {
      if (!ids.add(frame.id)) {
        throw FormatException('Duplicate frame id "${frame.id}".');
      }
      if (frame.durationMs < 40 || frame.durationMs > 2000) {
        throw FormatException(
          'Frame "${frame.id}" duration must be 40–2000 ms.',
        );
      }
      if (frame.cells.length != width * height) {
        throw FormatException(
          'Frame "${frame.id}" has ${frame.cells.length} cells; '
          'expected ${width * height}.',
        );
      }
      if (frame.cells.any((cell) => cell < 0 || cell > paletteRgb.length)) {
        throw FormatException(
          'Frame "${frame.id}" contains an unknown palette index.',
        );
      }
    }
  }

  static int _requiredInt(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! int) {
      throw FormatException('Sprite "$key" must be an integer.');
    }
    return value;
  }

  static int _parseRgb(Object? value) {
    if (value is! String || !RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(value)) {
      throw const FormatException(
        'Palette colors must use six hexadecimal RGB digits.',
      );
    }
    return int.parse(value, radix: 16);
  }

  static List<int> _decodeRows(
    List<String> rows, {
    required int width,
    required int height,
    required int paletteLength,
  }) {
    if (rows.length != height) {
      throw FormatException('Frame has ${rows.length} rows; expected $height.');
    }
    final cells = <int>[];
    for (final row in rows) {
      final glyphs = row.runes.toList(growable: false);
      if (glyphs.length != width) {
        throw FormatException(
          'Frame row has ${glyphs.length} cells; expected $width.',
        );
      }
      for (final rune in glyphs) {
        final value = _decodeCellRune(rune);
        if (value < 0 || value > paletteLength) {
          throw FormatException(
            'Frame row contains palette index $value, but only '
            '$paletteLength colors exist.',
          );
        }
        cells.add(value);
      }
    }
    return cells;
  }

  static int _decodeCellRune(int rune) {
    if (rune >= 0x30 && rune <= 0x39) return rune - 0x30;
    if (rune >= 0x41 && rune <= 0x5a) return rune - 0x41 + 10;
    throw FormatException(
      'Frame rows use only canonical 0–9/A–Z palette digits.',
    );
  }

  static List<String> _encodeRows(
    List<int> cells, {
    required int width,
    required int height,
  }) {
    return <String>[
      for (var y = 0; y < height; y++)
        String.fromCharCodes(<int>[
          for (var x = 0; x < width; x++) _encodeCellRune(cells[y * width + x]),
        ]),
    ];
  }

  static int _encodeCellRune(int value) =>
      value < 10 ? 0x30 + value : 0x41 + value - 10;
}

final class _SpriteSnapshot {
  const _SpriteSnapshot({required this.frames, required this.selectedFrameId});

  final List<AnsiSpriteFrame> frames;
  final String selectedFrameId;
}
