import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_internal.dart';

/// Component-level defaults for `fleury_widgets`.
///
/// Core [ThemeData] intentionally stays small. This extension carries
/// higher-level widget defaults that only the batteries-included widget package
/// needs. Add it to `ThemeData.extensions` and retrieve it with [of].
final class FleuryWidgetTheme {
  const FleuryWidgetTheme({
    this.switchTrackStyle,
    this.progressFilledStyle,
    this.progressTrackStyle,
    this.dataSelectedStyle,
    this.dataSeparatorStyle,
    this.dataEmptyStyle,
    this.logTraceStyle,
    this.logDebugStyle,
    this.logInfoStyle,
    this.logWarningStyle,
    this.logErrorStyle,
    this.logSuccessStyle,
    this.codeBlankStyle,
    this.codeCommentStyle,
    this.codeImportStyle,
    this.codeDeclarationStyle,
    this.codeKeywordStyle,
    this.codeStringStyle,
    this.codePlainStyle,
    this.diffAdditionStyle,
    this.diffDeletionStyle,
    this.diffHunkHeaderStyle,
    this.diffFileHeaderStyle,
    this.diffMetadataStyle,
    this.jsonErrorStyle,
    this.markdownHeadingStyle,
    this.markdownBlockquoteStyle,
    this.markdownCodeBlockStyle,
    this.markdownRuleStyle,
  });

  static const standard = FleuryWidgetTheme();

  /// Track styling for a switch, including its selected state.
  final CellStyle? switchTrackStyle;
  final CellStyle? progressFilledStyle;
  final CellStyle? progressTrackStyle;
  final CellStyle? dataSelectedStyle;
  final CellStyle? dataSeparatorStyle;
  final CellStyle? dataEmptyStyle;
  final CellStyle? logTraceStyle;
  final CellStyle? logDebugStyle;
  final CellStyle? logInfoStyle;
  final CellStyle? logWarningStyle;
  final CellStyle? logErrorStyle;
  final CellStyle? logSuccessStyle;
  final CellStyle? codeBlankStyle;
  final CellStyle? codeCommentStyle;
  final CellStyle? codeImportStyle;
  final CellStyle? codeDeclarationStyle;
  final CellStyle? codeKeywordStyle;
  final CellStyle? codeStringStyle;
  final CellStyle? codePlainStyle;
  final CellStyle? diffAdditionStyle;
  final CellStyle? diffDeletionStyle;
  final CellStyle? diffHunkHeaderStyle;
  final CellStyle? diffFileHeaderStyle;
  final CellStyle? diffMetadataStyle;
  final CellStyle? jsonErrorStyle;
  final CellStyle? markdownHeadingStyle;
  final CellStyle? markdownBlockquoteStyle;
  final CellStyle? markdownCodeBlockStyle;
  final CellStyle? markdownRuleStyle;

  static FleuryWidgetTheme of(BuildContext context) =>
      Theme.of(context).extension<FleuryWidgetTheme>() ?? standard;

  static FleuryWidgetTheme from(ThemeData theme) =>
      theme.extension<FleuryWidgetTheme>() ?? standard;

  CellStyle resolveSwitchTrack(ThemeData theme, {required bool selected}) =>
      resolveCellStyle(
        cascade: [
          CellStyle.state(
            base: theme.mutedStyle,
            selected: CellStyle(foreground: theme.colorScheme.primary),
          ),
          switchTrackStyle,
        ],
        states: {if (selected) CellStyleState.selected},
      );

  CellStyle resolveProgressFilled(ThemeData theme) =>
      progressFilledStyle ?? CellStyle.none;

  CellStyle resolveProgressTrack(ThemeData theme) =>
      progressTrackStyle ?? const CellStyle(dim: true);

  CellStyle resolveDataSelected(ThemeData theme) =>
      dataSelectedStyle ?? theme.selectionStyle;

  CellStyle resolveDataSeparator(ThemeData theme) =>
      dataSeparatorStyle ?? CellStyle.none;

  CellStyle resolveDataEmpty(ThemeData theme) =>
      dataEmptyStyle ?? theme.mutedStyle;

  CellStyle resolveLogTrace(ThemeData theme) =>
      logTraceStyle ?? const CellStyle(dim: true);

  CellStyle resolveLogDebug(ThemeData theme) =>
      logDebugStyle ?? const CellStyle(dim: true);

  CellStyle resolveLogInfo(ThemeData theme) => logInfoStyle ?? CellStyle.none;

  CellStyle resolveLogWarning(ThemeData theme) =>
      logWarningStyle ??
      CellStyle(bold: true, foreground: theme.colorScheme.warning);

  CellStyle resolveLogError(ThemeData theme) =>
      logErrorStyle ??
      CellStyle(bold: true, foreground: theme.colorScheme.error);

  CellStyle resolveLogSuccess(ThemeData theme) =>
      logSuccessStyle ??
      CellStyle(bold: true, foreground: theme.colorScheme.success);

