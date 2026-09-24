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
class MarkdownText extends StatefulWidget {
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
  State<MarkdownText> createState() => _MarkdownTextState();
}

class _MarkdownTextState extends State<MarkdownText> {
  _MarkdownRenderer? _renderer;
  String _data = '';
  int _completeLines = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // PRODUCER-SIDE GATE (RFC 0017 §2): only emit a real OSC 8 / anchor link
    // when the presenting surface reports it can render one. A non-supporting
    // terminal reports false, so `linkUri` stays null — the renderer emits
    // nothing and there is no wasted re-emit; the browser surface reports true,
    // so served/embedded peers get anchors. Scheme allow-listing (`_inline`,
    // §6) is the second half of the gate.
    final hyperlinks = MediaQuery.capabilitiesOf(context).hyperlinks;
    final data = widget.data;
    final base = widget.baseStyle ?? CellStyle.none;
    var renderer = _renderer;
    if (renderer == null ||
        !renderer.matches(
          base: base,
          // Mirrors FleuryWidgetTheme.resolveMarkdownHeading: primary for
          // H1, info for H2, no tint deeper — emphasis recedes with depth.
          h1: cs.primary,
          h2: cs.info,
          hyperlinks: hyperlinks,
          inlineLinkUrls: widget.inlineLinkUrls,
        )) {
      renderer = _renderer = _MarkdownRenderer(
        base: base,
        h1: cs.primary,
        h2: cs.info,
        hyperlinks: hyperlinks,
        inlineLinkUrls: widget.inlineLinkUrls,
      )..addLines(data.split('\n'));
      _data = data;
      _completeLines = _newlineCount(data);
    } else if (!identical(data, _data) && data != _data) {
      // An append re-renders from the last line it could have changed; any
      // other edit re-renders everything.
      final resume = _appendResumePoint(_data, _completeLines, data);
      final from = resume?.lines ?? 0;
      final tail = resume == null ? data : data.substring(resume.chars);
      renderer
        ..rewindTo(from)
        ..addLines(tail.split('\n'));
      _data = data;
      _completeLines = from + _newlineCount(tail);
    }
    final children = renderer.children;
    if (children.isEmpty) return const EmptyBox();
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

/// Controller for [MarkdownView] browsing.
class MarkdownViewController extends Notifier {
  MarkdownViewController({
    /// Zero-based block selected when the controller is created.
    /// Initial browsing row. Null starts without a current row.
    int? initialIndex = 0,
  }) : _list = ListController(initialIndex: initialIndex) {
    _list.addListener(notify);
  }

  final ListController _list;
  bool _disposed = false;

  ListController get _listController => _list;

