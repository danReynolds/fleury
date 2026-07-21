// MarkdownText — renders a subset of Markdown to a styled cell block.
//
// Scope is deliberately small: the things users want for help screens,
// chat bubbles, agentic-LLM responses, and `--help` output. No HTML
// passthrough, no tables, no images, no nested blockquotes, no MathML.
// Reach for a full Markdown engine (the `markdown` package) when you
// need that — this widget exists so the common case doesn't drag a
// 400 KB parser into your binary for a paragraph of italics + a
// bullet list.
//
// Supported inline syntax:
//   **bold**          bold
//   *italic*  _it_    italic
//   ~~strike~~        strikethrough
//   `code`            monospace + dim background tone
//   [text](url)       underlined; a real OSC 8 / anchor link when the
//                     surface supports it and the scheme is allow-listed,
//                     with an inspectable " (url)" suffix (opt-out)
//
// Supported block syntax:
//   # H1, ## H2, ### H3   bold headings (sized by underline density)
//   - / * bullet           "• " prefix at indent depth
//   1. 2. 3.               "N. " prefix
//   > blockquote           "│ " prefix, dim
//   ```code fence```       monospace block, no inline parsing inside
//   ---                    horizontal rule (dim ─)
//   blank line             paragraph break
//
// Everything else falls through as plain text. The parser is a single
// pass: line-mode for blocks, regex-driven for inline spans. Fast
// enough to render fresh on every frame for short content (the
// common case); for long markdown documents, render once + cache.

import 'dart:async' show unawaited;

import 'package:characters/characters.dart';
import 'package:fleury/fleury_core.dart';

import 'component_theme.dart';

/// Accent colour for Markdown links — a mint green that reads on dark
/// backgrounds (unlike a browser's default link blue) and matches Fleury's
/// default styling. Applies to safe-scheme links on every surface (terminal
/// OSC 8 text, browser `<a>`), since the browser anchor inherits the cell's
/// foreground.
const Color _kMarkdownLinkColor = RgbColor(126, 217, 149);

/// A widget that renders a [data] string of light Markdown as styled
/// terminal cells.
///
/// Use [baseStyle] to set the default cell style for the block
/// (e.g. dim for help text). Inline overrides cascade on top.
class MarkdownText extends StatelessWidget {
  const MarkdownText(
    this.data, {
    super.key,
    this.baseStyle,
    this.inlineLinkUrls = true,
  });

  /// Light Markdown source rendered by this widget.
  final String data;

  /// Base cell style inherited by the rendered Markdown spans.
  final CellStyle? baseStyle;

