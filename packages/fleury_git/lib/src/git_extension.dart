import 'dart:async' show FutureOr;

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

const gitRefreshCommandId = CommandId('git.refresh');
const gitOpenChangesCommandId = CommandId('git.open-changes');
const gitCommitCommandId = CommandId('git.commit');
const gitPushCommandId = CommandId('git.push');

const _gitWidgetTheme = FleuryWidgetTheme(
  logSuccessStyle: CellStyle(foreground: AnsiColor(10)),
  logWarningStyle: CellStyle(foreground: AnsiColor(11)),
  logErrorStyle: CellStyle(foreground: AnsiColor(9), bold: true),
);

typedef GitCommandCallback =
    FutureOr<void> Function(
      CommandContext context,
      GitRepositoryDataSource source,
    );

/// Immutable repository state supplied by a host app or package.
final class GitRepositorySnapshot {
  const GitRepositorySnapshot({
    required this.root,
    this.branch,
    this.detachedHead = false,
    this.ahead = 0,
    this.behind = 0,
    this.staged = 0,
    this.unstaged = 0,
    this.untracked = 0,
    this.conflicted = 0,
    this.lastCommit,
  }) : assert(ahead >= 0),
       assert(behind >= 0),
       assert(staged >= 0),
       assert(unstaged >= 0),
       assert(untracked >= 0),
       assert(conflicted >= 0);

  final String root;
  final String? branch;
  final bool detachedHead;
  final int ahead;
  final int behind;
  final int staged;
  final int unstaged;
  final int untracked;
  final int conflicted;
  final String? lastCommit;

  int get changeCount => staged + unstaged + untracked + conflicted;
  bool get hasChanges => changeCount > 0;
  bool get isClean => changeCount == 0 && conflicted == 0;
  bool get hasSyncDelta => ahead > 0 || behind > 0;

  String get branchLabel {
    final value = branch;
    if (value != null && value.isNotEmpty) return value;
    return detachedHead ? 'detached' : 'unknown';
  }

  String get changesLabel {
    if (conflicted > 0) {
      return '$conflicted conflict${conflicted == 1 ? '' : 's'}';
    }
    if (changeCount == 0) return 'clean';
    return '$changeCount change${changeCount == 1 ? '' : 's'}';
  }

  String? get syncLabel {
    if (!hasSyncDelta) return null;
    if (ahead > 0 && behind > 0) return 'ahead $ahead behind $behind';
    if (ahead > 0) return 'ahead $ahead';
    return 'behind $behind';
  }

  String get statusLabel {
    final sync = syncLabel;
    if (sync == null) return '$branchLabel - $changesLabel';
    return '$branchLabel - $changesLabel - $sync';
  }

  @override
  bool operator ==(Object other) {
    return other is GitRepositorySnapshot &&
        other.root == root &&
        other.branch == branch &&
        other.detachedHead == detachedHead &&
        other.ahead == ahead &&
        other.behind == behind &&
        other.staged == staged &&
        other.unstaged == unstaged &&
        other.untracked == untracked &&
        other.conflicted == conflicted &&
        other.lastCommit == lastCommit;
  }

  @override
  int get hashCode => Object.hash(
    root,
    branch,
    detachedHead,
    ahead,
    behind,
    staged,
    unstaged,
    untracked,
    conflicted,
    lastCommit,
  );
}

/// App-owned source of repository state.
abstract class GitRepositoryDataSource {
  const GitRepositoryDataSource();

  GitRepositorySnapshot get snapshot;
}

final class StaticGitRepositoryDataSource extends GitRepositoryDataSource {
  const StaticGitRepositoryDataSource(this.snapshot);

  @override
  final GitRepositorySnapshot snapshot;
}

/// Package-shaped Fleury extension for Git-aware developer tools.
///
/// The extension contributes static commands, status, theme defaults, and a
/// typed data source. It deliberately does not discover repositories, run Git,
/// manage subscriptions, cache, or own process lifecycles.
final class FleuryGitExtension extends FleuryAppExtension {
  const FleuryGitExtension({
    required this.dataSource,
    this.onRefresh,
    this.onOpenChanges,
    this.onCommit,
    this.onPush,
    this.theme = _gitWidgetTheme,
  });