  CellStyle resolveCodeBlank(ThemeData theme) =>
      codeBlankStyle ?? CellStyle.none;

  CellStyle resolveCodeComment(ThemeData theme) =>
      codeCommentStyle ?? const CellStyle(dim: true);

  CellStyle resolveCodeImport(ThemeData theme) =>
      codeImportStyle ?? const CellStyle(foreground: AnsiColor(14));

  CellStyle resolveCodeDeclaration(ThemeData theme) =>
      codeDeclarationStyle ??
      const CellStyle(foreground: AnsiColor(13), bold: true);

  CellStyle resolveCodeKeyword(ThemeData theme) =>
      codeKeywordStyle ?? const CellStyle(foreground: AnsiColor(12));

  CellStyle resolveCodeString(ThemeData theme) =>
      codeStringStyle ?? const CellStyle(foreground: AnsiColor(10));

  CellStyle resolveCodePlain(ThemeData theme) =>
      codePlainStyle ?? CellStyle.none;

  CellStyle resolveDiffAddition(ThemeData theme) =>
      diffAdditionStyle ?? const CellStyle(foreground: AnsiColor(10));

  CellStyle resolveDiffDeletion(ThemeData theme) =>
      diffDeletionStyle ?? const CellStyle(foreground: AnsiColor(9));

  CellStyle resolveDiffHunkHeader(ThemeData theme) =>
      diffHunkHeaderStyle ??
      const CellStyle(foreground: AnsiColor(14), bold: true);

  CellStyle resolveDiffFileHeader(ThemeData theme) =>
      diffFileHeaderStyle ??
      const CellStyle(foreground: AnsiColor(13), bold: true);

  CellStyle resolveDiffMetadata(ThemeData theme) =>
      diffMetadataStyle ?? const CellStyle(dim: true);

  CellStyle resolveJsonError(ThemeData theme) =>
      jsonErrorStyle ?? theme.errorStyle;

  CellStyle resolveMarkdownHeading(ThemeData theme, int? level) {
    final lvl = level ?? 1;
    // Color reinforces the depth hierarchy on top of the structural cues
    // (H1 reverse bar, H2+ underline): primary for H1, info for H2, and no
    // tint for H3 so the emphasis recedes with depth. An explicit
    // markdownHeadingStyle still overrides everything.
    final color = switch (lvl) {
      1 => theme.colorScheme.primary,
      2 => theme.colorScheme.info,
      _ => null,
    };
    final fallback = CellStyle(
      bold: true,
      underline: lvl > 1,
      reverse: lvl == 1,
      foreground: color,
    );
    return markdownHeadingStyle ?? fallback;
  }

  CellStyle resolveMarkdownBlockquote(ThemeData theme) =>
      markdownBlockquoteStyle ?? theme.mutedStyle;

  CellStyle resolveMarkdownCodeBlock(ThemeData theme) =>
      markdownCodeBlockStyle ??
      const CellStyle(background: RgbColor(40, 40, 50));

  CellStyle resolveMarkdownRule(ThemeData theme) =>
      markdownRuleStyle ?? theme.mutedStyle;