  int? get currentIndex => _list.currentIndex;
  set currentIndex(int? value) {
    _checkNotDisposed();
    _list.currentIndex = value;
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
    _list.removeListener(notify);
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
  final parser = _MarkdownParser(maxLineLength: maxLineLength, tabSize: tabSize)
    ..addLines(_markdownLines(source));
  return parser.document();
}

/// [source] split into lines, without the empty line a trailing newline
/// leaves.
List<String> _markdownLines(String source) {
  final lines = source.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

final RegExp _horizontalRulePattern = RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$');
final RegExp _headingPattern = RegExp(r'^(#{1,3})\s+(.*)$');
final RegExp _bulletPattern = RegExp(r'^(\s*)[-*]\s+(.*)$');
final RegExp _orderedPattern = RegExp(r'^(\s*)(\d+)\.\s+(.*)$');

/// A line-at-a-time parse that can rewind to any line and continue.
///
/// A row depends only on its own line and on whether a fenced code block is
/// open, so the state recorded before each line is enough to re-parse from
/// there — which is how an append re-parses only the lines it touched.
final class _MarkdownParser {
  _MarkdownParser({required this.maxLineLength, required this.tabSize});

  final int? maxLineLength;
  final int tabSize;

  final List<MarkdownBlock> _blocks = [];
  final List<MarkdownLink> _links = [];
  final List<String> _sourceLines = [];
  int _headingCount = 0;
  int _listItemCount = 0;
  int _codeBlockCount = 0;
  int _codeLineCount = 0;
  bool _inFence = false;

  // The state before each parsed line: [_stateWidth] ints per line, and
  // whether a fence was open.
  static const int _stateWidth = 6;
  final List<int> _lineStates = [];
  final List<bool> _lineFences = [];

  int get lineCount => _sourceLines.length;

  void addLines(Iterable<String> lines) {
    for (final line in lines) {
      _lineStates
        ..add(_blocks.length)
        ..add(_links.length)
        ..add(_headingCount)
        ..add(_listItemCount)
        ..add(_codeBlockCount)
        ..add(_codeLineCount);
      _lineFences.add(_inFence);
      _parseLine(line);
    }
  }

  /// Drops every line from [line] on, restoring the state before it.
  void rewindTo(int line) {
    if (line >= lineCount) return;
    final base = line * _stateWidth;
    _blocks.length = _lineStates[base];
    _links.length = _lineStates[base + 1];
    _headingCount = _lineStates[base + 2];
    _listItemCount = _lineStates[base + 3];
    _codeBlockCount = _lineStates[base + 4];
    _codeLineCount = _lineStates[base + 5];
    _inFence = _lineFences[line];
    _sourceLines.length = line;
    _lineStates.length = base;
    _lineFences.length = line;
  }

  MarkdownDocument document() => MarkdownDocument(
    blocks: List<MarkdownBlock>.unmodifiable(_blocks),
    links: List<MarkdownLink>.unmodifiable(_links),
    source: _sourceLines.join('\n'),
    blockCount: _blocks.length,
    headingCount: _headingCount,
    listItemCount: _listItemCount,
    linkCount: _links.length,
    codeBlockCount: _codeBlockCount,
    codeLineCount: _codeLineCount,
  );

  void _addBlock({
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
    final blockIndex = _blocks.length;
    final beforeLinks = _links.length;
    if (collectLinks) {
      _collectMarkdownLinks(displayText, links: _links, blockIndex: blockIndex);
    }
    final rawDisplay = _sanitizeMarkdownText(displayText, tabSize: tabSize);
    final display = _truncateGraphemes(rawDisplay, maxLineLength);
    _blocks.add(
      MarkdownBlock(
        index: blockIndex,
        kind: kind,
        sourceText: sourceText,
        plainText: plainText,
        displayText: display,
        headingLevel: headingLevel,
        listDepth: listDepth,
        listNumber: listNumber,
        linkCount: _links.length - beforeLinks,
        outputSanitized: sanitized || sourceText != rawSource,
        outputTruncated: display != rawDisplay,
        outputOriginalLength: originalLength,
      ),
    );
  }

  void _parseLine(String line) {
    final raw = _stripTrailingCr(line);
    final sourceText = _sanitizeMarkdownText(raw);
    _sourceLines.add(sourceText);
    if (_inFence) {
      final codeSource = _sanitizeMarkdownText(raw, tabSize: tabSize);
      if (codeSource.trimLeft().startsWith('```')) {
        _inFence = false;
        return;
      }
      _codeLineCount += 1;
      _addBlock(
        kind: MarkdownBlockKind.codeFence,
        rawSource: raw,
        sourceText: codeSource,
        plainText: codeSource,
        displayText: codeSource,
        originalLength: raw.length,
        sanitized: codeSource != raw,
        collectLinks: false,
      );
      return;
    }
    final trimmedLeft = sourceText.trimLeft();
    if (sourceText.trim().isEmpty) {
      _addBlock(
        kind: MarkdownBlockKind.blank,
        rawSource: raw,
        sourceText: sourceText,
        plainText: '',
        displayText: '',
        originalLength: raw.length,
        sanitized: sourceText != raw,
        collectLinks: false,
      );
      return;
    }
    if (trimmedLeft.startsWith('```')) {
      _codeBlockCount += 1;
      _inFence = true;
      return;
    }
    if (_horizontalRulePattern.hasMatch(sourceText)) {
      _addBlock(
        kind: MarkdownBlockKind.horizontalRule,
        rawSource: raw,
        sourceText: sourceText,
        plainText: 'horizontal rule',
        displayText: '─' * 40,
        originalLength: raw.length,
        sanitized: sourceText != raw,
        collectLinks: false,
      );
      return;
    }
    final heading = _headingPattern.firstMatch(sourceText);
    if (heading != null) {
      final level = heading.group(1)!.length;
      final body = heading.group(2)!;
      _headingCount += 1;
      _addBlock(
        kind: MarkdownBlockKind.heading,
        rawSource: raw,
        sourceText: sourceText,
        plainText: _plainInlineText(body),
        displayText: body,
        headingLevel: level,
        originalLength: raw.length,
        sanitized: sourceText != raw,
      );
      return;
    }
    if (trimmedLeft.startsWith('> ')) {
      final body = trimmedLeft.substring(2);
      _addBlock(
        kind: MarkdownBlockKind.blockquote,
        rawSource: raw,
        sourceText: sourceText,
        plainText: _plainInlineText(body),
        displayText: '│ $body',
        originalLength: raw.length,
        sanitized: sourceText != raw,
      );
      return;
    }
    final bullet = _bulletPattern.firstMatch(sourceText);
    if (bullet != null) {
      final indent = bullet.group(1)!.length;
      final body = bullet.group(2)!;
      _listItemCount += 1;
      _addBlock(
        kind: MarkdownBlockKind.bullet,
        rawSource: raw,
        sourceText: sourceText,
        plainText: _plainInlineText(body),
        displayText: '${' ' * indent}• $body',
        listDepth: indent,
        originalLength: raw.length,
        sanitized: sourceText != raw,
      );
      return;
    }
    final ordered = _orderedPattern.firstMatch(sourceText);
    if (ordered != null) {
      final indent = ordered.group(1)!.length;
      final number = int.parse(ordered.group(2)!);
      final body = ordered.group(3)!;
      _listItemCount += 1;
      _addBlock(
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
      return;
    }
    _addBlock(
      kind: MarkdownBlockKind.paragraph,
      rawSource: raw,
      sourceText: sourceText,
      plainText: _plainInlineText(sourceText),
      displayText: sourceText,
      originalLength: raw.length,
      sanitized: sourceText != raw,
    );
  }
}

/// Where a parse of [previous] can resume for [next]: the characters and the
/// count of the complete (newline-terminated) lines [previous] starts with,
/// which an append cannot have changed. Null unless [next] extends
/// [previous].
({int chars, int lines})? _appendResumePoint(
  String previous,
  int previousCompleteLines,
  String next,
) {
  if (next.length <= previous.length || !next.startsWith(previous)) {
    return null;
  }
  return (chars: previous.lastIndexOf('\n') + 1, lines: previousCompleteLines);
}

int _newlineCount(String text) {
  var count = 0;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) count++;
  }
  return count;
}

/// Keeps the last parse of a growing source so an append re-parses only its
/// tail, and an unchanged source re-parses nothing.
final class _MarkdownDocumentCache {
  _MarkdownParser? _parser;
  String _source = '';
  int _completeLines = 0;
  MarkdownDocument? _document;
  List<Widget> _linkWidgets = const [];

  MarkdownDocument documentFor(
    String source, {
    required int? maxLineLength,
    required int tabSize,
  }) {
    var parser = _parser;
    final document = _document;
    final sameOptions =
        parser != null &&
        parser.maxLineLength == maxLineLength &&
        parser.tabSize == tabSize;
    if (sameOptions && document != null) {
      if (identical(source, _source) || source == _source) return document;
      final resume = _appendResumePoint(_source, _completeLines, source);
      if (resume != null) {
        final tail = source.substring(resume.chars);
        parser
          ..rewindTo(resume.lines)
          ..addLines(_markdownLines(tail));
        return _store(source, parser, resume.lines + _newlineCount(tail));
      }
    }
    parser = _MarkdownParser(maxLineLength: maxLineLength, tabSize: tabSize)
      ..addLines(_markdownLines(source));
    return _store(source, parser, _newlineCount(source));
  }

  MarkdownDocument _store(
    String source,
    _MarkdownParser parser,
    int completeLines,
  ) {
    _parser = parser;
    _source = source;
    _completeLines = completeLines;
    return _document = parser.document();
  }

  /// Link semantics for [document]'s links, rebuilding only the links that
  /// changed since the last call.
  List<Widget> linkWidgets(MarkdownDocument document) {
    final links = document.links;
    final previous = _linkWidgets;
    var reuse = 0;
    while (reuse < previous.length &&
        reuse < links.length &&
        identical((previous[reuse] as _LinkSemantics).link, links[reuse])) {
      reuse++;
    }
    if (reuse == previous.length && reuse == links.length) return previous;
    return _linkWidgets = List<Widget>.unmodifiable([
      ...previous.take(reuse),
      for (var i = reuse; i < links.length; i++)
        _LinkSemantics(links[i], links[i].index),
    ]);
  }
}

/// Exports the selected block or whole document as sanitized Markdown source.
String exportMarkdownSelection(
  MarkdownDocument document, {
  required int blockIndex,
  MarkdownViewCopyOptions options = const MarkdownViewCopyOptions(),
}) {
  if (document.blocks.isEmpty) return '';
  final currentIndex = blockIndex.clamp(0, document.blocks.length - 1);
  return switch (options.mode) {
    MarkdownViewCopyMode.block => document.blocks[currentIndex].sourceText,
    MarkdownViewCopyMode.document => document.source,
  };
}

/// A Markdown document viewer with a block cursor: content renders styled
/// (headings tinted, inline bold/italic/code, blockquotes, fences) while
/// arrow keys move a selection block by block. Ctrl+C copies the selected
/// block's Markdown source — or the whole document.
class MarkdownView extends StatefulWidget {
  const MarkdownView({
    super.key,
    required String this.markdown,
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
  }) : document = null,
       assert(maxLineLength == null || maxLineLength >= 0),
       assert(tabSize > 0);

  /// Creates a viewer from an already parsed [MarkdownDocument].
  ///
  /// The document's sanitized blocks, links, and parsing statistics are reused
  /// without parsing Markdown source again.
  const MarkdownView.document({
    super.key,
    required MarkdownDocument this.document,
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
  }) : markdown = null,
       assert(maxLineLength == null || maxLineLength >= 0),
       assert(tabSize > 0);

  /// Markdown source to render, parsed by the view. The parse is kept while
  /// the source is unchanged, and an appended source re-parses only its last
  /// line onward, so streaming into a long document stays cheap. Null for
  /// [MarkdownView.document].
  final String? markdown;

  /// An already parsed document to render; null for [MarkdownView.new].
  final MarkdownDocument? document;

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
  final _MarkdownDocumentCache _cache = _MarkdownDocumentCache();
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

  MarkdownDocument get _document =>
      widget.document ??
      _cache.documentFor(
        widget.markdown!,
        maxLineLength: widget.maxLineLength,
        tabSize: widget.tabSize,
      );

  void _onFocusDetectorChange(bool focused) {
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
    final blocks = _document.blocks;
    if (blocks.isEmpty) return null;
    final selected = (_controller.currentIndex ?? 0).clamp(
      0,
      blocks.length - 1,
    );
    return blocks[selected];
  }

  Future<void> _copySelection() async {
    final blocks = _document.blocks;
    if (!widget.copySelection || blocks.isEmpty) return;
    final currentIndex = (_controller.currentIndex ?? 0).clamp(
      0,
      blocks.length - 1,
    );
    final text = exportMarkdownSelection(
      _document,
      blockIndex: currentIndex,
      options: widget.copyOptions,
    );
    final report = await ClipboardScope.of(
      context,
    ).writeWithReport(text, policy: widget.copyOptions.clipboardPolicy);
    if (!mounted) return;
    widget.onCopy?.call(
      MarkdownViewCopyResult(
        blockIndex: currentIndex,
        block: blocks[currentIndex],
        text: text,
        report: report,
      ),
    );
  }

  Future<void> _copyBlockAt(int index) async {
    final blocks = _document.blocks;
    if (index < 0 || index >= blocks.length) return;
    _focusNode.requestFocus();
    _controller.currentIndex = index;
    await _copySelection();
  }

  void _selectBlockAt(int index) {
    final blocks = _document.blocks;
    if (index < 0 || index >= blocks.length) return;
    _focusNode.requestFocus();
    _controller.currentIndex = index;
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
    final document = _document;
    final blocks = document.blocks;
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
              final selected = index == _controller.currentIndex;
              return _MarkdownBlockWidget(
                block: blocks[index],
                selected: selected,
                activeSelection: activeSelected,
                copyEnabled: copyEnabled,
                baseStyle: widget.baseStyle ?? CellStyle.none,
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
            onTrigger: (_) => unawaited(_copySelection()),
          ),
        ],
        child: list,
      );
    }

