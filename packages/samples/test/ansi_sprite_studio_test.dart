import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

import '../lib/src/ansi_sprite_model.dart';
import '../lib/src/ansi_sprite_studio.dart';

void main() {
  group('AnsiSpriteModel', () {
    test('pencil, erase, and fill perform real cell edits', () {
      final model = AnsiSpriteModel.fleury();
      addTearDown(model.dispose);

      model.addFrame();
      expect(model.selectedFrame.cells, everyElement(0));

      model.selectColor(2);
      model.selectTool(AnsiSpriteTool.fill);
      model.applyAtCursor();
      expect(model.selectedFrame.cells, everyElement(2));

      model.selectTool(AnsiSpriteTool.erase);
      model.applyAtCursor();
      expect(model.cellAt(model.cursorX, model.cursorY), 0);
      expect(
        model.selectedFrame.cells.where((cell) => cell == 2),
        hasLength(model.width * model.height - 1),
      );
    });

    test('one mouse stroke has byte-identical undo and redo', () {
      final model = AnsiSpriteModel.fleury();
      addTearDown(model.dispose);
      final before = model.exportPortable();

      model.beginStroke();
      model.paintStrokeCell(0, 0);
      model.paintStrokeCell(1, 0);
      model.endStroke();
      final after = model.exportPortable();
      expect(after, isNot(before));

      model.undo();
      expect(model.exportPortable(), before);
      model.redo();
      expect(model.exportPortable(), after);
    });

    test('duplicate and reorder preserve stable keyed frame identity', () {
      final model = AnsiSpriteModel.fleury();
      addTearDown(model.dispose);
      final source = model.selectedFrame;

      model.duplicateFrame();
      final duplicateId = model.selectedFrame.id;
      expect(duplicateId, isNot(source.id));
      expect(model.frames.map((frame) => frame.id).toSet(), hasLength(5));
      expect(model.selectedFrame.cells, source.cells);

      model.moveSelectedFrame(1);
      expect(model.selectedFrame.id, duplicateId);
      expect(model.frames[2].id, duplicateId);

      model.undo();
      expect(model.selectedFrame.id, duplicateId);
      expect(model.frames[1].id, duplicateId);
    });

    test('playback honors per-frame duration and selected starting frame', () {
      final model = AnsiSpriteModel.fleury();
      addTearDown(model.dispose);

      model.togglePlayback();
      expect(model.isPlaying, isTrue);
      expect(model.playbackFrameIndexAt(Duration.zero), 0);
      expect(model.playbackFrameIndexAt(const Duration(milliseconds: 139)), 0);
      expect(model.playbackFrameIndexAt(const Duration(milliseconds: 140)), 1);
      expect(model.playbackFrameIndexAt(const Duration(milliseconds: 319)), 1);
      expect(model.playbackFrameIndexAt(const Duration(milliseconds: 320)), 2);
      expect(model.playbackFrameIndexAt(const Duration(milliseconds: 600)), 0);

      model.selectFrame(2);
      expect(model.isPlaying, isFalse);
      expect(model.playbackFrameIndexAt(Duration.zero), 2);
    });

    test('portable export-import-export is byte-identical', () {
      final model = AnsiSpriteModel.fleury();
      addTearDown(model.dispose);
      model.duplicateFrame();
      model.adjustDuration(40);
      model.moveSelectedFrame(1);
      model.selectColor(5);
      model.setCursor(0, 0);
      model.applyAtCursor();

      final encoded = model.exportPortable();
      final imported = AnsiSpriteModel.fromPortable(encoded);
      addTearDown(imported.dispose);

      expect(imported.exportPortable(), encoded);
      expect(imported.width, model.width);
      expect(imported.height, model.height);
      expect(
        imported.frames.map((frame) => frame.id),
        model.frames.map((frame) => frame.id),
      );
    });
  });

  group('AnsiSpriteStudioApp', () {
    const size = CellSize(120, 40);
    const mint = RgbColor(0x3d, 0xdc, 0x97);

    testWidgets('renders a polished editor and full-cell sprite colors', (
      tester,
    ) {
      tester.pumpWidget(const AnsiSpriteStudioApp());
      final buffer = tester.render(size: size);
      final output = tester.renderToString(size: size);

      expect(output, contains('ANSI Sprite Studio'));
      expect(output, contains('Cell canvas'));
      expect(output, contains('Live preview'));
      expect(output, contains('Copy JSON'));
      expect(output, contains('Frames'));

      var mintCells = 0;
      for (var row = 0; row < size.rows; row++) {
        for (var col = 0; col < size.cols; col++) {
          if (buffer.atColRow(col, row).style.background == mint) {
            mintCells++;
          }
        }
      }
      expect(
        mintCells,
        greaterThan(10),
        reason: 'sprite pixels are painted as full background cells',
      );

      final canvas = tester.semantics().single(
        role: SemanticRole.image,
        label: 'Editable sprite canvas',
      );
      expect(canvas.bounds?.size, const CellSize(24, 8));
      expect(canvas.state['spriteWidth'], 12);
      expect(canvas.state['spriteHeight'], 8);
    });

    testWidgets(
      'mouse coordinates map through painted bounds to sprite cells',
      (tester) {
        tester.pumpWidget(const AnsiSpriteStudioApp());
        final before = tester.render(size: size);
        final canvas = tester.semantics().single(
          role: SemanticRole.image,
          label: 'Editable sprite canvas',
        );
        final bounds = canvas.bounds!;
        expect(
          before.atColRow(bounds.left, bounds.top).style.background,
          isNot(mint),
          reason: 'the top-left cell begins transparent',
        );

        tester.sendMouse(
          MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: bounds.left,
            row: bounds.top,
          ),
        );
        tester.sendMouse(
          MouseEvent(
            kind: MouseEventKind.up,
            button: MouseButton.left,
            col: bounds.left,
            row: bounds.top,
          ),
        );

        final after = tester.render(size: size);
        expect(after.atColRow(bounds.left, bounds.top).style.background, mint);
        expect(
          after.atColRow(bounds.left + 1, bounds.top).style.background,
          mint,
        );
        expect(after.atColRow(bounds.left, bounds.top).grapheme, '[');
        expect(after.atColRow(bounds.left + 1, bounds.top).grapheme, ']');

        final rightClickCol = bounds.left + 2;
        final transparent = after
            .atColRow(rightClickCol, bounds.top)
            .style
            .background;
        tester.sendMouse(
          MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.right,
            col: rightClickCol,
            row: bounds.top,
          ),
        );
        tester.sendMouse(
          MouseEvent(
            kind: MouseEventKind.up,
            button: MouseButton.right,
            col: rightClickCol,
            row: bounds.top,
          ),
        );
        expect(
          tester
              .render(size: size)
              .atColRow(rightClickCol, bounds.top)
              .style
              .background,
          transparent,
          reason: 'secondary clicks must not paint',
        );
      },
    );

    testWidgets('a sparse drag event paints a gapless, captured stroke', (
      tester,
    ) {
      tester.pumpWidget(const AnsiSpriteStudioApp());
      tester.render(size: size);
      final bounds = tester
          .semantics()
          .single(role: SemanticRole.image, label: 'Editable sprite canvas')
          .bounds!;
      final row = bounds.top + 7;

      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: bounds.left,
          row: row,
        ),
      );
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.drag,
          button: MouseButton.left,
          col: bounds.left + 4,
          row: row,
        ),
      );
      tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: bounds.left + 4,
          row: row,
        ),
      );

      final after = tester.render(size: size);
      for (var spriteX = 0; spriteX <= 2; spriteX++) {
        expect(
          after.atColRow(bounds.left + spriteX * 2, row).style.background,
          mint,
          reason: 'interpolated sprite cell $spriteX is painted',
        );
      }
    });

    testWidgets('arrow keys and Space edit the focused canvas', (tester) {
      tester.pumpWidget(const AnsiSpriteStudioApp());
      tester.render(size: size);
      final bounds = tester
          .semantics()
          .single(role: SemanticRole.image, label: 'Editable sprite canvas')
          .bounds!;

      for (var i = 0; i < 6; i++) {
        tester.sendKey(const KeyEvent(KeyCode.arrowLeft));
      }
      for (var i = 0; i < 4; i++) {
        tester.sendKey(const KeyEvent(KeyCode.arrowUp));
      }
      tester.sendKey(const KeyEvent(KeyCode.space));

      final after = tester.render(size: size);
      expect(after.atColRow(bounds.left, bounds.top).style.background, mint);
      expect(after.atColRow(bounds.left, bounds.top).grapheme, '[');
    });

    testWidgets(
      'Play advances the live preview and Pause returns to selection',
      (tester) {
        tester.pumpWidget(const AnsiSpriteStudioApp());
        expect(tester.renderToString(size: size), contains('frame-1  140 ms'));

        tester.sendKey(const KeyEvent(KeyCode.r));
        tester.render(size: size); // rebuild with the preview ticker enabled
        tester.pump(const Duration(milliseconds: 160));
        expect(tester.renderToString(size: size), contains('frame-2  180 ms'));

        tester.sendKey(const KeyEvent(KeyCode.r));
        expect(tester.renderToString(size: size), contains('frame-1  140 ms'));
      },
    );

    testWidgets('Ctrl+C copies canonical JSON through the host clipboard', (
      tester,
    ) {
      tester.pumpWidget(const AnsiSpriteStudioApp());
      tester.render(size: size);

      tester.press(KeySequence.ctrl.c);
      final copied = (tester.clipboard as InProcessClipboard).lastWritten;

      expect(copied, isNotNull);
      final imported = AnsiSpriteModel.fromPortable(copied!);
      addTearDown(imported.dispose);
      expect(imported.exportPortable(), copied);
    });

    testWidgets('Import opens an explicit focused-paste workflow', (tester) {
      tester.pumpWidget(const AnsiSpriteStudioApp());
      tester.render(size: size);

      tester.press(KeyCode.i);
      final output = tester.renderToString(size: size);

      expect(output, contains('Paste portable sprite JSON'));
      expect(output, contains('Ctrl+A, paste, then press Enter'));
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.textField, label: 'Portable sprite JSON')
            .focused,
        isTrue,
      );

      tester.sendKey(const KeyEvent(KeyCode.enter));
      expect(
        tester.renderToString(size: size),
        contains('Imported 4 frames losslessly from JSON'),
      );
    });
  });
}