  final GitRepositoryDataSource dataSource;
  final GitCommandCallback? onRefresh;
  final GitCommandCallback? onOpenChanges;
  final GitCommandCallback? onCommit;
  final GitCommandCallback? onPush;
  final FleuryWidgetTheme theme;

  @override
  List<AppCommand> get commands => [
    if (onRefresh != null)
      AppCommand(
        id: gitRefreshCommandId,
        title: 'Refresh Git Status',
        description: 'Refresh repository branch and working tree status',
        category: 'Git',
        run: (context) => onRefresh!(context, _sourceFor(context)),
      ),
    if (onOpenChanges != null)
      AppCommand(
        id: gitOpenChangesCommandId,
        title: 'Open Git Changes',
        description: 'Open the repository changes surface',
        category: 'Git',
        semanticAction: SemanticAction.open,
        enabled: (context) => _sourceFor(context).snapshot.hasChanges,
        run: (context) => onOpenChanges!(context, _sourceFor(context)),
      ),
    if (onCommit != null)
      AppCommand(
        id: gitCommitCommandId,
        title: 'Commit Git Changes',
        description: 'Start the host app commit workflow',
        category: 'Git',
        enabled: (context) => _sourceFor(context).snapshot.hasChanges,
        run: (context) => onCommit!(context, _sourceFor(context)),
      ),
    if (onPush != null)
      AppCommand(
        id: gitPushCommandId,
        title: 'Push Git Branch',
        description: 'Start the host app push workflow',
        category: 'Git',
        enabled: (context) => _sourceFor(context).snapshot.ahead > 0,
        run: (context) => onPush!(context, _sourceFor(context)),
      ),
  ];

  @override
  List<StatusItem> status(FleuryAppController app) {
    final snapshot = dataSource.snapshot;
    final factory = snapshot.conflicted > 0
        ? StatusItem.error
        : snapshot.hasChanges
        ? StatusItem.warning
        : StatusItem.success;
    return [
      factory(
        'Git',
        id: 'git',
        value: snapshot.statusLabel,
        action: onRefresh == null ? null : gitRefreshCommandId,
      ),
    ];
  }

  @override
  List<Object> get themeExtensions => [theme];

  @override
  List<Object> get dataSources => [dataSource];

  GitRepositoryDataSource _sourceFor(CommandContext context) {
    return context.maybeAppDataSource<GitRepositoryDataSource>() ?? dataSource;
  }
}

/// Minimal Git status widget consuming [GitRepositoryDataSource].
class GitStatusPanel extends StatelessWidget {
  const GitStatusPanel({
    super.key,
    this.snapshot,
    this.source,
    this.label = 'Git repository',
  });

  final GitRepositorySnapshot? snapshot;
  final GitRepositoryDataSource? source;
  final String label;

  @override
  Widget build(BuildContext context) {
    final snapshot =
        this.snapshot ??
        source?.snapshot ??
        FleuryApp.maybeDataSource<GitRepositoryDataSource>(context)?.snapshot;
    if (snapshot == null) {
      return Semantics(
        role: SemanticRole.status,
        label: label,
        value: 'unavailable',
        state: const SemanticState({'gitAvailable': false}),
        child: const Text('Git: unavailable'),
      );
    }

    final theme = Theme.of(context);
    final widgetTheme = FleuryWidgetTheme.of(context);
    final style = snapshot.conflicted > 0
        ? widgetTheme.resolveLogError(theme)
        : snapshot.hasChanges
        ? widgetTheme.resolveLogWarning(theme)
        : widgetTheme.resolveLogSuccess(theme);

    return Semantics(
      role: SemanticRole.status,
      label: label,
      value: snapshot.statusLabel,
      state: SemanticState({
        'gitAvailable': true,
        'gitRoot': snapshot.root,
        'gitBranch': snapshot.branchLabel,
        'gitDetachedHead': snapshot.detachedHead,
        'gitClean': snapshot.isClean,
        'gitChangeCount': snapshot.changeCount,
        'gitStaged': snapshot.staged,
        'gitUnstaged': snapshot.unstaged,
        'gitUntracked': snapshot.untracked,
        'gitConflicted': snapshot.conflicted,
        'gitAhead': snapshot.ahead,
        'gitBehind': snapshot.behind,
        if (snapshot.lastCommit != null) 'gitLastCommit': snapshot.lastCommit,
      }),
      child: Text('Git: ${snapshot.statusLabel}', style: style),
    );
  }
}
