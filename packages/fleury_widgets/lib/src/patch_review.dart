import 'dart:async' show scheduleMicrotask, unawaited;

import 'package:fleury/fleury_host.dart';

import 'diff_view.dart';

/// Protocol-neutral review status for a patch or one patch file.
enum PatchReviewStatus {
  pending,
  reviewing,
  approved,
  changesRequested,
  rejected,
  applied,
  failed,
  skipped,
}

/// One file entry in a [PatchReview].
final class PatchReviewFile {
  const PatchReviewFile({
    required this.path,
    this.id,
    this.fileIndex,
    this.oldPath,
    this.newPath,
    this.summary,
    this.status = PatchReviewStatus.pending,
    this.additions = 0,
    this.deletions = 0,
    this.hunks = 0,
    this.enabled = true,
    this.metadata = const <String, Object?>{},
  }) : assert(additions >= 0),
       assert(deletions >= 0),
       assert(hunks >= 0);

  /// Display and semantic path for the file.
  final String path;

  /// Optional stable identity used by semantics, selection, and callbacks.
  final Object? id;

  /// Parsed diff file index when this entry was derived from a [DiffDocument].
  final int? fileIndex;

  final String? oldPath;
  final String? newPath;
  final String? summary;
  final PatchReviewStatus status;
  final int additions;
  final int deletions;
  final int hunks;
  final bool enabled;
  final Map<String, Object?> metadata;

  String get displayId => (id ?? path).toString();
}

/// Controller for [PatchReview] file selection and viewport state.
class PatchReviewController extends ChangeNotifier {
  PatchReviewController({int selectedIndex = 0})
    : _list = ListController(selectedIndex: selectedIndex) {
    _list.addListener(notifyListeners);
  }

  final ListController _list;
  bool _disposed = false;

  ListController get _listController => _list;

  int? get selectedIndex => _list.selectedIndex;
  set selectedIndex(int? value) {
    _checkNotDisposed();
    _list.selectedIndex = value;
  }

  ({int first, int last})? get visibleRange => _list.visibleRange;

  void jumpToIndex(int index) {
    _checkNotDisposed();
    _list.jumpToIndex(index);
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('PatchReviewController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _list.removeListener(notifyListeners);
    _list.dispose();
    super.dispose();
  }
}

/// Clipboard/export behavior for [PatchReview] selected-file copy.
final class PatchReviewCopyOptions {
  const PatchReviewCopyOptions({
    this.includeSummary = true,
    this.includeStats = true,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  });

  final bool includeSummary;
  final bool includeStats;
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after [PatchReview] copies the selected file summary.
final class PatchReviewCopyResult {
  const PatchReviewCopyResult({
    required this.fileIndex,
    required this.file,
    required this.text,
    required this.report,
  });

  final int fileIndex;
  final PatchReviewFile file;
  final String text;
  final ClipboardWriteReport report;
}

/// Result delivered after [PatchReview] activates a file row.
final class PatchReviewFileSelectResult {
  const PatchReviewFileSelectResult({
    required this.fileIndex,
    required this.file,
  });

