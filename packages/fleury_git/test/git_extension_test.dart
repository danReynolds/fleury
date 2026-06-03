import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_git/fleury_git.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _hostTheme = FleuryWidgetTheme(
  logSuccessStyle: CellStyle(foreground: AnsiColor(2)),
);

final class _Capture extends StatelessWidget {
  const _Capture(this.capture);

  final void Function(BuildContext context) capture;

  @override
  Widget build(BuildContext context) {
    capture(context);
    return const Text('capture');
  }
}

void main() {
  test('GitRepositorySnapshot reports compact labels', () {
    const clean = GitRepositorySnapshot(root: '/repo/fleury', branch: 'main');
    expect(clean.statusLabel, 'main - clean');
    expect(clean.isClean, isTrue);

    const changed = GitRepositorySnapshot(
      root: '/repo/fleury',
      branch: 'feature',
      staged: 2,
      unstaged: 1,
      ahead: 1,
    );
    expect(changed.changeCount, 3);
    expect(changed.statusLabel, 'feature - 3 changes - ahead 1');

    const conflicted = GitRepositorySnapshot(
      root: '/repo/fleury',
      detachedHead: true,
      conflicted: 1,
      behind: 2,
    );
    expect(conflicted.branchLabel, 'detached');
    expect(conflicted.statusLabel, 'detached - 1 conflict - behind 2');
  });

  testWidgets('extension contributes commands, status, data, and theme', (
    tester,
  ) async {
    const source = StaticGitRepositoryDataSource(
      GitRepositorySnapshot(
        root: '/repo/fleury',
        branch: 'main',
        staged: 1,
        untracked: 1,
        ahead: 1,
        lastCommit: 'abc123',
      ),
    );
    final calls = <String>[];
    GitRepositoryDataSource? capturedSource;
    FleuryWidgetTheme? capturedTheme;

    tester.pumpWidget(
      FleuryApp(
        title: 'Git App',
        extensions: [
          FleuryGitExtension(
            dataSource: source,
            onRefresh: (context, source) {
              calls.add('refresh:${source.snapshot.branchLabel}');
            },
            onOpenChanges: (context, source) {
              calls.add('changes:${source.snapshot.changeCount}');
            },
            onPush: (context, source) {
              calls.add('push:${source.snapshot.ahead}');
            },
          ),
        ],
        child: Column(
          children: [
            const AppStatusBar(),
            _Capture((context) {
              capturedSource = FleuryApp.dataSource<GitRepositoryDataSource>(
                context,
              );
              capturedTheme = FleuryWidgetTheme.of(context);
            }),
            const GitStatusPanel(),
          ],
        ),
      ),
    );

    expect(capturedSource, same(source));
    expect(
      capturedTheme?.resolveLogSuccess(ThemeData.fallback),
      const CellStyle(foreground: AnsiColor(10)),
    );
    expect(tester.exists(text('Git: main - 2 changes - ahead 1')), isTrue);

    final panel = tester.semantics().single(
      role: SemanticRole.status,
      label: 'Git repository',
    );
    expect(panel.value, 'main - 2 changes - ahead 1');
    expect(panel.state['gitRoot'], '/repo/fleury');
    expect(panel.state['gitBranch'], 'main');
    expect(panel.state['gitChangeCount'], 2);
    expect(panel.state['gitAhead'], 1);
    expect(panel.state['gitLastCommit'], 'abc123');

    final refresh = await tester.invokeCommand(gitRefreshCommandId);
    final changes = await tester.invokeCommand(gitOpenChangesCommandId);
    final push = await tester.invokeCommand(gitPushCommandId);

    expect(refresh.completed, isTrue);
    expect(changes.completed, isTrue);
    expect(push.completed, isTrue);
    expect(calls, ['refresh:main', 'changes:2', 'push:1']);
  });

  testWidgets('host commands and themes remain authoritative', (tester) async {
    const source = StaticGitRepositoryDataSource(
      GitRepositorySnapshot(root: '/repo/fleury', branch: 'main'),
    );
    final calls = <String>[];
    FleuryWidgetTheme? capturedTheme;

    tester.pumpWidget(
      Theme(
        data: ThemeData(extensions: const [_hostTheme]),
        child: FleuryApp(
          title: 'Git App',
          commands: [
            AppCommand(
              id: gitRefreshCommandId,
              title: 'Host Refresh',
              run: (_) {
                calls.add('host');
              },
            ),
          ],
          extensions: [
            FleuryGitExtension(
              dataSource: source,
              onRefresh: (context, source) {
                calls.add('extension');
              },
            ),
          ],
          child: _Capture((context) {
            capturedTheme = FleuryWidgetTheme.of(context);
          }),
        ),
      ),
    );

    final result = await tester.invokeCommand(gitRefreshCommandId);

    expect(result.completed, isTrue);
    expect(result.command?.title, 'Host Refresh');
    expect(calls, ['host']);
    expect(capturedTheme, same(_hostTheme));
  });

  testWidgets('disabled commands report disabled when snapshot lacks work', (
    tester,
  ) async {
    const source = StaticGitRepositoryDataSource(
      GitRepositorySnapshot(root: '/repo/fleury', branch: 'main'),
    );
    final calls = <String>[];

    tester.pumpWidget(
      FleuryApp(
        title: 'Git App',
        extensions: [
          FleuryGitExtension(
            dataSource: source,
            onOpenChanges: (context, source) {
              calls.add('changes');
            },
            onPush: (context, source) {
              calls.add('push');
            },
          ),
        ],
        child: const GitStatusPanel(),
      ),
    );

    final changes = await tester.invokeCommand(gitOpenChangesCommandId);
    final push = await tester.invokeCommand(gitPushCommandId);

    expect(changes.status, CommandInvocationStatus.disabled);
    expect(push.status, CommandInvocationStatus.disabled);
    expect(calls, isEmpty);
    expect(tester.exists(text('Git: main - clean')), isTrue);
  });
}