    return FocusDetector(
      onFocusChange: _onFocusDetectorChange,
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
          'blockCount': document.blockCount,
          'headingCount': document.headingCount,
          'listItemCount': document.listItemCount,
          'linkCount': document.linkCount,
          'codeBlockCount': document.codeBlockCount,
          'codeLineCount': document.codeLineCount,
          'copyEnabled': copyEnabled,
          'copyMode': widget.copyOptions.mode.name,
          'clipboardPolicy': widget.copyOptions.clipboardPolicy.name,
          if (visibleRange != null) ...{
            'visibleRangeStart': visibleRange.first,
            'visibleRangeEnd': visibleRange.last,
          },
          if (_controller.currentIndex != null)
            'currentIndex': _controller.currentIndex,
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
            ..._cache.linkWidgets(document),
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
              : CellStyle.none,
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

// The capability contract every Markdown link node reports (terminalCapability
// / capabilityRequirement / activeFallback): MarkdownText always keeps a
// visible-URL fallback available, so this documents the prohibited-by-default
// OSC 8 stance and the fallback label. Constant, so resolved once; the live
// per-surface outcome rides on each node's `osc8Policy`, which the producer
// derived from the actual capability.
final SemanticState _linkCapabilityState = resolveCapabilityRequirement(
  const CapabilityRequirement(
    feature: TerminalFeature.osc8Hyperlinks,
    level: CapabilityLevel.prohibited,
    reason: 'Markdown links render as visible text by default.',
    fallback: CapabilityFallback(label: 'visible URL'),
  ),
  const CapabilityTruth(
    feature: TerminalFeature.osc8Hyperlinks,
    support: CapabilitySupport.unknown,
    enablement: CapabilityEnablement.disabled,
    delivery: CapabilityDelivery.notApplicable,
    policyBlocked: true,
    evidence: <CapabilityEvidence>[
      CapabilityEvidence(
        source: CapabilityEvidenceSource.policy,
        detail: 'Markdown links use visible URLs by default.',
      ),
    ],
  ),
).toSemanticState();

/// The (invisible) semantics node for a markdown [link]. The URL stays
/// agent/AT-legible via [Semantics.value] regardless of whether a live link was
/// emitted. [osc8Policy] records what actually happened at the producer (see
/// [_osc8PolicyFor]); it defaults to `disabledByDefault` for callers that render
/// links as visible text only (e.g. [MarkdownView]).
class _LinkSemantics extends StatelessWidget {
  const _LinkSemantics(
    this.link,
    this.index, {
    this.osc8Policy = 'disabledByDefault',
  });

  final MarkdownLink link;
  final int index;
  final String osc8Policy;

  @override
  Widget build(BuildContext context) => Semantics(
    role: SemanticRole.link,
    label: link.text,
    value: link.url,
    state: _linkCapabilityState.merge(<String, Object?>{
      'markdownLinkIndex': index,
      'markdownBlockIndex': link.blockIndex,
      'linkUrl': link.url,
      'linkScheme': link.scheme,
      'safeLinkScheme': link.safeScheme,
      'osc8Policy': osc8Policy,
    }),
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

/// The rows [MarkdownText] renders for its source, built a line at a time
/// and resumable like [_MarkdownParser], so an append re-renders only the
/// lines it touched and unchanged rows keep their widget instances.
final class _MarkdownRenderer {
  _MarkdownRenderer({
    required this.base,
    required this.h1,
    required this.h2,
    required this.hyperlinks,
    required this.inlineLinkUrls,
  });

  final CellStyle base;
  final Color? h1;
  final Color? h2;
  final bool hyperlinks;
  final bool inlineLinkUrls;

  final List<Widget> _rows = [];
  final List<MarkdownLink> _links = [];
  final List<Widget> _linkRows = [];
  bool _inFence = false;

  // The state before each rendered line.
  final List<int> _lineRows = [];
  final List<int> _lineLinks = [];
  final List<bool> _lineFences = [];

  List<Widget>? _children;

  bool matches({
    required CellStyle base,
    required Color? h1,
    required Color? h2,
    required bool hyperlinks,
    required bool inlineLinkUrls,
  }) =>
      base == this.base &&
      h1 == this.h1 &&
      h2 == this.h2 &&
      hyperlinks == this.hyperlinks &&
      inlineLinkUrls == this.inlineLinkUrls;

  /// The line rows followed by one semantics node per link.
  List<Widget> get children =>
      _children ??= List<Widget>.unmodifiable([..._rows, ..._linkRows]);

  void addLines(Iterable<String> lines) {
    _children = null;
    for (final line in lines) {
      _lineRows.add(_rows.length);
      _lineLinks.add(_links.length);
      _lineFences.add(_inFence);
      final before = _links.length;
      _renderLine(line);
      for (var i = before; i < _links.length; i++) {
        _linkRows.add(
          _LinkSemantics(
            _links[i],
            i,
            osc8Policy: _osc8PolicyFor(_links[i], hyperlinks: hyperlinks),
          ),
        );
      }
    }
  }

  /// Drops every line from [line] on, restoring the state before it.
  void rewindTo(int line) {
    if (line >= _lineRows.length) return;
    _children = null;
    _rows.length = _lineRows[line];
    _links.length = _lineLinks[line];
    _linkRows.length = _lineLinks[line];
    _inFence = _lineFences[line];
    _lineRows.length = line;
    _lineLinks.length = line;
    _lineFences.length = line;
  }

  TextSpan _inlineSpan(String text, CellStyle style) => _inline(
    text,
    style,
    links: _links,
    hyperlinks: hyperlinks,
    inlineLinkUrls: inlineLinkUrls,
  );

  void _renderLine(String line) {
    if (_inFence) {
      if (line.trimLeft().startsWith('```')) {
        _inFence = false;
        return;
      }
      _rows.add(
        Text(
          line,
          style: base.merge(const CellStyle(background: RgbColor(40, 40, 50))),
        ),
      );
      return;
    }
    if (line.trim().isEmpty) {
      _rows.add(const Text(''));
      return;
    }
    if (line.trimLeft().startsWith('```')) {
      _inFence = true;
      return;
    }
    if (_horizontalRulePattern.hasMatch(line)) {
      _rows.add(Text('─' * 40, style: base.merge(const CellStyle(dim: true))));
      return;
    }
    final heading = _headingPattern.firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.length;
      final body = heading.group(2)!;
      final hStyle = base.merge(
        CellStyle(
          bold: true,
          // H1 inverts for emphasis; H2/H3 just bold + underline. A color
          // tint reinforces the depth hierarchy.
          underline: level > 1,
          inverse: level == 1,
          foreground: switch (level) {
            1 => h1,
            2 => h2,
            _ => null,
          },
        ),
      );
      _rows.add(RichText(text: _inlineSpan(body, hStyle)));
      return;
    }
    if (line.trimLeft().startsWith('> ')) {
      final body = line.trimLeft().substring(2);
      final qStyle = base.merge(const CellStyle(dim: true));
      _rows.add(
        RichText(
          text: TextSpan(
            style: qStyle,
            children: [
              const TextSpan(text: '│ '),
              _inlineSpan(body, qStyle),
            ],
          ),
        ),
      );
      return;
    }
    final bullet = _bulletPattern.firstMatch(line);
    if (bullet != null) {
      final indent = ' ' * bullet.group(1)!.length;
      final body = bullet.group(2)!;
      _rows.add(
        RichText(
          text: TextSpan(
            style: base,
            children: [
              TextSpan(text: '$indent• '),
              _inlineSpan(body, base),
            ],
          ),
        ),
      );
      return;
    }
    final ordered = _orderedPattern.firstMatch(line);
    if (ordered != null) {
      final indent = ' ' * ordered.group(1)!.length;
      final num = ordered.group(2)!;
      final body = ordered.group(3)!;
      _rows.add(
        RichText(
          text: TextSpan(
            style: base,
            children: [
              TextSpan(text: '$indent$num. '),
              _inlineSpan(body, base),
            ],
          ),
        ),
      );
      return;
    }
    _rows.add(RichText(text: _inlineSpan(line, base)));
  }
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
  _inline(src, CellStyle.none, links: links, blockIndex: blockIndex);
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