  /// Whether a link keeps its inspectable ` (url)` suffix after the text.
  ///
  /// Default true (RFC 0017): the destination stays visible on terminals that
  /// don't honor OSC 8 and auditable everywhere. Set false for the clean-link
  /// look — but the suffix is only dropped when the link is actually *live*
  /// (a real OSC 8 / anchor target was emitted, which makes the visible url
  /// redundant). A link that fell back to plain text — unsupported surface or
  /// un-allow-listed scheme — always keeps its url, so a destination is never
  /// hidden behind a link that doesn't work.
  final bool inlineLinkUrls;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Mirrors FleuryWidgetTheme.resolveMarkdownHeading: primary for H1,
    // info for H2, no tint deeper — emphasis recedes with depth.
    Color? headingColor(int level) => switch (level) {
      1 => cs.primary,
      2 => cs.info,
      _ => null,
    };
    // PRODUCER-SIDE GATE (RFC 0017 §2): only emit a real OSC 8 / anchor link
    // when the presenting surface reports it can render one. A non-supporting
    // terminal reports false, so `linkUri` stays null — the renderer emits
    // nothing and there is no wasted re-emit; the browser surface reports true,
    // so served/embedded peers get anchors. Scheme allow-listing (`_inline`,
    // §6) is the second half of the gate.
    final hyperlinks = MediaQuery.capabilitiesOf(context).hyperlinks;
    final result = _renderBlocks(
      data,
      baseStyle ?? CellStyle.empty,
      headingColor: headingColor,
      hyperlinks: hyperlinks,
      inlineLinkUrls: inlineLinkUrls,
    );
    if (result.lines.isEmpty && result.links.isEmpty) return const EmptyBox();
    final children = <Widget>[
      ...result.lines,
      for (var i = 0; i < result.links.length; i++)
        _linkSemantics(
          result.links[i],
          i,
          osc8Policy: _osc8PolicyFor(result.links[i], hyperlinks: hyperlinks),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// Coarse Markdown block classification used by [MarkdownView].
enum MarkdownBlockKind {
  blank,
  paragraph,
  heading,
  bullet,
  ordered,
  blockquote,
  codeFence,
  horizontalRule,
}

/// Clipboard/export mode for [MarkdownView] selected-block copy.
enum MarkdownViewCopyMode {
  /// Copy the selected sanitized source block.
  block,

  /// Copy the whole sanitized source document.
  document,
}

/// One Markdown link discovered outside fenced code blocks.
final class MarkdownLink {
  const MarkdownLink({
    required this.index,
    required this.blockIndex,
    required this.text,
    required this.url,
  });

  /// Zero-based position of this link in the parsed document.
  final int index;

  /// Zero-based index of the [MarkdownBlock] containing this link.
  final int blockIndex;

  /// Sanitized label displayed for the link.
  final String text;

  /// Sanitized destination parsed from the Markdown source.
  final String url;

  String? get scheme => _urlScheme(url);
  bool get safeScheme => isSafeLinkScheme(url);
}

/// Parsed Markdown rendered by [MarkdownView].
final class MarkdownDocument {
  const MarkdownDocument({
    required this.blocks,
    required this.links,
    required this.source,
    required this.blockCount,
    required this.headingCount,
    required this.listItemCount,
    required this.linkCount,
    required this.codeBlockCount,
    required this.codeLineCount,
  });

  factory MarkdownDocument.parse(
    /// Markdown source to parse.
    String source, {

    /// Maximum grapheme length of each displayed row, or null for no limit.
    int? maxLineLength = 1000,

    /// Number of spaces used to expand each tab.
    int tabSize = 2,
  }) {
    return parseMarkdownDocument(
      source,
      maxLineLength: maxLineLength,
      tabSize: tabSize,
    );
  }

  /// Parsed visible rows in document order.
  final List<MarkdownBlock> blocks;

  /// Links discovered outside fenced code blocks, in document order.
  final List<MarkdownLink> links;

  /// Sanitized Markdown source represented by this document.
  final String source;

  /// Number of parsed rows, including blank rows and fenced-code rows.
  final int blockCount;

  /// Number of heading rows in [blocks].
  final int headingCount;

  /// Number of ordered and unordered list-item rows in [blocks].
  final int listItemCount;

  /// Number of links in [links].
  final int linkCount;

  /// Number of fenced code blocks in the source.
  final int codeBlockCount;

  /// Number of code rows contained by fenced code blocks.
  final int codeLineCount;

  bool get isEmpty => blocks.isEmpty;
}

/// One visible Markdown row in a [MarkdownView].
final class MarkdownBlock {
  const MarkdownBlock({
    required this.index,
    required this.kind,
    required this.sourceText,
    required this.plainText,
    required this.displayText,
    required this.headingLevel,
    required this.listDepth,
    required this.listNumber,
    required this.linkCount,
    required this.outputSanitized,
    required this.outputTruncated,
    required this.outputOriginalLength,
  });

  /// Zero-based position of this row in its [MarkdownDocument].
  final int index;

  /// Parsed block classification for this row.
  final MarkdownBlockKind kind;

  /// Sanitized Markdown source represented by this row.
  final String sourceText;

  /// Text content with supported inline Markdown markers removed.
  final String plainText;

  /// Sanitized, length-limited text passed to the row renderer.
  final String displayText;

  /// Heading level for heading rows, otherwise null.
  final int? headingLevel;

  /// Leading-space indentation recorded for a list item.
  final int listDepth;

  /// Source number for an ordered-list item, otherwise null.
  final int? listNumber;

  /// Number of links discovered in this row.
  final int linkCount;

  /// Whether control-character sanitization changed the source row.
  final bool outputSanitized;

  /// Whether [displayText] was shortened to the configured line limit.
  final bool outputTruncated;

  /// UTF-16 length of the source row before sanitization and truncation.
  final int outputOriginalLength;
}

/// Controller for [MarkdownView] selection.
class MarkdownViewController extends ChangeNotifier {
  MarkdownViewController({
    /// Zero-based block selected when the controller is created.
    int selectedIndex = 0,
  }) : _list = ListController(selectedIndex: selectedIndex) {
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
      throw StateError('MarkdownViewController has been disposed.');
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

/// Options for copying from [MarkdownView].
final class MarkdownViewCopyOptions {
  const MarkdownViewCopyOptions({
    this.mode = MarkdownViewCopyMode.block,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  });

  /// Scope of Markdown source exported by a copy action.
  final MarkdownViewCopyMode mode;

  /// Clipboard policy applied to the exported text.
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after [MarkdownView] copies Markdown text.
final class MarkdownViewCopyResult {
  const MarkdownViewCopyResult({
    required this.blockIndex,
    required this.block,
    required this.text,
    required this.report,
  });

  /// Zero-based index of the block selected when copying occurred.
  final int blockIndex;

  /// Block selected when copying occurred.
  final MarkdownBlock block;

  /// Sanitized Markdown source submitted to the clipboard writer.
  final String text;

  /// Outcome reported by the clipboard writer.
  final ClipboardWriteReport report;
}

/// Parses light Markdown into sanitized visible [MarkdownBlock] rows.
MarkdownDocument parseMarkdownDocument(
  String source, {
  int? maxLineLength = 1000,
  int tabSize = 2,
}) {
  assert(tabSize > 0);
  final rawLines = source.split('\n');
  if (rawLines.isNotEmpty && rawLines.last.isEmpty) rawLines.removeLast();
  final sanitizedSourceLines = <String>[
    for (final line in rawLines) _sanitizeMarkdownText(_stripTrailingCr(line)),
  ];
  final blocks = <MarkdownBlock>[];
  final links = <MarkdownLink>[];
  var headingCount = 0;
  var listItemCount = 0;
  var codeBlockCount = 0;
  var codeLineCount = 0;
  var i = 0;

  void addBlock({
    required MarkdownBlockKind kind,
    required String rawSource,
    required String sourceText,
    required String plainText,
    required String displayText,
    int? headingLevel,
    int listDepth = 0,
    int? listNumber,
    int originalLength = 0,
    bool sanitized = false,
    bool collectLinks = true,
  }) {
    final blockIndex = blocks.length;
    final beforeLinks = links.length;
    if (collectLinks) {
      _collectMarkdownLinks(displayText, links: links, blockIndex: blockIndex);
    }
    final rawDisplay = _sanitizeMarkdownText(displayText, tabSize: tabSize);
    final display = _truncateGraphemes(rawDisplay, maxLineLength);
    blocks.add(
      MarkdownBlock(
        index: blockIndex,
        kind: kind,
        sourceText: sourceText,
        plainText: plainText,
        displayText: display,
        headingLevel: headingLevel,
        listDepth: listDepth,
        listNumber: listNumber,
        linkCount: links.length - beforeLinks,
        outputSanitized: sanitized || sourceText != rawSource,
        outputTruncated: display != rawDisplay,
        outputOriginalLength: originalLength,
      ),
    );
  }

  while (i < rawLines.length) {
    final raw = _stripTrailingCr(rawLines[i]);
    final sourceText = sanitizedSourceLines[i];
    final trimmedLeft = sourceText.trimLeft();
    if (sourceText.trim().isEmpty) {
      addBlock(
        kind: MarkdownBlockKind.blank,
        rawSource: raw,
        sourceText: sourceText,
        plainText: '',
        displayText: '',
        originalLength: raw.length,
        sanitized: sourceText != raw,
        collectLinks: false,
      );
      i++;
      continue;
    }
    if (trimmedLeft.startsWith('```')) {
      codeBlockCount += 1;
      i++;
      while (i < rawLines.length &&
          !_sanitizeMarkdownText(
            _stripTrailingCr(rawLines[i]),
            tabSize: tabSize,
          ).trimLeft().startsWith('```')) {
        final codeRaw = _stripTrailingCr(rawLines[i]);
        final codeSource = _sanitizeMarkdownText(codeRaw, tabSize: tabSize);
        codeLineCount += 1;
        addBlock(
          kind: MarkdownBlockKind.codeFence,
          rawSource: codeRaw,
          sourceText: codeSource,
          plainText: codeSource,
          displayText: codeSource,
          originalLength: codeRaw.length,
          sanitized: codeSource != codeRaw,
          collectLinks: false,
        );
        i++;
      }
      if (i < rawLines.length) i++;
      continue;
    }
    if (RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$').hasMatch(sourceText)) {
      addBlock(
        kind: MarkdownBlockKind.horizontalRule,
        rawSource: raw,
        sourceText: sourceText,
        plainText: 'horizontal rule',
        displayText: '─' * 40,
        originalLength: raw.length,
        sanitized: sourceText != raw,
        collectLinks: false,
      );
      i++;
      continue;
    }
    final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(sourceText);
    if (heading != null) {
      final level = heading.group(1)!.length;
      final body = heading.group(2)!;
      headingCount += 1;
      addBlock(
        kind: MarkdownBlockKind.heading,
        rawSource: raw,
        sourceText: sourceText,
        plainText: _plainInlineText(body),
        displayText: body,
        headingLevel: level,
        originalLength: raw.length,
        sanitized: sourceText != raw,
      );
      i++;
      continue;
    }
    if (trimmedLeft.startsWith('> ')) {
      final body = trimmedLeft.substring(2);
      addBlock(
        kind: MarkdownBlockKind.blockquote,
        rawSource: raw,
        sourceText: sourceText,
        plainText: _plainInlineText(body),
        displayText: '│ $body',
        originalLength: raw.length,
        sanitized: sourceText != raw,
      );
      i++;
      continue;
    }
    final bullet = RegExp(r'^(\s*)[-*]\s+(.*)$').firstMatch(sourceText);
    if (bullet != null) {
      final indent = bullet.group(1)!.length;
      final body = bullet.group(2)!;
      listItemCount += 1;
      addBlock(
        kind: MarkdownBlockKind.bullet,
        rawSource: raw,
        sourceText: sourceText,
        plainText: _plainInlineText(body),
        displayText: '${' ' * indent}• $body',
        listDepth: indent,
        originalLength: raw.length,
        sanitized: sourceText != raw,
      );
      i++;
      continue;
    }
    final ordered = RegExp(r'^(\s*)(\d+)\.\s+(.*)$').firstMatch(sourceText);
    if (ordered != null) {
      final indent = ordered.group(1)!.length;
      final number = int.parse(ordered.group(2)!);
      final body = ordered.group(3)!;
      listItemCount += 1;
      addBlock(
        kind: MarkdownBlockKind.ordered,
        rawSource: raw,
        sourceText: sourceText,
        plainText: _plainInlineText(body),
        displayText: '${' ' * indent}$number. $body',
        listDepth: indent,
        listNumber: number,
        originalLength: raw.length,
        sanitized: sourceText != raw,
      );
      i++;
      continue;
    }
    addBlock(
      kind: MarkdownBlockKind.paragraph,
      rawSource: raw,
      sourceText: sourceText,
      plainText: _plainInlineText(sourceText),
      displayText: sourceText,
      originalLength: raw.length,
      sanitized: sourceText != raw,
    );
    i++;
  }

  return MarkdownDocument(
    blocks: List<MarkdownBlock>.unmodifiable(blocks),
    links: List<MarkdownLink>.unmodifiable(links),
    source: sanitizedSourceLines.join('\n'),
    blockCount: blocks.length,
    headingCount: headingCount,
    listItemCount: listItemCount,
    linkCount: links.length,
    codeBlockCount: codeBlockCount,
    codeLineCount: codeLineCount,
  );
}

/// Exports the selected block or whole document as sanitized Markdown source.
String exportMarkdownSelection(
  MarkdownDocument document, {
  required int blockIndex,
  MarkdownViewCopyOptions options = const MarkdownViewCopyOptions(),
}) {
  if (document.blocks.isEmpty) return '';
  final selectedIndex = blockIndex.clamp(0, document.blocks.length - 1);
  return switch (options.mode) {
    MarkdownViewCopyMode.block => document.blocks[selectedIndex].sourceText,
    MarkdownViewCopyMode.document => document.source,
  };
}

/// A Markdown document viewer with a block cursor: content renders styled
/// (headings tinted, inline bold/italic/code, blockquotes, fences) while
/// arrow keys move a selection block by block. Ctrl+C copies the selected
/// block's Markdown source — or the whole document.
class MarkdownView extends StatefulWidget {
  MarkdownView({
    super.key,

    /// Markdown source parsed into [document] before rendering.
    required String markdown,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel = 'Markdown',
    this.baseStyle,
    this.maxLineLength = 1000,
    this.tabSize = 2,
    this.copySelection = true,
    this.copyOptions = const MarkdownViewCopyOptions(),
    this.onCopy,
  }) : document = parseMarkdownDocument(
         markdown,
         maxLineLength: maxLineLength,
         tabSize: tabSize,
       ),
       assert(maxLineLength == null || maxLineLength >= 0),
       assert(tabSize > 0);

  /// Creates a viewer from an already parsed [MarkdownDocument].
  ///
  /// The document's sanitized blocks, links, and parsing statistics are reused
  /// without parsing Markdown source again.
  const MarkdownView.document({
    super.key,
    required this.document,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel = 'Markdown',
    this.baseStyle,
    this.maxLineLength = 1000,
    this.tabSize = 2,
    this.copySelection = true,
    this.copyOptions = const MarkdownViewCopyOptions(),
    this.onCopy,
  }) : assert(maxLineLength == null || maxLineLength >= 0),
       assert(tabSize > 0);

  /// Parsed Markdown document to render.
  final MarkdownDocument document;

  /// External selection and visible-range controller.
  final MarkdownViewController? controller;

  /// Focus node used for keyboard navigation.
  final FocusNode? focusNode;

  /// Whether the viewer should request focus when mounted.
  final bool autofocus;

  /// Semantic label (the accessibility name; not rendered) for the Markdown viewer.
  final String semanticLabel;

  /// Base text style merged into rendered Markdown spans.
  final CellStyle? baseStyle;

  /// Maximum displayed line length.
  final int? maxLineLength;

  /// Number of spaces used when expanding tabs.
  final int tabSize;

  /// Whether Ctrl+C and semantic copy export the selected block/document.
  final bool copySelection;

  /// Clipboard/export options for copied Markdown text.
  final MarkdownViewCopyOptions copyOptions;

  /// Called after a copy attempt completes.
  final void Function(MarkdownViewCopyResult result)? onCopy;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  late MarkdownViewController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  bool _focusedWithin = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? MarkdownViewController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'MarkdownView');
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(covariant MarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? MarkdownViewController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'MarkdownView');
      _ownsFocusNode = widget.focusNode == null;
    }
  }

  void _onControllerChange() => setState(() {});

  void _onFocusWithinChange(bool focused) {
    if (_focusedWithin == focused) return;
    setState(() {
      _focusedWithin = focused;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  MarkdownBlock? _selectedBlock() {
    final blocks = widget.document.blocks;
    if (blocks.isEmpty) return null;
    final selected = (_controller.selectedIndex ?? 0).clamp(
      0,
      blocks.length - 1,
    );
    return blocks[selected];
  }

  Future<void> _copySelection() async {
    final blocks = widget.document.blocks;
    if (!widget.copySelection || blocks.isEmpty) return;
    final selectedIndex = (_controller.selectedIndex ?? 0).clamp(
      0,
      blocks.length - 1,
    );
    final text = exportMarkdownSelection(
      widget.document,
      blockIndex: selectedIndex,
      options: widget.copyOptions,
    );
    final report = await ClipboardScope.of(
      context,
    ).writeWithReport(text, policy: widget.copyOptions.clipboardPolicy);
    if (!mounted) return;
    widget.onCopy?.call(
      MarkdownViewCopyResult(
        blockIndex: selectedIndex,
        block: blocks[selectedIndex],
        text: text,
        report: report,
      ),
    );
  }

  Future<void> _copyBlockAt(int index) async {
    final blocks = widget.document.blocks;
    if (index < 0 || index >= blocks.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
    await _copySelection();
  }

  void _selectBlockAt(int index) {
    final blocks = widget.document.blocks;
    if (index < 0 || index >= blocks.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
  }

  Future<void> _handleMarkdownAction(SemanticAction action) async {
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.navigate:
        _focusNode.requestFocus();
        setState(() {});
        return;
      case SemanticAction.copy:
        await _copySelection();
        return;
      case _:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocks = widget.document.blocks;
    final selected = _selectedBlock();
    final visibleRange = _controller.visibleRange;
    final copyEnabled = widget.copySelection && blocks.isNotEmpty;
    Widget list = blocks.isEmpty
        ? const Text('  (empty markdown)', style: CellStyle(dim: true))
        : ListView.builder(
            controller: _controller._listController,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            itemCount: blocks.length,
            itemBuilder: (context, index, activeSelected) {
              final selected = index == _controller.selectedIndex;
              return _MarkdownBlockWidget(
                block: blocks[index],
                selected: selected,
                activeSelection: activeSelected,
                copyEnabled: copyEnabled,
                baseStyle: widget.baseStyle ?? CellStyle.empty,
                componentTheme: FleuryWidgetTheme.of(context),
                onActivate: () => _selectBlockAt(index),
                onCopy: () => _copyBlockAt(index),
              );
            },
          );

    if (copyEnabled) {
      list = KeyBindings(
        bindings: [
          KeyBinding(
            KeySequence.ctrl.c,
            label: 'Copy markdown selection',
            onTrigger: () => unawaited(_copySelection()),
          ),
        ],
        child: list,
      );
    }

    return FocusWithin(
      onFocusChange: _onFocusWithinChange,
      child: Semantics(
        role: SemanticRole.markdown,
        label: widget.semanticLabel,
        focused: _focusedWithin || _focusNode.hasFocus,
        actions: {
          SemanticAction.focus,
          SemanticAction.navigate,
          if (copyEnabled) SemanticAction.copy,
        },
        onAction: _handleMarkdownAction,
        state: SemanticState({
          'collectionRowCount': blocks.length,
          'blockCount': widget.document.blockCount,
          'headingCount': widget.document.headingCount,
          'listItemCount': widget.document.listItemCount,
          'linkCount': widget.document.linkCount,
          'codeBlockCount': widget.document.codeBlockCount,
          'codeLineCount': widget.document.codeLineCount,
          'copyEnabled': copyEnabled,
          'copyMode': widget.copyOptions.mode.name,
          'clipboardPolicy': widget.copyOptions.clipboardPolicy.name,
          if (visibleRange != null) ...{
            'visibleRangeStart': visibleRange.first,
            'visibleRangeEnd': visibleRange.last,
          },
          if (_controller.selectedIndex != null)
            'selectedIndex': _controller.selectedIndex,
          if (selected != null) ...{
            'selectedKey': selected.index,
            'selectedMarkdownBlockKind': selected.kind.name,
            if (selected.headingLevel != null)
              'selectedHeadingLevel': selected.headingLevel,
          },
        }),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: list),
            for (final link in widget.document.links)
              _linkSemantics(link, link.index),
          ],
        ),
      ),
    );
  }
}

class _MarkdownBlockWidget extends StatelessWidget {
  const _MarkdownBlockWidget({
    required this.block,
    required this.selected,
    required this.activeSelection,
    required this.copyEnabled,
    required this.baseStyle,
    required this.componentTheme,
    required this.onActivate,
    required this.onCopy,
  });

  final MarkdownBlock block;
  final bool selected;
  final bool activeSelection;
  final bool copyEnabled;
  final CellStyle baseStyle;
  final FleuryWidgetTheme componentTheme;
  final VoidCallback onActivate;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        _styleForMarkdownBlock(block, baseStyle, theme, componentTheme).merge(
          activeSelection
              ? theme.selectionStyle
              : selected
              ? theme.mutedStyle
              : CellStyle.empty,
        );
    final line =
        block.kind == MarkdownBlockKind.codeFence ||
            block.kind == MarkdownBlockKind.horizontalRule
        ? Text(block.displayText, style: style)
        : RichText(text: _inline(block.displayText, style));
    return Semantics(
      role: SemanticRole.markdownBlock,
      label: block.plainText,
      value: block.sourceText,
      selected: selected,
      actions: {
        SemanticAction.activate,
        if (selected && copyEnabled) SemanticAction.copy,
      },
      onAction: (action) async {
        switch (action) {
          case SemanticAction.activate:
            onActivate();
            return;
          case SemanticAction.copy:
            if (selected && copyEnabled) await onCopy();
            return;
          case _:
            return;
        }
      },
      state: SemanticState({
        'rowIndex': block.index,
        'rowKey': block.index,
        'markdownBlockKind': block.kind.name,
        if (block.headingLevel != null) 'headingLevel': block.headingLevel,
        'listDepth': block.listDepth,
        if (block.listNumber != null) 'listNumber': block.listNumber,
        'linkCount': block.linkCount,
        'outputSanitized': block.outputSanitized,
        'outputTruncated': block.outputTruncated,
        'outputOriginalLength': block.outputOriginalLength,
      }),
      child: line,
    );
  }
}

CellStyle _styleForMarkdownBlock(
  MarkdownBlock block,
  CellStyle base,
  ThemeData theme,
  FleuryWidgetTheme widgetTheme,
) {
  return switch (block.kind) {
    MarkdownBlockKind.heading => base.merge(
      widgetTheme.resolveMarkdownHeading(theme, block.headingLevel),
    ),
    MarkdownBlockKind.blockquote => base.merge(
      widgetTheme.resolveMarkdownBlockquote(theme),
    ),
    MarkdownBlockKind.codeFence => base.merge(
      widgetTheme.resolveMarkdownCodeBlock(theme),
    ),
    MarkdownBlockKind.horizontalRule => base.merge(
      widgetTheme.resolveMarkdownRule(theme),
    ),
    MarkdownBlockKind.blank ||
    MarkdownBlockKind.paragraph ||
    MarkdownBlockKind.bullet ||
    MarkdownBlockKind.ordered => base,
  };
}

/// The OSC 8 outcome for [link] under the surface's [hyperlinks] capability,
/// mirroring the producer gate in [_inline]: `supported` when the surface
/// supports hyperlinks AND the scheme is allow-listed (the run carries a real
/// linkUri), `disabledByPolicy` when an un-allow-listed scheme blocks it,
/// `unsupported` when the surface has no link concept. Every value is a real
/// enum name so the field can't drift from the vocabulary it reports:
/// `supported`/`unsupported` are `HyperlinkSupport` states (the same
/// `fleury diagnose` labels for OSC 8), and `disabledByPolicy` is a
/// `CapabilityResolutionState`.
String _osc8PolicyFor(MarkdownLink link, {required bool hyperlinks}) {
  if (!hyperlinks) return 'unsupported';
  if (!link.safeScheme) return 'disabledByPolicy';
  return 'supported';
}

/// Builds the (invisible) semantics node for a markdown [link]. The URL stays
/// agent/AT-legible via [Semantics.value] regardless of whether a live link was
/// emitted. [osc8Policy] records what actually happened at the producer (see
/// [_osc8PolicyFor]); it defaults to `disabledByDefault` for callers that render
/// links as visible text only (e.g. [MarkdownView]).
Widget _linkSemantics(
  MarkdownLink link,
  int index, {
  String osc8Policy = 'disabledByDefault',
}) {
  // The generic capability-resolution contract (terminalCapability /
  // capabilityRequirement / activeFallback): MarkdownText always keeps a
  // visible-URL fallback available, so this documents the prohibited-by-default
  // OSC 8 stance and the fallback label. The live per-surface outcome rides on
  // `osc8Policy` below, which the producer derived from the actual capability.
  final resolution = resolveCapabilityRequirement(
    const CapabilityRequirement(
      feature: TerminalFeature.osc8Hyperlinks,
      level: CapabilityLevel.prohibited,
      reason: 'Markdown links render as visible text by default.',
      fallback: CapabilityFallback(label: 'visible URL'),
    ),
    TerminalCapabilities.defaultCapabilities,
    policyBlockedFeatures: const <TerminalFeature>{
      TerminalFeature.osc8Hyperlinks,
    },
  );
  final state = resolution.toSemanticState().merge(<String, Object?>{
    'markdownLinkIndex': index,
    'markdownBlockIndex': link.blockIndex,
    'linkUrl': link.url,
    'linkScheme': link.scheme,
    'safeLinkScheme': link.safeScheme,
    'osc8Policy': osc8Policy,
  });
  return Semantics(
    role: SemanticRole.link,
    label: link.text,
    value: link.url,
    state: state,
    child: const EmptyBox(),
  );
}

/// The link's scheme name (lowercased substring before the first `:`), or null
/// for a scheme-less URL. Reported as the `linkScheme` diagnostic; the
/// safe/unsafe verdict itself is the shared [isSafeLinkScheme] (RFC 0017 §6).
String? _urlScheme(String url) {
  final index = url.indexOf(':');
  if (index <= 0) return null;
  return url.substring(0, index).toLowerCase();
}

// ---- Block-level pass -----------------------------------------------------

({List<Widget> lines, List<MarkdownLink> links}) _renderBlocks(
  String data,
  CellStyle base, {
  Color? Function(int level)? headingColor,
  bool hyperlinks = false,
  bool inlineLinkUrls = true,
}) {
  final out = <Widget>[];
  final links = <MarkdownLink>[];
  final lines = data.split('\n');
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      out.add(const Text(''));
      i++;
      continue;
    }
    // Fenced code block — consume until matching ```.
    if (line.trimLeft().startsWith('```')) {
      i++;
      final codeLines = <String>[];
      while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
        codeLines.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++; // skip closing fence
      for (final c in codeLines) {
        out.add(
          Text(
            c,
            style: base.merge(
              const CellStyle(background: RgbColor(40, 40, 50)),
            ),
          ),
        );
      }
      continue;
    }
    // Horizontal rule.
    if (RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$').hasMatch(line)) {
      out.add(Text('─' * 40, style: base.merge(const CellStyle(dim: true))));
      i++;
      continue;
    }
    // Heading.
    final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.length;
      final body = heading.group(2)!;
      final hStyle = base.merge(
        CellStyle(
          bold: true,
          // H1 inverts for emphasis; H2/H3 just bold + underline. A color
          // tint (when provided) reinforces the depth hierarchy.
          underline: level > 1,
          inverse: level == 1,
          foreground: headingColor?.call(level),
        ),
      );
      out.add(
        RichText(
          text: _inline(
            body,
            hStyle,
            links: links,
            hyperlinks: hyperlinks,
            inlineLinkUrls: inlineLinkUrls,
          ),
        ),
      );
      i++;
      continue;
    }
    // Blockquote.
    if (line.trimLeft().startsWith('> ')) {
      final body = line.trimLeft().substring(2);
      final qStyle = base.merge(const CellStyle(dim: true));
      out.add(
        RichText(
          text: TextSpan(
            style: qStyle,
            children: [
              const TextSpan(text: '│ '),
              _inline(
                body,
                qStyle,
                links: links,
                hyperlinks: hyperlinks,
                inlineLinkUrls: inlineLinkUrls,
              ),
            ],
          ),
        ),
      );
      i++;
      continue;
    }
    // Bullet list.
    final bullet = RegExp(r'^(\s*)[-*]\s+(.*)$').firstMatch(line);
    if (bullet != null) {
      final indent = ' ' * bullet.group(1)!.length;
      final body = bullet.group(2)!;
      out.add(
        RichText(
          text: TextSpan(
            style: base,
            children: [
              TextSpan(text: '$indent• '),
              _inline(
                body,
                base,
                links: links,
                hyperlinks: hyperlinks,
                inlineLinkUrls: inlineLinkUrls,
              ),
            ],
          ),
        ),
      );
      i++;
      continue;
    }
    // Ordered list.
    final ordered = RegExp(r'^(\s*)(\d+)\.\s+(.*)$').firstMatch(line);
    if (ordered != null) {
      final indent = ' ' * ordered.group(1)!.length;
      final num = ordered.group(2)!;
      final body = ordered.group(3)!;
      out.add(
        RichText(
          text: TextSpan(
            style: base,
            children: [
              TextSpan(text: '$indent$num. '),
              _inline(
                body,
                base,
                links: links,
                hyperlinks: hyperlinks,
                inlineLinkUrls: inlineLinkUrls,
              ),
            ],
          ),
        ),
      );
      i++;
      continue;
    }
    // Plain paragraph line.
    out.add(
      RichText(
        text: _inline(
          line,
          base,
          links: links,
          hyperlinks: hyperlinks,
          inlineLinkUrls: inlineLinkUrls,
        ),
      ),
    );
    i++;
  }
  return (lines: out, links: links);
}

// ---- Inline pass ----------------------------------------------------------

/// Walks [src] left-to-right, splitting at markup tokens, and emits a
/// [TextSpan] tree under [base]. Greedy: longest tokens win at each
/// position. Unbalanced markup is left as literal text (no escape
/// sequences corrupt the render).
TextSpan _inline(
  String src,
  CellStyle base, {
  List<MarkdownLink>? links,
  int blockIndex = -1,
  bool hyperlinks = false,
  bool inlineLinkUrls = true,
}) {
  final children = <TextSpan>[];
  var i = 0;
  final buf = StringBuffer();

  void flushText() {
    if (buf.isEmpty) return;
    children.add(TextSpan(text: buf.toString()));
    buf.clear();
  }

  while (i < src.length) {
    final ch = src[i];

    // Inline code: `…`
    if (ch == '`') {
      final end = src.indexOf('`', i + 1);
      if (end > i) {
        flushText();
        children.add(
          TextSpan(
            text: src.substring(i + 1, end),
            style: base.merge(
              const CellStyle(background: RgbColor(45, 45, 55)),
            ),
          ),
        );
        i = end + 1;
        continue;
      }
    }
    // Bold: **…**
    if (ch == '*' && i + 1 < src.length && src[i + 1] == '*') {
      final end = src.indexOf('**', i + 2);
      if (end > i) {
        flushText();
        children.add(
          TextSpan(
            text: src.substring(i + 2, end),
            style: base.merge(const CellStyle(bold: true)),
          ),
        );
        i = end + 2;
        continue;
      }
    }
    // Strikethrough: ~~…~~
    if (ch == '~' && i + 1 < src.length && src[i + 1] == '~') {
      final end = src.indexOf('~~', i + 2);
      if (end > i) {
        flushText();
        children.add(
          TextSpan(
            text: src.substring(i + 2, end),
            style: base.merge(const CellStyle(strikethrough: true)),
          ),
        );
        i = end + 2;
        continue;
      }
    }
    // Italic: *…* OR _…_ (single delimiter; greedy until matching one).
    if (ch == '*' || ch == '_') {
      // Avoid double-* here (handled above).
      final end = src.indexOf(ch, i + 1);
      if (end > i) {
        flushText();
        children.add(
          TextSpan(
            text: src.substring(i + 1, end),
            style: base.merge(const CellStyle(italic: true)),
          ),
        );
        i = end + 1;
        continue;
      }
    }
    // Link: [text](url) — underline the label; attach a real OSC 8 / anchor
    // target (linkUri) only when the surface supports links AND the scheme is
    // allow-listed, else fall back to plain underline + the visible url.
    if (ch == '[') {
      final closeBracket = src.indexOf(']', i + 1);
      if (closeBracket > i &&
          closeBracket + 1 < src.length &&
          src[closeBracket + 1] == '(') {
        final closeParen = src.indexOf(')', closeBracket + 2);
        if (closeParen > closeBracket) {
          flushText();
          final text = _sanitizeMarkdownText(
            src.substring(i + 1, closeBracket),
          );
          final url = _sanitizeMarkdownText(
            src.substring(closeBracket + 2, closeParen),
          );
          links?.add(
            MarkdownLink(
              index: links.length,
              blockIndex: blockIndex,
              text: text,
              url: url,
            ),
          );
          // A safe-scheme link renders in the link accent colour + underline
          // (readable on dark, unlike a browser's default blue), whether or not
          // it's clickable here; the producer gate (capability + safe scheme)
          // additionally attaches `linkUri` to make it live. An unsafe scheme is
          // refused — plain underlined text, never the link colour.
          final safe = isSafeLinkScheme(url);
          final live = hyperlinks && safe;
          children.add(
            TextSpan(
              text: text,
              style: safe
                  ? base.merge(
                      CellStyle(
                        foreground: _kMarkdownLinkColor,
                        underline: true,
                        linkUri: live ? url : null,
                      ),
                    )
                  : base.merge(const CellStyle(underline: true)),
            ),
          );
          // Keep the inspectable ` (url)` suffix (RFC 0017 §8) unless the
          // caller opted out AND the link is live — a clickable link makes the
          // url redundant, but a dead fallback must never hide its destination.
          if (inlineLinkUrls || !live) {
            children.add(
              TextSpan(
                text: ' ($url)',
                style: base.merge(const CellStyle(dim: true)),
              ),
            );
          }
          i = closeParen + 1;
          continue;
        }
      }
    }
    buf.write(ch);
    i++;
  }
  flushText();
  if (children.length == 1) {
    // Collapse a single child into one styled leaf. Preserve the child's own
    // style when it has one (a lone `code`, **bold**, or a suffix-less live
    // link) — its style already has `base` merged in, and dropping it would
    // silently lose the styling, including a link's linkUri. A plain-text child
    // (from flushText) has no style and falls back to base.
    final only = children.first;
    return TextSpan(text: only.text, style: only.style ?? base);
  }
  return TextSpan(style: base, children: children);
}

void _collectMarkdownLinks(
  String src, {
  required List<MarkdownLink> links,
  required int blockIndex,
}) {
  _inline(src, CellStyle.empty, links: links, blockIndex: blockIndex);
}

String _plainInlineText(String src) {
  var text = src;
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
    (match) =>
        '${match.group(1)!} (${_sanitizeMarkdownText(match.group(2)!)}'
        ')',
  );
  // Strip the emphasis/code delimiters, keeping the inner text. replaceAllMapped
  // (not replaceAll) is required: Dart uses a replaceAll replacement string
  // literally, so r'$1' would emit the two characters "$1" instead of group 1 —
  // matching the link rule above, which already maps the group by hand.
  text = text
      .replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1)!)
      .replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1)!)
      .replaceAllMapped(RegExp(r'~~([^~]+)~~'), (m) => m.group(1)!)
      .replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => m.group(1)!)
      .replaceAllMapped(RegExp(r'_([^_]+)_'), (m) => m.group(1)!);
  return _sanitizeMarkdownText(text);
}

String _sanitizeMarkdownText(String text, {int tabSize = 2}) {
  final expandedTabs = text.replaceAll('\t', ' ' * tabSize);
  // Visible \r/\n BEFORE sanitizing — sanitizeForDisplay rewrites them to
  // U+FFFD, so doing it after would leave these replaceAlls as dead no-ops.
  return sanitizeForDisplay(
    expandedTabs.replaceAll('\r', r'\r').replaceAll('\n', r'\n'),
  );
}

String _stripTrailingCr(String text) {
  return text.endsWith('\r') ? text.substring(0, text.length - 1) : text;
}

String _truncateGraphemes(String text, int? maxLength) {
  if (maxLength == null) return text;
  if (maxLength <= 0) return '';
  final chars = text.characters;
  if (chars.length <= maxLength) return text;
  if (maxLength == 1) return '…';
  return '${chars.take(maxLength - 1)}…';
}