  final int fileIndex;
  final PatchReviewFile file;
}

/// Builds file-level patch review entries from a parsed unified diff.
List<PatchReviewFile> buildPatchReviewFiles(
  DiffDocument document, {
  Map<String, PatchReviewStatus> statusByPath =
      const <String, PatchReviewStatus>{},
  Map<String, String> summariesByPath = const <String, String>{},
}) {
  final builders = <int, _PatchFileBuilder>{};
  for (final row in document.rows) {
    final fileIndex = row.fileIndex;
    if (fileIndex == null) continue;
    final builder = builders.putIfAbsent(
      fileIndex,
      () => _PatchFileBuilder(fileIndex: fileIndex),
    );
    if (row.oldPath != null) builder.oldPath = row.oldPath;
    if (row.newPath != null) builder.newPath = row.newPath;
    switch (row.kind) {
      case DiffLineKind.addition:
        builder.additions += 1;
      case DiffLineKind.deletion:
        builder.deletions += 1;
      case _:
        break;
    }
    if (row.hunkIndex != null) builder.hunkIndexes.add(row.hunkIndex!);
  }

  final indexes = builders.keys.toList()..sort();
  return List<PatchReviewFile>.unmodifiable([
    for (final index in indexes)
      builders[index]!.build(
        statusByPath: statusByPath,
        summariesByPath: summariesByPath,
      ),
  ]);
}

/// Exports one [PatchReviewFile] as sanitized clipboard/debug text.
String exportPatchReviewFile(
  PatchReviewFile file, {
  PatchReviewCopyOptions options = const PatchReviewCopyOptions(),
}) {
  final parts = <String>[
    _sanitizePatchText(file.path),
    file.status.name,
    if (options.includeStats)
      '+${file.additions} -${file.deletions} ${file.hunks} hunks',
    if (options.includeSummary && file.summary != null)
      _sanitizePatchText(file.summary!),
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' | ');
}

/// Protocol-neutral patch review surface for developer-tool workflows.
class PatchReview extends StatefulWidget {
  factory PatchReview({
    Key? key,
    required String diff,
    List<PatchReviewFile>? files,
    Object? patchId,
    PatchReviewStatus status = PatchReviewStatus.pending,
    PatchReviewController? controller,
    DiffViewController? diffController,
    FocusNode? focusNode,
    FocusNode? diffFocusNode,
    bool autofocus = false,
    bool diffAutofocus = false,
    String label = 'Patch review',
    int maxVisibleFiles = 4,
    int diffHeight = 10,
    bool showDiff = true,
    bool copySelection = true,
    PatchReviewCopyOptions copyOptions = const PatchReviewCopyOptions(),
    DiffViewCopyOptions diffCopyOptions = const DiffViewCopyOptions(),
    void Function(PatchReviewFileSelectResult result)? onSelectFile,
    void Function(PatchReviewCopyResult result)? onCopyFile,
    void Function(DiffViewCopyResult result)? onDiffCopy,
  }) {
    final document = parseUnifiedDiff(diff);
    return PatchReview.document(
      key: key,
      document: document,
      files: files ?? buildPatchReviewFiles(document),
      patchId: patchId,
      status: status,
      controller: controller,
      diffController: diffController,
      focusNode: focusNode,
      diffFocusNode: diffFocusNode,
      autofocus: autofocus,
      diffAutofocus: diffAutofocus,
      label: label,
      maxVisibleFiles: maxVisibleFiles,
      diffHeight: diffHeight,
      showDiff: showDiff,
      copySelection: copySelection,
      copyOptions: copyOptions,
      diffCopyOptions: diffCopyOptions,
      onSelectFile: onSelectFile,
      onCopyFile: onCopyFile,
      onDiffCopy: onDiffCopy,
    );
  }

  const PatchReview.document({
    super.key,
    required this.document,
    required this.files,
    this.patchId,
    this.status = PatchReviewStatus.pending,
    this.controller,
    this.diffController,
    this.focusNode,
    this.diffFocusNode,
    this.autofocus = false,
    this.diffAutofocus = false,
    this.label = 'Patch review',
    this.maxVisibleFiles = 4,
    this.diffHeight = 10,
    this.showDiff = true,
    this.copySelection = true,
    this.copyOptions = const PatchReviewCopyOptions(),
    this.diffCopyOptions = const DiffViewCopyOptions(),
    this.onSelectFile,
    this.onCopyFile,
    this.onDiffCopy,
  }) : assert(maxVisibleFiles > 0),
       assert(diffHeight > 0);

  final DiffDocument document;
  final List<PatchReviewFile> files;
  final Object? patchId;
  final PatchReviewStatus status;
  final PatchReviewController? controller;
  final DiffViewController? diffController;
  final FocusNode? focusNode;
  final FocusNode? diffFocusNode;
  final bool autofocus;
  final bool diffAutofocus;
  final String label;
  final int maxVisibleFiles;
  final int diffHeight;
  final bool showDiff;
  final bool copySelection;
  final PatchReviewCopyOptions copyOptions;
  final DiffViewCopyOptions diffCopyOptions;
  final void Function(PatchReviewFileSelectResult result)? onSelectFile;
  final void Function(PatchReviewCopyResult result)? onCopyFile;
  final void Function(DiffViewCopyResult result)? onDiffCopy;

