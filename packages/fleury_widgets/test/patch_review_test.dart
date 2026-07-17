import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _sampleDiff = '''
diff --git a/lib/app.dart b/lib/app.dart
index 111..222 100644
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -1,3 +1,4 @@
 void main() {
-  print("old");
+  print("new");
+  run();
 }
diff --git a/test/app_test.dart b/test/app_test.dart
index 333..444 100644
--- a/test/app_test.dart
+++ b/test/app_test.dart
@@ -1,2 +1,2 @@
-expect(old, true);
+expect(newValue, true);
''';

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('PatchReviewController lifecycle', () {
    test('dispose is idempotent and keeps final readable state', () {
      final controller = PatchReviewController(selectedIndex: 1);

      controller.dispose();
      controller.dispose();

      expect(controller.selectedIndex, 1);
      expect(controller.visibleRange, isNull);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final controller = PatchReviewController()..dispose();

      const message = 'PatchReviewController has been disposed.';
      expect(() => controller.selectedIndex = 1, _stateError(message));
      expect(() => controller.jumpToIndex(1), _stateError(message));
    });
  });

  test('buildPatchReviewFiles derives per-file review summaries', () {
    final document = parseUnifiedDiff(_sampleDiff);
    final files = buildPatchReviewFiles(
      document,
      statusByPath: const {
        'lib/app.dart': PatchReviewStatus.approved,
        'test/app_test.dart': PatchReviewStatus.changesRequested,
      },
      summariesByPath: const {'lib/app.dart': 'Runtime shell update'},
    );

    expect(files, hasLength(2));
    expect(files[0].path, 'lib/app.dart');
    expect(files[0].fileIndex, 0);
    expect(files[0].additions, 2);
    expect(files[0].deletions, 1);
    expect(files[0].hunks, 1);
    expect(files[0].status, PatchReviewStatus.approved);
    expect(files[0].summary, 'Runtime shell update');

    expect(files[1].path, 'test/app_test.dart');
    expect(files[1].fileIndex, 1);
    expect(files[1].additions, 1);
    expect(files[1].deletions, 1);
    expect(files[1].status, PatchReviewStatus.changesRequested);
  });

  testWidgets('renders patch summary, file semantics, and diff semantics', (
    tester,
  ) {
    final document = parseUnifiedDiff(_sampleDiff);
    final files = buildPatchReviewFiles(
      document,
      statusByPath: const {'lib/app.dart': PatchReviewStatus.approved},
    );
    tester.pumpWidget(
      PatchReview.document(
        document: document,
        files: files,
        patchId: 'patch-42',
        status: PatchReviewStatus.reviewing,
        label: 'Launch patch',
        onSelectFile: (_) {},
      ),
    );

    final output = tester.renderToString(
      size: const CellSize(100, 18),
      emptyMark: ' ',
    );
    expect(output, contains('Launch patch: 2 files  +3 -2  2 hunks'));
    expect(output, contains('  lib/app.dart'));
    expect(output, isNot(contains('> lib/app.dart')));
    expect(output, contains('test/app_test.dart'));
    expect(output, contains('+  print("new");'));

    final review = tester.semantics().single(
      role: SemanticRole.patchReview,
      label: 'Launch patch',
      action: SemanticAction.copy,
    );
    expect(review.value, 'reviewing');
    expect(review.state.patchId, 'patch-42');
    expect(review.state.patchStatus, 'reviewing');
    expect(review.state['patchFileCount'], 2);
    expect(review.state['patchAdditionCount'], 3);
    expect(review.state['patchDeletionCount'], 2);
    expect(review.state['patchHunkCount'], 2);
    expect(review.state['approvedPatchFileCount'], 1);
    expect(review.state.selectedPatchFilePath, 'lib/app.dart');

    final file = tester.semantics().single(
      role: SemanticRole.patchFile,
      label: 'lib/app.dart',
      selected: true,
      action: SemanticAction.activate,
    );
    expect(file.value, 'approved');
    expect(file.state.patchFilePath, 'lib/app.dart');
    expect(file.state.patchFileStatus, 'approved');
    expect(file.state['patchFileAdditionCount'], 2);
    expect(file.state['patchFileDeletionCount'], 1);

    final diff = tester.semantics().single(
      role: SemanticRole.diff,
      label: 'Launch patch diff',
    );
    expect(diff.state['fileCount'], 2);
    expect(diff.state['hunkCount'], 2);

    final fallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.patchReview,
      label: 'Launch patch',
      state:
          'patch id patch-42, status reviewing, 2 files, 3 additions, '
          '2 deletions, 2 hunks, 1 approved, selected file lib/app.dart',
    );
    expect(fallback.roleLabel, 'patch review');
  });

  group('copy and activation', () {
    testWidgets('semantic copy copies the selected patch file summary', (
      tester,
    ) async {
      final controller = PatchReviewController();
      PatchReviewCopyResult? copied;
      tester.pumpWidget(
        PatchReview(
          diff: _sampleDiff,
          label: 'Launch patch',
          controller: controller,
          copyOptions: const PatchReviewCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopyFile: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(100, 18));
      final result = await tester.invokeSemanticAction(
        SemanticAction.copy,
        role: SemanticRole.patchFile,
        label: 'lib/app.dart',
      );
      await Future<void>.delayed(Duration.zero);

      expect(result.completed, isTrue);
      expect(
        tester.clipboard.readInProcess(),
        'lib/app.dart | pending | +2 -1 1 hunks',
      );
      expect(copied?.file.path, 'lib/app.dart');
      expect(copied?.report.result, ClipboardWriteResult.inProcessOnly);
    });

    testWidgets('semantic activation selects a patch file and jumps the diff', (
      tester,
    ) async {
      final diffController = DiffViewController(selectedIndex: 0);
      PatchReviewFileSelectResult? selected;
      tester.pumpWidget(
        PatchReview(
          diff: _sampleDiff,
          label: 'Launch patch',
          diffController: diffController,
          onSelectFile: (result) => selected = result,
        ),
      );

      tester.render(size: const CellSize(100, 18));
      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.patchFile,
        label: 'test/app_test.dart',
      );

      expect(result.completed, isTrue);
      expect(selected?.file.path, 'test/app_test.dart');
      expect(diffController.selectedIndex, 10);
      final review = tester.semantics().single(
        role: SemanticRole.patchReview,
        label: 'Launch patch',
      );
      expect(review.state.selectedPatchFilePath, 'test/app_test.dart');
    });

    testWidgets('semantic focus and activation focus the patch review', (
      tester,
    ) async {
      final controller = PatchReviewController();
      final diffController = DiffViewController(selectedIndex: 0);
      PatchReviewFileSelectResult? selected;
      tester.pumpWidget(
        PatchReview(
          diff: _sampleDiff,
          label: 'Launch patch',
          controller: controller,
          diffController: diffController,
          onSelectFile: (result) => selected = result,
        ),
      );

      tester.render(size: const CellSize(100, 18));
      var review = tester.semantics().single(
        role: SemanticRole.patchReview,
        label: 'Launch patch',
        action: SemanticAction.focus,
      );
      expect(review.focused, isFalse);
      expect(review.actions, contains(SemanticAction.navigate));

      var result = await tester.invokeSemanticAction(
        SemanticAction.focus,
        role: SemanticRole.patchReview,
        label: 'Launch patch',
      );
      expect(result.completed, isTrue);

      tester.render(size: const CellSize(100, 18));
      review = tester.semantics().single(
        role: SemanticRole.patchReview,
        label: 'Launch patch',
        focused: true,
      );
      expect(review.state.selectedPatchFilePath, 'lib/app.dart');

      result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.patchFile,
        label: 'test/app_test.dart',
      );
      expect(result.completed, isTrue);
      expect(controller.selectedIndex, 1);
      expect(selected?.file.path, 'test/app_test.dart');
      expect(diffController.selectedIndex, 10);

      tester.render(size: const CellSize(100, 18));
      final file = tester.semantics().single(
        role: SemanticRole.patchFile,
        label: 'test/app_test.dart',
        selected: true,
        action: SemanticAction.copy,
      );
      expect(file.state.patchFilePath, 'test/app_test.dart');

      review = tester.semantics().single(
        role: SemanticRole.patchReview,
        label: 'Launch patch',
        focused: true,
      );
      expect(review.state.selectedPatchFilePath, 'test/app_test.dart');
      expect(review.state['selectedIndex'], 1);
    });

    testWidgets('preserves selected patch file identity across file refresh', (
      tester,
    ) {
      final document = parseUnifiedDiff(_sampleDiff);
      final files = buildPatchReviewFiles(document);
      final controller = PatchReviewController(selectedIndex: 1);
      tester.pumpWidget(
        PatchReview.document(
          document: document,
          files: files,
          label: 'Launch patch',
          controller: controller,
        ),
      );
      tester.render(size: const CellSize(100, 18));

      tester.pumpWidget(
        PatchReview.document(
          document: document,
          files: [
            files[0],
            const PatchReviewFile(
              path: 'lib/inserted.dart',
              id: 'inserted',
              status: PatchReviewStatus.pending,
              additions: 1,
            ),
            const PatchReviewFile(
              path: 'test/app_test.dart',
              id: 'test/app_test.dart',
              fileIndex: 1,
              summary: 'Updated test summary',
              status: PatchReviewStatus.approved,
              additions: 3,
              deletions: 1,
              hunks: 2,
            ),
          ],
          label: 'Launch patch',
          controller: controller,
        ),
      );
      tester.render(size: const CellSize(100, 18));
      tester.pump();
      tester.render(size: const CellSize(100, 18));

      expect(controller.selectedIndex, 2);
      final review = tester.semantics().single(
        role: SemanticRole.patchReview,
        label: 'Launch patch',
      );
      expect(review.state.selectedPatchFilePath, 'test/app_test.dart');

      final selected = tester.semantics().single(
        role: SemanticRole.patchFile,
        label: 'test/app_test.dart',
        selected: true,
      );
      expect(selected.value, 'approved');
      expect(selected.hint, 'Updated test summary');
      expect(selected.state['patchFileAdditionCount'], 3);
      expect(selected.state['patchFileHunkCount'], 2);
    });
  });
}