  FleuryWidgetTheme copyWith({
    CellStyle? switchTrackStyle,
    CellStyle? progressFilledStyle,
    CellStyle? progressTrackStyle,
    CellStyle? dataSelectedStyle,
    CellStyle? dataSeparatorStyle,
    CellStyle? dataEmptyStyle,
    CellStyle? logTraceStyle,
    CellStyle? logDebugStyle,
    CellStyle? logInfoStyle,
    CellStyle? logWarningStyle,
    CellStyle? logErrorStyle,
    CellStyle? logSuccessStyle,
    CellStyle? codeBlankStyle,
    CellStyle? codeCommentStyle,
    CellStyle? codeImportStyle,
    CellStyle? codeDeclarationStyle,
    CellStyle? codeKeywordStyle,
    CellStyle? codeStringStyle,
    CellStyle? codePlainStyle,
    CellStyle? diffAdditionStyle,
    CellStyle? diffDeletionStyle,
    CellStyle? diffHunkHeaderStyle,
    CellStyle? diffFileHeaderStyle,
    CellStyle? diffMetadataStyle,
    CellStyle? jsonErrorStyle,
    CellStyle? markdownHeadingStyle,
    CellStyle? markdownBlockquoteStyle,
    CellStyle? markdownCodeBlockStyle,
    CellStyle? markdownRuleStyle,
  }) {
    return FleuryWidgetTheme(
      switchTrackStyle: switchTrackStyle ?? this.switchTrackStyle,
      progressFilledStyle: progressFilledStyle ?? this.progressFilledStyle,
      progressTrackStyle: progressTrackStyle ?? this.progressTrackStyle,
      dataSelectedStyle: dataSelectedStyle ?? this.dataSelectedStyle,
      dataSeparatorStyle: dataSeparatorStyle ?? this.dataSeparatorStyle,
      dataEmptyStyle: dataEmptyStyle ?? this.dataEmptyStyle,
      logTraceStyle: logTraceStyle ?? this.logTraceStyle,
      logDebugStyle: logDebugStyle ?? this.logDebugStyle,
      logInfoStyle: logInfoStyle ?? this.logInfoStyle,
      logWarningStyle: logWarningStyle ?? this.logWarningStyle,
      logErrorStyle: logErrorStyle ?? this.logErrorStyle,
      logSuccessStyle: logSuccessStyle ?? this.logSuccessStyle,
      codeBlankStyle: codeBlankStyle ?? this.codeBlankStyle,
      codeCommentStyle: codeCommentStyle ?? this.codeCommentStyle,
      codeImportStyle: codeImportStyle ?? this.codeImportStyle,
      codeDeclarationStyle: codeDeclarationStyle ?? this.codeDeclarationStyle,
      codeKeywordStyle: codeKeywordStyle ?? this.codeKeywordStyle,
      codeStringStyle: codeStringStyle ?? this.codeStringStyle,
      codePlainStyle: codePlainStyle ?? this.codePlainStyle,
      diffAdditionStyle: diffAdditionStyle ?? this.diffAdditionStyle,
      diffDeletionStyle: diffDeletionStyle ?? this.diffDeletionStyle,
      diffHunkHeaderStyle: diffHunkHeaderStyle ?? this.diffHunkHeaderStyle,
      diffFileHeaderStyle: diffFileHeaderStyle ?? this.diffFileHeaderStyle,
      diffMetadataStyle: diffMetadataStyle ?? this.diffMetadataStyle,
      jsonErrorStyle: jsonErrorStyle ?? this.jsonErrorStyle,
      markdownHeadingStyle: markdownHeadingStyle ?? this.markdownHeadingStyle,
      markdownBlockquoteStyle:
          markdownBlockquoteStyle ?? this.markdownBlockquoteStyle,
      markdownCodeBlockStyle:
          markdownCodeBlockStyle ?? this.markdownCodeBlockStyle,
      markdownRuleStyle: markdownRuleStyle ?? this.markdownRuleStyle,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FleuryWidgetTheme &&
        other.switchTrackStyle == switchTrackStyle &&
        other.progressFilledStyle == progressFilledStyle &&
        other.progressTrackStyle == progressTrackStyle &&
        other.dataSelectedStyle == dataSelectedStyle &&
        other.dataSeparatorStyle == dataSeparatorStyle &&
        other.dataEmptyStyle == dataEmptyStyle &&
        other.logTraceStyle == logTraceStyle &&
        other.logDebugStyle == logDebugStyle &&
        other.logInfoStyle == logInfoStyle &&
        other.logWarningStyle == logWarningStyle &&
        other.logErrorStyle == logErrorStyle &&
        other.logSuccessStyle == logSuccessStyle &&
        other.codeBlankStyle == codeBlankStyle &&
        other.codeCommentStyle == codeCommentStyle &&
        other.codeImportStyle == codeImportStyle &&
        other.codeDeclarationStyle == codeDeclarationStyle &&
        other.codeKeywordStyle == codeKeywordStyle &&
        other.codeStringStyle == codeStringStyle &&
        other.codePlainStyle == codePlainStyle &&
        other.diffAdditionStyle == diffAdditionStyle &&
        other.diffDeletionStyle == diffDeletionStyle &&
        other.diffHunkHeaderStyle == diffHunkHeaderStyle &&
        other.diffFileHeaderStyle == diffFileHeaderStyle &&
        other.diffMetadataStyle == diffMetadataStyle &&
        other.jsonErrorStyle == jsonErrorStyle &&
        other.markdownHeadingStyle == markdownHeadingStyle &&
        other.markdownBlockquoteStyle == markdownBlockquoteStyle &&
        other.markdownCodeBlockStyle == markdownCodeBlockStyle &&
        other.markdownRuleStyle == markdownRuleStyle;
  }

  @override
  int get hashCode => Object.hashAll([
    switchTrackStyle,
    progressFilledStyle,
    progressTrackStyle,
    dataSelectedStyle,
    dataSeparatorStyle,
    dataEmptyStyle,
    logTraceStyle,
    logDebugStyle,
    logInfoStyle,
    logWarningStyle,
    logErrorStyle,
    logSuccessStyle,
    codeBlankStyle,
    codeCommentStyle,
    codeImportStyle,
    codeDeclarationStyle,
    codeKeywordStyle,
    codeStringStyle,
    codePlainStyle,
    diffAdditionStyle,
    diffDeletionStyle,
    diffHunkHeaderStyle,
    diffFileHeaderStyle,
    diffMetadataStyle,
    jsonErrorStyle,
    markdownHeadingStyle,
    markdownBlockquoteStyle,
    markdownCodeBlockStyle,
    markdownRuleStyle,
  ]);
}