  @override
  State<PatchReview> createState() => _PatchReviewState();
}

class _PatchReviewState extends State<PatchReview> {
  late PatchReviewController _controller;
  late DiffViewController _diffController;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsDiffController = false;
  bool _ownsFocusNode = false;
  bool _focusedWithin = false;
  Object? _pendingSelectedPatchFileIdentity;
  int _selectionSyncGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? PatchReviewController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChange);
    _diffController = widget.diffController ?? DiffViewController();
    _ownsDiffController = widget.diffController == null;
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'PatchReview');
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(covariant PatchReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? PatchReviewController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChange);
    }
    if (widget.diffController != oldWidget.diffController) {
      if (_ownsDiffController) _diffController.dispose();
      _diffController = widget.diffController ?? DiffViewController();
      _ownsDiffController = widget.diffController == null;
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'PatchReview');
      _ownsFocusNode = widget.focusNode == null;
    }
    if (widget.files != oldWidget.files) {
      _syncSelectionAfterFileUpdate(oldWidget.files);
    }
  }

  void _onControllerChange() => setState(() {});

  void _syncSelectionAfterFileUpdate(List<PatchReviewFile> oldFiles) {
    _selectionSyncGeneration++;
    _pendingSelectedPatchFileIdentity = null;
    if (widget.files.isEmpty) {
      _controller.selectedIndex = null;
      return;
    }
    final selectedIndex = _controller.selectedIndex;
    if (selectedIndex == null) {
      _controller.selectedIndex = 0;
      return;
    }
    if (selectedIndex >= 0 && selectedIndex < oldFiles.length) {
      final selectedIdentity = _fileIdentity(oldFiles[selectedIndex]);
      final nextIndex = widget.files.indexWhere(
        (file) => _fileIdentity(file) == selectedIdentity,
      );
      if (nextIndex != -1) {
        _selectIndexAfterListCountRefresh(selectedIdentity, nextIndex);
        return;
      }
    }
    _controller.selectedIndex = selectedIndex.clamp(0, widget.files.length - 1);
  }

  void _selectIndexAfterListCountRefresh(
    Object selectedIdentity,
    int nextIndex,
  ) {
    final knownItemCount = _controller._listController.itemCount;
    if (knownItemCount == 0 || nextIndex < knownItemCount) {
      _controller.selectedIndex = nextIndex;
      return;
    }

    _pendingSelectedPatchFileIdentity = selectedIdentity;
    final generation = _selectionSyncGeneration;
    final binding = TuiBinding.maybeOf(context);
    if (binding == null) {
      scheduleMicrotask(() {
        _applyPendingSelection(generation, selectedIdentity);
      });
      return;
    }
    binding.addPostFrameCallback((_) {
      _applyPendingSelection(generation, selectedIdentity);
    });
  }

  void _applyPendingSelection(int generation, Object selectedIdentity) {
    if (!mounted || generation != _selectionSyncGeneration) return;
    if (_pendingSelectedPatchFileIdentity != selectedIdentity) return;
    final nextIndex = widget.files.indexWhere(
      (file) => _fileIdentity(file) == selectedIdentity,
    );
    if (nextIndex == -1) {
      _pendingSelectedPatchFileIdentity = null;
      return;
    }
    _pendingSelectedPatchFileIdentity = null;
    _controller.selectedIndex = nextIndex;
  }

  void _onFocusWithinChange(bool focused) {
    if (_focusedWithin == focused) return;
    setState(() {
      _focusedWithin = focused;
    });
  }

  Future<void> _copySelection() async {
    if (!widget.copySelection || widget.files.isEmpty) return;
    final selected = (_controller.selectedIndex ?? 0).clamp(
      0,
      widget.files.length - 1,
    );
    final file = widget.files[selected];
    final text = exportPatchReviewFile(file, options: widget.copyOptions);
    final report = await Clipboard.instance.writeWithReport(
      text,
      policy: widget.copyOptions.clipboardPolicy,
    );
    if (!mounted) return;
    widget.onCopyFile?.call(
      PatchReviewCopyResult(
        fileIndex: selected,
        file: file,
        text: text,
        report: report,
      ),
    );
  }

  void _selectCurrent() {
    if (widget.files.isEmpty) return;
    _focusNode.requestFocus();
    final selected = (_controller.selectedIndex ?? 0).clamp(
      0,
      widget.files.length - 1,
    );
    final file = widget.files[selected];
    if (!file.enabled) return;
    _jumpDiffToFile(file);
    widget.onSelectFile?.call(
      PatchReviewFileSelectResult(fileIndex: selected, file: file),
    );
  }

  Future<void> _selectAt(int index) async {
    if (index < 0 || index >= widget.files.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
    _selectCurrent();
  }

  Future<void> _copyAt(int index) async {
    if (index < 0 || index >= widget.files.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
    await _copySelection();
  }

  Future<void> _handleReviewAction(SemanticAction action) async {
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.navigate:
        _focusNode.requestFocus();
        setState(() {});
        return;
      case SemanticAction.submit:
        _selectCurrent();
        return;
      case SemanticAction.copy:
        await _copySelection();
        return;
      case _:
        return;
    }
  }

  void _jumpDiffToFile(PatchReviewFile file) {
    final fileIndex = file.fileIndex;
    if (fileIndex == null) return;
    for (final row in widget.document.rows) {
      if (row.fileIndex == fileIndex) {
        _diffController.selectedIndex = row.index;
        _diffController.jumpToIndex(row.index);
        return;
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    if (_ownsController) _controller.dispose();
    if (_ownsDiffController) _diffController.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _controller.selectedIndex;
    final selectedFile =
        selectedIndex == null ||
            selectedIndex < 0 ||
            selectedIndex >= widget.files.length
        ? null
        : widget.files[selectedIndex];
    final visibleRange = _controller.visibleRange;
    final copyEnabled = widget.copySelection && widget.files.isNotEmpty;
    final canSelect = widget.onSelectFile != null;
    final visible = widget.files.isEmpty
        ? 1
        : (widget.files.length > widget.maxVisibleFiles
              ? widget.maxVisibleFiles
              : widget.files.length);

    Widget fileList = widget.files.isEmpty
        ? const Text('No patch files')
        : ListView.builder(
            controller: _controller._listController,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            itemCount: widget.files.length,
            onSelect: (_) => _selectCurrent(),
            itemBuilder: (context, index, activeSelected) {
              final selected = index == _controller.selectedIndex;
              return _PatchFileRow(
                file: widget.files[index],
                index: index,
                selected: selected,
                activeSelection: activeSelected,
                canSelect: canSelect,
                copyEnabled: copyEnabled,
                onSelect: () => _selectAt(index),
                onCopy: () => _copyAt(index),
              );
            },
          );

    if (copyEnabled) {
      fileList = KeyBindings(
        bindings: [
          KeyBinding(
            KeyChord.ctrl.c,
            label: 'Copy patch file',
            onEvent: (_) => unawaited(_copySelection()),
          ),
        ],
        child: fileList,
      );
    }

    final children = <Widget>[
      Text(_summaryText(widget.label, widget.status, widget.files)),
      SizedBox(height: visible, child: fileList),
    ];
    if (widget.showDiff) {
      children.addAll([
        const SizedBox(height: 1),
        SizedBox(
          height: widget.diffHeight,
          child: DiffView.document(
            document: widget.document,
            label: '${widget.label} diff',
            controller: _diffController,
            focusNode: widget.diffFocusNode,
            autofocus: widget.diffAutofocus,
            copyOptions: widget.diffCopyOptions,
            onCopy: widget.onDiffCopy,
          ),
        ),
      ]);
    }

    return FocusWithin(
      onFocusChange: _onFocusWithinChange,
      child: Semantics(
        role: SemanticRole.patchReview,
        label: _sanitizePatchText(widget.label),
        value: widget.status.name,
        focused: _focusedWithin || _focusNode.hasFocus,
        actions: {
          SemanticAction.focus,
          SemanticAction.navigate,
          if (canSelect) SemanticAction.submit,
          if (copyEnabled) SemanticAction.copy,
        },
        onAction: _handleReviewAction,
        state: SemanticState({
          if (widget.patchId != null)
            'patchId': _sanitizePatchText(widget.patchId!.toString()),
          'patchStatus': widget.status.name,
          'patchFileCount': widget.files.length,
          'patchAdditionCount': _totalAdditions(widget.files),
          'patchDeletionCount': _totalDeletions(widget.files),
          'patchHunkCount': _totalHunks(widget.files),
          'approvedPatchFileCount': _statusCount(
            widget.files,
            PatchReviewStatus.approved,
          ),
          'changesRequestedPatchFileCount': _statusCount(
            widget.files,
            PatchReviewStatus.changesRequested,
          ),
          'copyEnabled': copyEnabled,
          'clipboardPolicy': widget.copyOptions.clipboardPolicy.name,
          if (visibleRange != null && widget.files.isNotEmpty) ...{
            'visibleRangeStart': visibleRange.first,
            'visibleRangeEnd': visibleRange.last,
          },
          'selectedIndex': ?selectedIndex,
          if (selectedFile != null) ..._selectedFileState(selectedFile),
        }),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _PatchFileRow extends StatelessWidget {
  const _PatchFileRow({
    required this.file,
    required this.index,
    required this.selected,
    required this.activeSelection,
    required this.canSelect,
    required this.copyEnabled,
    required this.onSelect,
    required this.onCopy,
  });

  final PatchReviewFile file;
  final int index;
  final bool selected;
  final bool activeSelection;
  final bool canSelect;
  final bool copyEnabled;
  final Future<void> Function() onSelect;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final path = _sanitizePatchText(file.path);
    final summary = file.summary == null
        ? null
        : _sanitizePatchText(file.summary!);
    return Semantics(
      role: SemanticRole.patchFile,
      label: path,
      value: file.status.name,
      hint: summary,
      selected: selected,
      enabled: file.enabled,
      actions: {
        if (file.enabled && canSelect) SemanticAction.activate,
        if (selected && copyEnabled) SemanticAction.copy,
      },
      onAction: (action) async {
        switch (action) {
          case SemanticAction.activate:
            if (file.enabled && canSelect) await onSelect();
            return;
          case SemanticAction.copy:
            if (selected && copyEnabled) await onCopy();
            return;
          case _:
            return;
        }
      },
      state: SemanticState({
        ...file.metadata,
        'rowIndex': index,
        'viewIndex': index,
        'rowKey': _sanitizePatchText(file.displayId),
        'patchFilePath': path,
        'patchFileStatus': file.status.name,
        'patchFileAdditionCount': file.additions,
        'patchFileDeletionCount': file.deletions,
        'patchFileHunkCount': file.hunks,
        if (file.fileIndex != null) 'fileIndex': file.fileIndex,
        if (file.oldPath != null) 'oldPath': _sanitizePatchText(file.oldPath!),
        if (file.newPath != null) 'newPath': _sanitizePatchText(file.newPath!),
        'filePath': path,
        'outputSanitized': _fileWasSanitized(file),
      }),
      child: Text(
        _rowText(file, activeSelection: activeSelection),
        style: _rowStyle(
          Theme.of(context),
          selected: selected,
          activeSelection: activeSelection,
          file: file,
        ),
      ),
    );
  }
}

final class _PatchFileBuilder {
  _PatchFileBuilder({required this.fileIndex});

  final int fileIndex;
  String? oldPath;
  String? newPath;
  int additions = 0;
  int deletions = 0;
  final Set<int> hunkIndexes = <int>{};

  PatchReviewFile build({
    required Map<String, PatchReviewStatus> statusByPath,
    required Map<String, String> summariesByPath,
  }) {
    final path = newPath ?? oldPath ?? 'file $fileIndex';
    return PatchReviewFile(
      path: path,
      id: path,
      fileIndex: fileIndex,
      oldPath: oldPath,
      newPath: newPath,
      summary: summariesByPath[path],
      status: statusByPath[path] ?? PatchReviewStatus.pending,
      additions: additions,
      deletions: deletions,
      hunks: hunkIndexes.length,
    );
  }
}

Map<String, Object?> _selectedFileState(PatchReviewFile file) {
  final path = _sanitizePatchText(file.path);
  return <String, Object?>{
    'selectedKey': _sanitizePatchText(file.displayId),
    'selectedPatchFilePath': path,
    'selectedPatchFileStatus': file.status.name,
    'selectedPatchFileAdditionCount': file.additions,
    'selectedPatchFileDeletionCount': file.deletions,
    'selectedPatchFileHunkCount': file.hunks,
  };
}

Object _fileIdentity(PatchReviewFile file) => file.id ?? file.path;

String _summaryText(
  String label,
  PatchReviewStatus status,
  List<PatchReviewFile> files,
) {
  final safeLabel = _sanitizePatchText(label);
  return '$safeLabel: ${files.length} files  +${_totalAdditions(files)}'
      ' -${_totalDeletions(files)}  ${_totalHunks(files)} hunks'
      '  ${status.name}';
}

String _rowText(PatchReviewFile file, {required bool activeSelection}) {
  final prefix = activeSelection ? '> ' : '  ';
  final path = _sanitizePatchText(file.path);
  final parts = <String>[
    file.status.name,
    '+${file.additions}',
    '-${file.deletions}',
    '${file.hunks} hunks',
  ];
  return '$prefix$path  ${parts.join('  ')}';
}

int _totalAdditions(List<PatchReviewFile> files) =>
    files.fold<int>(0, (total, file) => total + file.additions);

int _totalDeletions(List<PatchReviewFile> files) =>
    files.fold<int>(0, (total, file) => total + file.deletions);

int _totalHunks(List<PatchReviewFile> files) =>
    files.fold<int>(0, (total, file) => total + file.hunks);

int _statusCount(List<PatchReviewFile> files, PatchReviewStatus status) {
  return files.fold<int>(
    0,
    (total, file) => total + (file.status == status ? 1 : 0),
  );
}

bool _fileWasSanitized(PatchReviewFile file) {
  return _sanitizePatchText(file.displayId) != file.displayId ||
      _sanitizePatchText(file.path) != file.path ||
      (file.oldPath != null &&
          _sanitizePatchText(file.oldPath!) != file.oldPath) ||
      (file.newPath != null &&
          _sanitizePatchText(file.newPath!) != file.newPath) ||
      (file.summary != null &&
          _sanitizePatchText(file.summary!) != file.summary);
}

String _sanitizePatchText(String text) {
  return sanitizeForDisplay(
    text.replaceAll(_patchLineBreakPattern, ' '),
  ).replaceAll(RegExp(' +'), ' ').trim();
}

final _patchLineBreakPattern = RegExp(r'[\r\n\t]');

CellStyle _rowStyle(
  ThemeData theme, {
  required bool selected,
  required bool activeSelection,
  required PatchReviewFile file,
}) {
  if (!file.enabled) return theme.mutedStyle;
  if (activeSelection) return theme.selectionStyle;
  if (selected) return theme.mutedStyle;
  return switch (file.status) {
    PatchReviewStatus.pending => CellStyle.empty,
    PatchReviewStatus.reviewing => const CellStyle(foreground: AnsiColor(14)),
    PatchReviewStatus.approved => const CellStyle(foreground: AnsiColor(10)),
    PatchReviewStatus.changesRequested => const CellStyle(
      foreground: AnsiColor(11),
    ),
    PatchReviewStatus.rejected ||
    PatchReviewStatus.failed => const CellStyle(foreground: AnsiColor(9)),
    PatchReviewStatus.applied => const CellStyle(foreground: AnsiColor(10)),
    PatchReviewStatus.skipped => theme.mutedStyle,
  };
}
