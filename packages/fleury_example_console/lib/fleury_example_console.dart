library;

import 'dart:async' show Completer, unawaited;
import 'dart:io' show Platform;

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

const demoScreenOverview = 'overview';
const demoScreenSearch = 'search';
const demoScreenIndex = 'index';
const demoScreenConnection = 'connection';
const demoScreenRuns = 'runs';
const demoScreenTree = 'tree';
const demoScreenPayload = 'payload';
const demoScreenChanges = 'changes';
const demoScreenSource = 'source';
const demoScreenDocs = 'docs';
const demoScreenTranscript = 'transcript';
const demoScreenProcess = 'process';
const demoScreenDiagnostics = 'diagnostics';

const demoCommandOpenPalette = CommandId('app.openPalette');
const demoCommandGoOverview = CommandId('screen.overview');
const demoCommandGoSearch = CommandId('screen.search');
const demoCommandGoIndex = CommandId('screen.index');
const demoCommandGoConnection = CommandId('screen.connection');
const demoCommandGoRuns = CommandId('screen.runs');
const demoCommandGoTree = CommandId('screen.tree');
const demoCommandGoPayload = CommandId('screen.payload');
const demoCommandGoChanges = CommandId('screen.changes');
const demoCommandGoSource = CommandId('screen.source');
const demoCommandGoDocs = CommandId('screen.docs');
const demoCommandGoTranscript = CommandId('screen.transcript');
const demoCommandGoProcess = CommandId('screen.process');
const demoCommandGoDiagnostics = CommandId('screen.diagnostics');
const demoCommandStartTask = CommandId('task.startFake');
const demoCommandCancelTask = CommandId('task.cancelFake');
const demoCommandRunProcess = CommandId('process.dartVersion.start');
const demoCommandCancelProcess = CommandId('process.dartVersion.cancel');
const demoCommandRequestApproval = CommandId('approval.deploy.request');
const demoCommandToggleStream = CommandId('logs.toggleStream');
const demoCommandDiagnose = CommandId('terminal.diagnose');
const demoCommandCaptureDebug = CommandId('debug.captureSnapshot');
const demoCommandFocusRunsFilter = CommandId('runs.focusFilter');
const demoCommandFocusRunsTable = CommandId('runs.focusTable');
const demoCommandFocusTreeTable = CommandId('tree.focusTable');
const demoCommandFocusPayload = CommandId('payload.focusJson');
const demoCommandFocusChanges = CommandId('changes.focusDiff');
const demoCommandFocusSource = CommandId('source.focusCode');
const demoCommandFocusDocs = CommandId('docs.focusMarkdown');
const demoCommandFocusSearch = CommandId('search.focusQuery');
const demoCommandBuildLogIndex = CommandId('index.buildLogs');
const demoCommandAppendIndexedLogBurst = CommandId('index.appendLogBurst');
const demoCommandFocusIndexFilter = CommandId('index.focusFilter');
const demoCommandFocusIndexLog = CommandId('index.focusLog');
const demoCommandFocusComposer = CommandId('transcript.focusComposer');
const demoCommandAppendLogBurst = CommandId('transcript.appendLogBurst');

const demoIndexedLogInitialCount = 192;
const demoIndexedLogAppendCount = 3;

const _demoIndexYieldPolicy = TaskYieldPolicy(
  itemBudget: 16,
  elapsedBudget: Duration(days: 1),
);

const _demoWidgetTheme = FleuryWidgetTheme(
  controlFocusStyle: CellStyle(bold: true, foreground: AnsiColor(14)),
  progressFilledStyle: CellStyle(foreground: AnsiColor(10)),
  progressTrackStyle: CellStyle(dim: true),
  dataSelectedStyle: CellStyle(inverse: true, foreground: AnsiColor(14)),
  dataSeparatorStyle: CellStyle(foreground: AnsiColor(8)),
  logWarningStyle: CellStyle(bold: true, foreground: AnsiColor(11)),
  logErrorStyle: CellStyle(bold: true, foreground: AnsiColor(9)),
  logSuccessStyle: CellStyle(bold: true, foreground: AnsiColor(10)),
  codeImportStyle: CellStyle(foreground: AnsiColor(14)),
  codeDeclarationStyle: CellStyle(bold: true, foreground: AnsiColor(13)),
  codeKeywordStyle: CellStyle(foreground: AnsiColor(12)),
  codeStringStyle: CellStyle(foreground: AnsiColor(10)),
  diffAdditionStyle: CellStyle(foreground: AnsiColor(10)),
  diffDeletionStyle: CellStyle(foreground: AnsiColor(9)),
  diffHunkHeaderStyle: CellStyle(bold: true, foreground: AnsiColor(14)),
  markdownHeadingStyle: CellStyle(bold: true, foreground: AnsiColor(14)),
  markdownCodeBlockStyle: CellStyle(background: AnsiColor(8)),
);

const _demoTheme = ThemeData(
  colorScheme: ColorScheme(
    primary: AnsiColor(14),
    success: AnsiColor(10),
    warning: AnsiColor(11),
    error: AnsiColor(9),
    info: AnsiColor(12),
  ),
  focusedStyle: CellStyle(bold: true, foreground: AnsiColor(14)),
  selectionStyle: CellStyle(inverse: true, bold: true),
);

final class RunRecord {
  const RunRecord({
    required this.id,
    required this.status,
    required this.title,
    required this.owner,
    required this.duration,
    required this.progress,
    required this.warnings,
  });

  final String id;
  final String status;
  final String title;
  final String owner;
  final String duration;
  final int progress;
  final int warnings;
}

final class TranscriptEvent {
  const TranscriptEvent({
    required this.id,
    required this.source,
    required this.kind,
    required this.text,
  });

  final int id;
  final String source;
  final String kind;
  final String text;
}

/// Package-owned global-search read model contributed by
/// [DemoConsoleExtension].
final class DemoSearchDataSource {
  const DemoSearchDataSource({required this.runs, required this.transcript});

  final List<RunRecord> runs;
  final List<TranscriptEvent> transcript;

  List<SearchResult> buildCorpus() {
    return _globalSearchCorpus(runs: runs, transcript: transcript);
  }
}

/// App-level demo extension registered through `FleuryApp.extensions`.
///
/// The demo app uses this as an integration handle for package-owned workflow
/// state. Core Fleury only provides typed lookup; this package owns the model
/// shape and lifecycle.
final class DemoConsoleExtension extends FleuryAppExtension {
  const DemoConsoleExtension({
    required this.workflowId,
    required this.streaming,
    required this.debugCaptures,
    required this.transcriptCount,
    required this.search,
    required this.recordDiagnostic,
    required this.activateScreen,
  });

  final String workflowId;
  final bool streaming;
  final int debugCaptures;
  final int transcriptCount;
  final DemoSearchDataSource search;
  final void Function() recordDiagnostic;
  final bool Function(String screenId) activateScreen;

  String get streamStatusValue => streaming ? 'on' : 'paused';
  String get debugStatusValue => 'captures $debugCaptures';

  @override
  List<AppCommand> get commands => [
    AppCommand(
      id: demoCommandDiagnose,
      title: 'Run Terminal Diagnose',
      description: 'Open diagnostics and record a synthetic report',
      category: 'Diagnostics',
      semanticAction: SemanticAction.diagnose,
      run: (context) {
        context.appExtension<DemoConsoleExtension>().activateScreen(
          demoScreenDiagnostics,
        );
        context.appExtension<DemoConsoleExtension>().recordDiagnostic();
      },
    ),
  ];

  @override
  List<StatusItem> status(FleuryAppController app) => [
    StatusItem.text(
      'Stream',
      id: 'stream',
      value: streamStatusValue,
      action: demoCommandToggleStream,
    ),
    StatusItem.text(
      'Debug',
      id: 'debug',
      value: debugStatusValue,
      action: demoCommandCaptureDebug,
    ),
  ];

  @override
  List<Object> get themeExtensions => const [_demoWidgetTheme];

  @override
  List<Object> get dataSources => [search];
}

/// First demo app for the Phase 1 Fleury framework loop.
///
/// This is an internal integration harness, not a polished public example.
/// It deliberately uses app-shell commands, screens, status, command palette,
/// text input, table, progress, key hints, and semantic/test surfaces together.
class DemoConsoleApp extends StatefulWidget {
  const DemoConsoleApp({super.key});

  @override
  State<DemoConsoleApp> createState() => _DemoConsoleAppState();
}

typedef _DemoScreenBuilder = Widget Function(BuildContext context);

final class _DemoScreenSpec {
  const _DemoScreenSpec({
    required this.id,
    required this.title,
    required this.builder,
    this.shortTitle,
    this.description,
    this.commands = const <AppCommand>[],
  });

  final String id;
  final String title;
  final _DemoScreenBuilder builder;
  final String? shortTitle;
  final String? description;
  final List<AppCommand> commands;
}

final class _DemoNavigationController extends ChangeNotifier {
  _DemoNavigationController(this.activeScreenId);

  String activeScreenId;

  bool activate(String screenId) {
    if (activeScreenId == screenId) return true;
    activeScreenId = screenId;
    notifyListeners();
    return true;
  }

  void refresh() {
    notifyListeners();
  }
}

class _DemoConsoleAppState extends State<DemoConsoleApp> {
  final _runsFilter = TextEditingController();
  final _globalSearchQuery = TextEditingController();
  final _indexedLogFilter = TextEditingController();
  final _composer = TextEditingController();
  final _composerHistory = TextHistoryController();
  final _transcriptMessages = MessageListController();
  final _runsFilterFocus = FocusNode(debugLabel: 'runs filter');
  final _globalSearchFocus = FocusNode(debugLabel: 'global search query');
  final _globalSearchResultsFocus = FocusNode(
    debugLabel: 'global search results',
  );
  final _indexedLogFilterFocus = FocusNode(debugLabel: 'indexed log filter');
  final _indexedLogFocus = FocusNode(debugLabel: 'indexed log region');
  final _runsTableFocus = FocusNode(debugLabel: 'runs table');
  final _treeTableFocus = FocusNode(debugLabel: 'tree table');
  final _payloadFocus = FocusNode(debugLabel: 'payload json');
  final _changesFocus = FocusNode(debugLabel: 'changes diff');
  final _sourceFocus = FocusNode(debugLabel: 'source code');
  final _docsFocus = FocusNode(debugLabel: 'docs markdown');
  final _composerFocus = FocusNode(debugLabel: 'transcript composer');
  final _transcriptFocus = FocusNode(debugLabel: 'transcript messages');
  final _runsTable = DataTableController(selectedIndex: 0);
  final _globalSearchList = ListController(selectedIndex: 0);
  final _indexedLogController = LogRegionController(followTail: false);
  final _treeTable = TreeTableController(expandedKeys: const {'core'});
  final _payloadJson = JsonViewController();
  final _changesReview = PatchReviewController();
  final _changesDiff = DiffViewController(selectedIndex: 7);
  final _sourceCode = CodeViewController(selectedIndex: 7);
  final _docsMarkdown = MarkdownViewController(selectedIndex: 5);
  final _connectionForm = FormController(_connectionFormDefinition);
  final _task = TaskController<void>(id: 'fake-task', label: 'Fake task');
  final _logIndexTask = TaskController<LogRegionSearchIndex>(
    id: 'demo-log-index',
    label: 'Demo log index',
  );
  final _globalSearchTask = DebouncedTaskController<List<SearchResult>>(
    delay: const Duration(milliseconds: 60),
    id: 'global-search',
    label: 'Global search',
  );
  final _process = ProcessTaskController(
    id: 'dart-version',
    label: 'Dart version',
  );
  late final ProcessCommandRunner _processRunner;

  final _navigation = _DemoNavigationController(demoScreenOverview);
  Completer<void>? _fakeTaskCompleter;
  bool _streaming = true;
  int _debugCaptures = 0;
  int _logBurst = 0;
  int _nextTranscriptEventId = 2;
  String _globalSearchResolvedQuery = '';
  List<SearchResult> _globalSearchResults = const <SearchResult>[];
  late final List<LogEntry> _indexedLogs = _buildDemoIndexedLogs(
    demoIndexedLogInitialCount,
  );
  LogRegionSearchIndex? _indexedLogSearchIndex;

  late final List<RunRecord> _runs = const [
    RunRecord(
      id: 'RUN-1001',
      status: 'running',
      title: 'Index workspace',
      owner: 'agent',
      duration: '00:12',
      progress: 42,
      warnings: 0,
    ),
    RunRecord(
      id: 'RUN-1002',
      status: 'failed',
      title: 'API deploy smoke',
      owner: 'ops',
      duration: '01:34',
      progress: 100,
      warnings: 3,
    ),
    RunRecord(
      id: 'RUN-1003',
      status: 'passed',
      title: 'Widget semantic sweep',
      owner: 'qa',
      duration: '02:08',
      progress: 100,
      warnings: 1,
    ),
    RunRecord(
      id: 'RUN-1004',
      status: 'queued',
      title: 'Terminal capability scan',
      owner: 'cli',
      duration: '--:--',
      progress: 0,
      warnings: 0,
    ),
  ];

  final List<TranscriptEvent> _transcript = [
    const TranscriptEvent(
      id: 0,
      source: 'system',
      kind: 'info',
      text: 'Demo console booted with deterministic fixtures.',
    ),
    const TranscriptEvent(
      id: 1,
      source: 'worker',
      kind: 'log',
      text: 'Waiting for a fake task.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _processRunner = ProcessCommandRunner(
      controller: _process,
      command: ProcessTaskCommand(Platform.resolvedExecutable, ['--version']),
      startCommandId: demoCommandRunProcess,
      cancelCommandId: demoCommandCancelProcess,
      title: 'Run Dart Version',
      cancelTitle: 'Cancel Dart Version',
      category: 'Process',
      shortcuts: [KeyChord.ctrl.enter],
      cancelShortcuts: [KeyChord.ctrl.x],
    );
    _runsFilter.addListener(_rebuild);
    _globalSearchQuery.addListener(_scheduleGlobalSearch);
    _indexedLogFilter.addListener(_rebuild);
    _runsTable.addListener(_rebuild);
    _globalSearchTask.addListener(_rebuild);
    _indexedLogController.addListener(_rebuild);
    _logIndexTask.addListener(_rebuild);
    _payloadJson.addListener(_rebuild);
    _changesReview.addListener(_rebuild);
    _changesDiff.addListener(_rebuild);
    _sourceCode.addListener(_rebuild);
    _docsMarkdown.addListener(_rebuild);
    _connectionForm.addListener(_rebuild);
    _task.addListener(_rebuild);
    _process.addListener(_rebuild);
  }

  @override
  void dispose() {
    _runsFilter.removeListener(_rebuild);
    _globalSearchQuery.removeListener(_scheduleGlobalSearch);
    _indexedLogFilter.removeListener(_rebuild);
    _runsTable.removeListener(_rebuild);
    _globalSearchTask.removeListener(_rebuild);
    _indexedLogController.removeListener(_rebuild);
    _logIndexTask.removeListener(_rebuild);
    _payloadJson.removeListener(_rebuild);
    _changesReview.removeListener(_rebuild);
    _changesDiff.removeListener(_rebuild);
    _sourceCode.removeListener(_rebuild);
    _docsMarkdown.removeListener(_rebuild);
    _connectionForm.removeListener(_rebuild);
    _task.removeListener(_rebuild);
    _process.removeListener(_rebuild);
    if (_task.isRunning) _task.cancel();
    if (_logIndexTask.isRunning) _logIndexTask.cancel();
    _globalSearchTask.cancel();
    if (_process.isRunning) _process.cancel();
    _completeFakeTask();
    _runsFilter.dispose();
    _globalSearchQuery.dispose();
    _indexedLogFilter.dispose();
    _composer.dispose();
    _composerHistory.dispose();
    _transcriptMessages.dispose();
    _runsFilterFocus.dispose();
    _globalSearchFocus.dispose();
    _globalSearchResultsFocus.dispose();
    _indexedLogFilterFocus.dispose();
    _indexedLogFocus.dispose();
    _runsTableFocus.dispose();
    _treeTableFocus.dispose();
    _payloadFocus.dispose();
    _changesFocus.dispose();
    _sourceFocus.dispose();
    _docsFocus.dispose();
    _composerFocus.dispose();
    _transcriptFocus.dispose();
    _runsTable.dispose();
    _globalSearchList.dispose();
    _indexedLogController.dispose();
    _treeTable.dispose();
    _payloadJson.dispose();
    _changesReview.dispose();
    _changesDiff.dispose();
    _sourceCode.dispose();
    _docsMarkdown.dispose();
    _connectionForm.dispose();
    _task.dispose();
    _logIndexTask.dispose();
    _globalSearchTask.dispose();
    _process.dispose();
    _navigation.dispose();
    super.dispose();
  }

  void _rebuild() {
    _mutate(() {});
  }

  void _mutate(void Function() update) {
    setState(update);
    _navigation.refresh();
  }

  bool get _taskRunning => _task.isRunning;

  int get _taskProgress => (_task.progress?.current ?? 0).round();

  DemoSearchDataSource get _searchDataSource {
    return DemoSearchDataSource(runs: _runs, transcript: _transcript);
  }

  @override
  Widget build(BuildContext context) {
    final searchDataSource = _searchDataSource;
    final extension = DemoConsoleExtension(
      workflowId: 'demo-console',
      streaming: _streaming,
      debugCaptures: _debugCaptures,
      transcriptCount: _transcript.length,
      search: searchDataSource,
      recordDiagnostic: _recordDiagnostic,
      activateScreen: _activateScreen,
    );
    return Theme(
      data: _demoTheme,
      child: FleuryApp(
        title: 'Fleury Demo Console',
        extensions: <Object>[extension],
        commands: _commands,
        status: _status,
        child: Navigator(
          home: _ConsoleShell(
            screens: _screens,
            navigation: _navigation,
            onActivateScreen: _activateScreen,
          ),
        ),
      ),
    );
  }

  List<_DemoScreenSpec> get _screens => [
    _DemoScreenSpec(
      id: demoScreenOverview,
      title: 'Overview',
      shortTitle: 'Home',
      description: 'Summary, task progress, and recent activity',
      commands: [
        AppCommand(
          id: demoCommandStartTask,
          title: 'Start Fake Task',
          category: 'Task',
          enabled: (_) => !_taskRunning,
          semanticAction: SemanticAction.start,
          run: (_) {
            _startTask();
          },
        ),
      ],
      builder: (context) {
        final extension = FleuryApp.extension<DemoConsoleExtension>(context);
        return _OverviewScreen(
          task: _task,
          process: _process,
          processCommand: _processRunner.command,
          transcript: _transcript,
          debugCaptures: extension.debugCaptures,
          streaming: extension.streaming,
          contextItems: _demoContextItems(
            task: _task,
            transcript: _transcript,
            debugCaptures: extension.debugCaptures,
          ),
          onContextSelected: _selectContextItem,
        );
      },
    ),
    _DemoScreenSpec(
      id: demoScreenSearch,
      title: 'Search',
      description: 'Debounced global search across demo app surfaces',
      commands: [
        AppCommand(
          id: demoCommandFocusSearch,
          title: 'Focus Global Search',
          category: 'Search',
          shortcuts: const [KeyChord.char('/')],
          semanticAction: SemanticAction.focus,
          run: (_) {
            _globalSearchFocus.requestFocus();
          },
        ),
      ],
      builder: (_) => _SearchScreen(
        query: _globalSearchQuery,
        queryFocus: _globalSearchFocus,
        resultsFocus: _globalSearchResultsFocus,
        list: _globalSearchList,
        task: _globalSearchTask,
        resolvedQuery: _globalSearchResolvedQuery,
        results: _globalSearchResults,
        onActivateScreen: _activateScreen,
        onActivate: _activateSearchResult,
      ),
    ),
    _DemoScreenSpec(
      id: demoScreenIndex,
      title: 'Indexed Logs',
      shortTitle: 'Index',
      description: 'Cooperative retained-log indexing and filtering',
      commands: [
        AppCommand(
          id: demoCommandBuildLogIndex,
          title: 'Build Demo Log Index',
          category: 'Index',
          semanticAction: SemanticAction.start,
          enabled: (_) => !_logIndexTask.isRunning,
          run: (_) {
            _buildDemoLogIndex();
          },
        ),
        AppCommand(
          id: demoCommandAppendIndexedLogBurst,
          title: 'Append Indexed Log Burst',
          description: 'Append logs and refresh the search index cooperatively',
          category: 'Index',
          semanticAction: SemanticAction.start,
          enabled: (_) => !_logIndexTask.isRunning,
          run: (_) {
            _appendIndexedLogBurst();
          },
        ),
        AppCommand(
          id: demoCommandFocusIndexFilter,
          title: 'Focus Indexed Log Filter',
          category: 'Index',
          shortcuts: const [KeyChord.char('/')],
          semanticAction: SemanticAction.focus,
          run: (_) {
            _indexedLogFilterFocus.requestFocus();
          },
        ),
        AppCommand(
          id: demoCommandFocusIndexLog,
          title: 'Focus Indexed Log Region',
          category: 'Index',
          semanticAction: SemanticAction.focus,
          run: (_) {
            _indexedLogFocus.requestFocus();
          },
        ),
      ],
      builder: (_) => _IndexedLogsScreen(
        entries: _indexedLogs,
        searchIndex: _indexedLogSearchIndex,
        filter: _indexedLogFilter,
        filterFocus: _indexedLogFilterFocus,
        logFocus: _indexedLogFocus,
        controller: _indexedLogController,
        task: _logIndexTask,
      ),
    ),
    _DemoScreenSpec(
      id: demoScreenConnection,
      title: 'Connection',
      description: 'Shared form definition with full-screen and prompt parity',
      builder: (_) => _ConnectionScreen(
        controller: _connectionForm,
        onSubmit: _submitConnection,
      ),
    ),
    _DemoScreenSpec(
      id: demoScreenRuns,
      title: 'Runs',
      description: 'Dense run records with filtering and selection',
      commands: [
        AppCommand(
          id: demoCommandFocusRunsFilter,
          title: 'Focus Run Filter',
          category: 'Runs',
          shortcuts: const [KeyChord.char('/')],
          semanticAction: SemanticAction.focus,
          run: (_) {
            _runsFilterFocus.requestFocus();
          },
        ),
        AppCommand(
          id: demoCommandFocusRunsTable,
          title: 'Focus Runs Table',
          category: 'Runs',
          semanticAction: SemanticAction.focus,
          run: (_) {
            _runsTableFocus.requestFocus();
          },
        ),
      ],
      builder: (_) => _RunsScreen(
        filter: _runsFilter,
        filterFocus: _runsFilterFocus,
        tableFocus: _runsTableFocus,
        table: _runsTable,
        runs: _runs,
        onSelect: _selectRun,
      ),
    ),
    _DemoScreenSpec(
      id: demoScreenTree,
      title: 'Tree',
      description: 'Hierarchical subsystem table with expansion and copy',
      commands: [
        AppCommand(
          id: demoCommandFocusTreeTable,
          title: 'Focus Tree Table',
          category: 'Tree',
          semanticAction: SemanticAction.focus,
          run: (_) {
            _treeTableFocus.requestFocus();
          },
        ),
      ],
      builder: (_) => _TreeTableScreen(
        controller: _treeTable,
        focusNode: _treeTableFocus,
        nodes: _frameworkTreeNodes,
        onSelect: _selectTreeNode,
      ),
    ),
    _DemoScreenSpec(
      id: demoScreenPayload,
      title: 'Payload',
      description: 'Structured JSON payload with path semantics and copy',
      commands: [
        AppCommand(
          id: demoCommandFocusPayload,
          title: 'Focus Payload JSON',
          category: 'Payload',
          semanticAction: SemanticAction.focus,
          run: (_) {
            _payloadFocus.requestFocus();
          },
        ),
      ],
      builder: (_) => _PayloadScreen(
        controller: _payloadJson,
        focusNode: _payloadFocus,
        onCopy: _copyPayload,
      ),
    ),
    _DemoScreenSpec(
      id: demoScreenChanges,
      title: 'Changes',
      description: 'Unified diff with file, hunk, and line semantics',
      commands: [
        AppCommand(
          id: demoCommandFocusChanges,
          title: 'Focus Changes Diff',
          category: 'Changes',
          semanticAction: SemanticAction.focus,
          run: (_) {
            _changesFocus.requestFocus();
          },
        ),
      ],
      builder: (_) => _ChangesScreen(
        reviewController: _changesReview,
        controller: _changesDiff,
        focusNode: _changesFocus,
        onFileSelected: _selectPatchFile,
        onCopy: _copyChange,
      ),
    ),
    _DemoScreenSpec(
      id: demoScreenSource,
      title: 'Source',
      description: 'Code fixture with source-line semantics and safe copy',
      commands: [
        AppCommand(
          id: demoCommandFocusSource,
          title: 'Focus Source Code',
          category: 'Source',
          semanticAction: SemanticAction.focus,
          run: (_) {
            _sourceFocus.requestFocus();
          },
        ),
      ],
      builder: (_) => _SourceScreen(
        controller: _sourceCode,
        focusNode: _sourceFocus,
        onCopy: _copySource,
      ),
    ),
    _DemoScreenSpec(
      id: demoScreenDocs,
      title: 'Docs',
      description: 'Markdown fixture with link semantics and safe copy',
      commands: [
        AppCommand(
          id: demoCommandFocusDocs,
          title: 'Focus Docs Markdown',
          category: 'Docs',
          semanticAction: SemanticAction.focus,
          run: (_) {
            _docsFocus.requestFocus();
          },
        ),
      ],
      builder: (_) => _DocsScreen(
        controller: _docsMarkdown,
        focusNode: _docsFocus,
        onCopy: _copyDocs,
      ),
    ),
    _DemoScreenSpec(
      id: demoScreenTranscript,
      title: 'Transcript',
      description: 'Streamed transcript, logs, and command composer',
      commands: [
        AppCommand(
          id: demoCommandToggleStream,
          title: 'Toggle Log Stream',
          category: 'Transcript',
          enabled: (_) => true,
          run: (_) {
            _mutate(() {
              _streaming = !_streaming;
              _append('logs', _streaming ? 'stream resumed' : 'stream paused');
            });
          },
        ),
        AppCommand(
          id: demoCommandFocusComposer,
          title: 'Focus Composer',
          category: 'Transcript',
          semanticAction: SemanticAction.focus,
          run: (_) {
            _composerFocus.requestFocus();
          },
        ),
        AppCommand(
          id: demoCommandAppendLogBurst,
          title: 'Append Log Burst',
          description: 'Append deterministic streamed log lines',
          category: 'Transcript',
          enabled: (context) =>
              context.appExtension<DemoConsoleExtension>().streaming,
          run: (_) {
            _appendLogBurst();
          },
        ),
      ],
      builder: (_) => _TranscriptScreen(
        transcript: _transcript,
        conversations: _demoConversations(
          task: _task,
          process: _process,
          transcript: _transcript,
          streaming: _streaming,
        ),
        fileMentions: _demoFileMentions,
        composer: _composer,
        composerHistory: _composerHistory,
        composerFocus: _composerFocus,
        transcriptController: _transcriptMessages,
        transcriptFocus: _transcriptFocus,
        streaming: _streaming,
        onConversationSelected: _selectConversation,
        onMentionPicked: _pickFileMention,
        onSubmit: _submitComposer,
      ),
    ),
    _DemoScreenSpec(
      id: demoScreenProcess,
      title: 'Process',
      description: 'Native process command, output, and cancellation surface',
      builder: (_) => ProcessCommandScope(
        runner: _processRunner,
        child: _ProcessScreen(controller: _process, runner: _processRunner),
      ),
    ),
    _DemoScreenSpec(
      id: demoScreenDiagnostics,
      title: 'Diagnostics',
      description: 'Terminal capabilities and debug snapshot actions',
      commands: [
        AppCommand(
          id: demoCommandCaptureDebug,
          title: 'Capture Debug Snapshot',
          category: 'Diagnostics',
          semanticAction: SemanticAction.captureDebug,
          run: (_) {
            _captureDebug();
          },
        ),
      ],
      builder: (context) {
        final extension = FleuryApp.extension<DemoConsoleExtension>(context);
        return _DiagnosticsScreen(
          debugCaptures: extension.debugCaptures,
          streaming: extension.streaming,
          traceEvents: _demoTraceEvents(
            task: _task,
            process: _process,
            transcript: _transcript,
            debugCaptures: extension.debugCaptures,
            streaming: extension.streaming,
          ),
          onTraceSelected: _selectTraceEvent,
        );
      },
    ),
  ];

  List<AppCommand> get _commands => [
    AppCommand(
      id: demoCommandOpenPalette,
      title: 'Open Command Palette',
      description: 'Search and run available commands',
      category: 'App',
      shortcuts: [KeyChord.ctrl.k],
      semanticAction: SemanticAction.open,
      run: _openPalette,
    ),
    _goCommand(
      id: demoCommandGoOverview,
      title: 'Go to Overview',
      screen: demoScreenOverview,
      shortcut: KeyChord.ctrl.o,
    ),
    _goCommand(
      id: demoCommandGoSearch,
      title: 'Go to Search',
      screen: demoScreenSearch,
      shortcut: KeyChord.ctrl.f,
    ),
    _goCommand(
      id: demoCommandGoIndex,
      title: 'Go to Indexed Logs',
      screen: demoScreenIndex,
      shortcut: KeyChord.ctrl.i,
    ),
    _goCommand(
      id: demoCommandGoConnection,
      title: 'Go to Connection',
      screen: demoScreenConnection,
      shortcut: KeyChord.ctrl.l,
    ),
    _goCommand(
      id: demoCommandGoRuns,
      title: 'Go to Runs',
      screen: demoScreenRuns,
      shortcut: KeyChord.ctrl.r,
    ),
    _goCommand(
      id: demoCommandGoTree,
      title: 'Go to Tree',
      screen: demoScreenTree,
      shortcut: KeyChord.ctrl.y,
    ),
    _goCommand(
      id: demoCommandGoPayload,
      title: 'Go to Payload',
      screen: demoScreenPayload,
      shortcut: KeyChord.ctrl.j,
    ),
    _goCommand(
      id: demoCommandGoChanges,
      title: 'Go to Changes',
      screen: demoScreenChanges,
      shortcut: KeyChord.ctrl.g,
    ),
    _goCommand(
      id: demoCommandGoSource,
      title: 'Go to Source',
      screen: demoScreenSource,
      shortcut: KeyChord.ctrl.s,
    ),
    _goCommand(
      id: demoCommandGoDocs,
      title: 'Go to Docs',
      screen: demoScreenDocs,
      shortcut: KeyChord.ctrl.h,
    ),
    _goCommand(
      id: demoCommandGoTranscript,
      title: 'Go to Transcript',
      screen: demoScreenTranscript,
      shortcut: KeyChord.ctrl.t,
    ),
    _goCommand(
      id: demoCommandGoProcess,
      title: 'Go to Process',
      screen: demoScreenProcess,
      shortcut: KeyChord.ctrl.p,
    ),
    _goCommand(
      id: demoCommandGoDiagnostics,
      title: 'Go to Diagnostics',
      screen: demoScreenDiagnostics,
      shortcut: KeyChord.ctrl.d,
    ),
    AppCommand(
      id: demoCommandStartTask,
      title: 'Start Fake Task',
      description: 'Start deterministic worker progress',
      category: 'Task',
      enabled: (_) => !_taskRunning,
      semanticAction: SemanticAction.start,
      run: (_) {
        _startTask();
      },
    ),
    AppCommand(
      id: demoCommandCancelTask,
      title: 'Cancel Active Task',
      description: 'Stop the fake worker if it is active',
      category: 'Task',
      enabled: (_) => _taskRunning,
      semanticAction: SemanticAction.cancel,
      run: (_) {
        _cancelTask();
      },
    ),
    AppCommand(
      id: demoCommandRequestApproval,
      title: 'Request Deploy Approval',
      description: 'Open a protocol-neutral approval prompt',
      category: 'Approvals',
      semanticAction: SemanticAction.open,
      run: _requestApproval,
    ),
    AppCommand(
      id: demoCommandCaptureDebug,
      title: 'Capture Debug Snapshot',
      description: 'Record a small debug snapshot counter',
      category: 'Diagnostics',
      semanticAction: SemanticAction.captureDebug,
      run: (_) {
        _captureDebug();
      },
    ),
    ..._activeScreenCommands(),
  ];

  Iterable<AppCommand> _activeScreenCommands() sync* {
    for (final screen in _screens) {
      for (final command in screen.commands) {
        yield _activeScreenCommand(screen.id, command);
      }
    }
  }

  AppCommand _activeScreenCommand(String screenId, AppCommand command) {
    return AppCommand(
      id: command.id,
      title: command.title,
      description: command.description,
      category: command.category,
      shortcuts: command.shortcuts,
      semanticAction: command.semanticAction,
      visible: (context) {
        return _navigation.activeScreenId == screenId &&
            command.visible(context);
      },
      enabled: (context) {
        return _navigation.activeScreenId == screenId &&
            command.enabled(context);
      },
      run: command.run,
    );
  }

  AppCommand _goCommand({
    required CommandId id,
    required String title,
    required String screen,
    required KeyChord shortcut,
  }) {
    return AppCommand(
      id: id,
      title: title,
      category: 'Navigation',
      shortcuts: [shortcut],
      semanticAction: SemanticAction.navigate,
      run: (_) {
        _activateScreen(screen);
      },
    );
  }

  bool _activateScreen(String screenId) {
    if (!_screens.any((screen) => screen.id == screenId)) return false;
    final previous = _navigation.activeScreenId;
    _navigation.activate(screenId);
    if (previous != screenId && mounted) setState(() {});
    return true;
  }

  _DemoScreenSpec get _activeScreen {
    return _screens.firstWhere(
      (screen) => screen.id == _navigation.activeScreenId,
      orElse: () => _screens.first,
    );
  }

  List<StatusItem> _status(FleuryAppController _) {
    final screen = _activeScreen.title;
    final taskStatus = _task.status;
    return [
      StatusItem.text('Screen', id: 'screen', value: screen),
      switch (taskStatus) {
        TaskStatus.running => StatusItem.warning(
          'Task',
          id: 'task',
          value: 'running $_taskProgress%',
          action: demoCommandCancelTask,
        ),
        TaskStatus.failed => StatusItem.warning(
          'Task',
          id: 'task',
          value: 'failed',
          action: demoCommandStartTask,
        ),
        TaskStatus.canceled => StatusItem.text(
          'Task',
          id: 'task',
          value: 'canceled',
          action: demoCommandStartTask,
        ),
        TaskStatus.succeeded => StatusItem.success(
          'Task',
          id: 'task',
          value: 'done',
          action: demoCommandStartTask,
        ),
        TaskStatus.idle => StatusItem.success(
          'Task',
          id: 'task',
          value: 'idle',
        ),
      },
      switch (_process.status) {
        TaskStatus.running => StatusItem.warning(
          'Process',
          id: 'process',
          value: 'running',
          action: demoCommandGoProcess,
        ),
        TaskStatus.failed => StatusItem.warning(
          'Process',
          id: 'process',
          value: 'failed',
          action: demoCommandGoProcess,
        ),
        TaskStatus.canceled => StatusItem.text(
          'Process',
          id: 'process',
          value: 'canceled',
          action: demoCommandGoProcess,
        ),
        TaskStatus.succeeded => StatusItem.success(
          'Process',
          id: 'process',
          value: 'done',
          action: demoCommandGoProcess,
        ),
        TaskStatus.idle => StatusItem.text(
          'Process',
          id: 'process',
          value: 'idle',
          action: demoCommandGoProcess,
        ),
      },
    ];
  }

  void _openPalette(CommandContext context) {
    final buildContext = context.buildContext;
    if (buildContext == null) return;
    unawaited(CommandPalette.open(buildContext));
  }

  void _startTask() {
    if (_task.isRunning) return;
    final progress = (_taskProgress == 0 ? 15 : _taskProgress + 20).clamp(
      0,
      95,
    );
    final message = 'fake task advanced to $progress%';
    final completer = Completer<void>();
    _fakeTaskCompleter = completer;

    _mutate(() {
      _append('worker', message);
    });

    unawaited(
      _task.start((context) async {
        context.reportProgress(
          current: progress,
          total: 100,
          label: '$progress%',
        );
        context.write(message, source: 'worker');
        await completer.future;
        context.checkCancellation();
      }),
    );
  }

  void _cancelTask() {
    if (!_task.isRunning) return;
    final progress = _taskProgress;
    _task.cancel();
    _completeFakeTask();
    _mutate(() {
      _append('worker', 'fake task canceled at $progress%');
    });
  }

  void _completeFakeTask() {
    final completer = _fakeTaskCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _fakeTaskCompleter = null;
  }

  void _captureDebug() {
    _mutate(() {
      _debugCaptures += 1;
      _append('debug', 'captured semantic snapshot #$_debugCaptures');
    });
  }

  void _recordDiagnostic() {
    _mutate(() {
      _append('diagnose', 'terminal profile: ansi-256, mouse pending');
    });
  }

  void _scheduleGlobalSearch() {
    final query = _globalSearchQuery.text;
    if (query.trim().isEmpty) {
      _globalSearchTask.reset();
      _mutate(() {
        _globalSearchResolvedQuery = '';
        _globalSearchResults = const <SearchResult>[];
      });
      return;
    }

    unawaited(
      _globalSearchTask
          .schedule((context) {
            final corpus = _searchDataSource.buildCorpus();
            final searchIndex = SearchResultIndex(corpus);
            final order = searchIndex.order(query: query);
            final results = <SearchResult>[
              for (final index in order) corpus[index],
            ];
            context.reportProgress(
              current: results.length,
              total: corpus.length,
              label: '${results.length} matches',
            );
            context.write(
              'query "$query" matched ${results.length} of ${corpus.length}',
              source: 'search',
            );
            return List<SearchResult>.unmodifiable(results);
          })
          .then((result) {
            if (!mounted ||
                !result.succeeded ||
                _globalSearchQuery.text != query) {
              return;
            }
            _mutate(() {
              _globalSearchResolvedQuery = query;
              _globalSearchResults = result.value ?? const <SearchResult>[];
            });
          }),
    );
  }

  void _activateSearchResult(SearchResult result) {
    final id = result.id?.toString() ?? result.title;
    _mutate(() {
      _append('search', 'activated $id');
    });
  }

  void _buildDemoLogIndex() {
    if (_logIndexTask.isRunning) return;
    _mutate(() {
      _indexedLogSearchIndex = null;
    });
    unawaited(
      _logIndexTask
          .start((context) async {
            final index = await LogRegionSearchIndex.buildCooperatively(
              _indexedLogs,
              context: context,
              yieldPolicy: _demoIndexYieldPolicy,
              progressLabel: 'index demo logs',
            );
            context.write(
              'indexed ${index.length} demo log rows',
              source: 'index',
            );
            return index;
          })
          .then((result) {
            if (!mounted || !result.succeeded || result.value == null) return;
            _mutate(() {
              _indexedLogSearchIndex = result.value;
              _append('index', 'built ${result.value!.length} demo log rows');
            });
          }),
    );
  }

  void _appendIndexedLogBurst() {
    if (_logIndexTask.isRunning) return;
    final start = _indexedLogs.length;
    final index =
        _indexedLogSearchIndex ?? LogRegionSearchIndex.empty(_indexedLogs);
    _mutate(() {
      for (var i = 0; i < demoIndexedLogAppendCount; i++) {
        _indexedLogs.add(_demoIndexedLogEntry(start + i));
      }
      _indexedLogSearchIndex = null;
    });
    unawaited(
      _logIndexTask
          .start((context) async {
            await index.refreshCooperatively(
              context: context,
              yieldPolicy: _demoIndexYieldPolicy,
              progressLabel: 'refresh demo logs',
            );
            context.write(
              'refreshed ${index.length} demo log rows',
              source: 'index',
            );
            return index;
          })
          .then((result) {
            if (!mounted || !result.succeeded || result.value == null) return;
            _mutate(() {
              _indexedLogSearchIndex = result.value;
              _append(
                'index',
                'refreshed ${result.value!.length} demo log rows',
              );
            });
          }),
    );
  }

  void _selectRun(RunRecord run) {
    _mutate(() {
      _append('runs', 'selected run ${run.id} ${run.status}');
    });
  }

  void _requestApproval(CommandContext context) {
    final buildContext = context.buildContext;
    if (buildContext == null) return;
    Navigator.of(buildContext).present<void>(
      ApprovalPrompt(
        request: const ApprovalRequest(
          id: 'deploy.prod',
          title: 'Approve deploy?',
          message: 'Deploy the latest demo build to production.',
          subject: 'prod',
          details: ['run RUN-1002 failed smoke', 'requires operator review'],
          severity: ApprovalSeverity.warning,
          confirmLabel: 'Approve',
          cancelLabel: 'Deny',
        ),
        onDecision: (decision) {
          Navigator.maybeOf(buildContext)?.pop();
          _recordApproval(decision);
        },
      ),
    );
  }

  void _recordApproval(ApprovalDecision decision) {
    _mutate(() {
      _append(
        'approval',
        decision == ApprovalDecision.approved
            ? 'deploy approval granted'
            : 'deploy approval denied',
      );
    });
  }

  void _submitConnection(FormSubmitResult result) {
    _mutate(() {
      if (result.valid) {
        _append(
          'connection',
          'configured ${result.values.text('project')} '
              '${result.values['environment']} ${result.values['region']} '
              'features ${result.values.listValue('features').join(',')} '
              'config ${result.values.path('configPath')} '
              '${_demoDate(result.values.dateValue('launchDate'))} '
              'retries ${result.values['retries']}',
        );
      } else {
        _append('connection', 'invalid form ${result.errors.length} errors');
      }
    });
  }

  void _selectTreeNode(TreeTableRow<String> row) {
    _mutate(() {
      _append('tree', 'selected ${row.key} ${row.node.cells['status'] ?? ''}');
    });
  }

  void _copyPayload(JsonViewCopyResult result) {
    _mutate(() {
      _append('payload', 'copied ${result.row.path}');
    });
  }

  void _copyChange(DiffViewCopyResult result) {
    _mutate(() {
      _append(
        'changes',
        'copied ${result.row.filePath ?? 'diff'} ${result.row.kind.name}',
      );
    });
  }

  void _selectPatchFile(PatchReviewFileSelectResult result) {
    _mutate(() {
      _append('patch', 'selected ${result.file.path}');
    });
  }

  void _copySource(CodeViewCopyResult result) {
    _mutate(() {
      _append(
        'source',
        'copied line ${result.line.lineNumber} ${result.line.kind.name}',
      );
    });
  }

  void _copyDocs(MarkdownViewCopyResult result) {
    _mutate(() {
      _append(
        'docs',
        'copied block ${result.block.index + 1} ${result.block.kind.name}',
      );
    });
  }

  void _submitComposer(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _mutate(() {
      _append('user', trimmed);
      _composer.text = '';
    });
  }

  void _pickFileMention(FileMentionPickResult result) {
    _mutate(() {
      if (_composer.text.trim().isNotEmpty && !_composer.text.endsWith(' ')) {
        _composer.insert(' ');
      }
      _composer.insert(result.entry.displayMention);
      _append('composer', 'mentioned ${result.entry.path}');
    });
  }

  void _selectConversation(ConversationNavigatorSelectResult result) {
    _mutate(() {
      _append('conversation', 'selected ${result.entry.displayId}');
    });
  }

  void _selectContextItem(ContextPanelSelectResult result) {
    _mutate(() {
      _append('context', 'selected ${result.item.displayId}');
    });
  }

  void _selectTraceEvent(TraceTimelineSelectResult result) {
    _mutate(() {
      _append('trace', 'selected ${result.event.displayId}');
    });
  }

  void _appendLogBurst() {
    _mutate(() {
      _logBurst += 1;
      for (var i = 1; i <= 3; i++) {
        _append('stream', 'burst $_logBurst.$i');
      }
    });
  }

  void _append(String source, String text) {
    _transcript.add(
      TranscriptEvent(
        id: _nextTranscriptEventId++,
        source: source,
        kind: 'log',
        text: text,
      ),
    );
    if (_transcript.length > 8) _transcript.removeAt(0);
  }
}

class _ConsoleShell extends StatelessWidget {
  const _ConsoleShell({
    required this.screens,
    required this.navigation,
    required this.onActivateScreen,
  });

  final List<_DemoScreenSpec> screens;
  final _DemoNavigationController navigation;
  final bool Function(String screenId) onActivateScreen;

  _DemoScreenSpec get activeScreen {
    return screens.firstWhere(
      (screen) => screen.id == navigation.activeScreenId,
      orElse: () => screens.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: navigation,
      builder: (context, _) {
        final active = activeScreen;
        return Padding(
          padding: const EdgeInsets.all(1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Fleury Demo Console',
                style: const CellStyle(bold: true, foreground: AnsiColor(14)),
              ),
              const SizedBox(height: 1),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 22,
                      child: _Sidebar(
                        screens: screens,
                        activeScreenId: active.id,
                        onActivateScreen: onActivateScreen,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: _DemoScreenSlot(
                        key: ValueKey<String>('screen:${active.id}'),
                        screen: active,
                        onActivateScreen: onActivateScreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 1),
              AppStatusBar(),
              KeyHintBar(),
            ],
          ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.screens,
    required this.activeScreenId,
    required this.onActivateScreen,
  });

  final List<_DemoScreenSpec> screens;
  final String activeScreenId;
  final bool Function(String screenId) onActivateScreen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      role: SemanticRole.navigation,
      label: 'Demo console navigation',
      state: SemanticState({
        'screenCount': screens.length,
        'activeScreenId': activeScreenId,
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Screens', style: CellStyle(bold: true)),
          const SizedBox(height: 1),
          for (final screen in screens)
            Semantics(
              role: SemanticRole.listItem,
              label: screen.title,
              selected: screen.id == activeScreenId,
              actions: const {SemanticAction.navigate},
              state: SemanticState({
                'screenId': screen.id,
                if (screen.shortTitle != null)
                  'screenShortTitle': screen.shortTitle,
              }),
              onAction: (action) {
                if (action == SemanticAction.navigate) {
                  onActivateScreen(screen.id);
                }
              },
              child: Text(
                '${screen.id == activeScreenId ? '>' : ' '} ${screen.title}',
                style: screen.id == activeScreenId
                    ? const CellStyle(foreground: AnsiColor(10), bold: true)
                    : CellStyle.empty,
              ),
            ),
          const SizedBox(height: 1),
          const Text('Ctrl+K palette', style: CellStyle(dim: true)),
        ],
      ),
    );
  }
}

class _DemoScreenSlot extends StatelessWidget {
  const _DemoScreenSlot({
    super.key,
    required this.screen,
    required this.onActivateScreen,
  });

  final _DemoScreenSpec screen;
  final bool Function(String screenId) onActivateScreen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      id: SemanticNodeId('screen:${screen.id}'),
      role: SemanticRole.screen,
      label: screen.title,
      value: screen.description,
      selected: true,
      actions: const {SemanticAction.navigate},
      state: SemanticState({
        'screenId': screen.id,
        if (screen.shortTitle != null) 'screenShortTitle': screen.shortTitle,
      }),
      onAction: (action) {
        if (action == SemanticAction.navigate) {
          onActivateScreen(screen.id);
        }
      },
      child: _DemoScreenBuilderWidget(builder: screen.builder),
    );
  }
}

class _DemoScreenBuilderWidget extends StatelessWidget {
  const _DemoScreenBuilderWidget({required this.builder});

  final _DemoScreenBuilder builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

class _OverviewScreen extends StatelessWidget {
  const _OverviewScreen({
    required this.task,
    required this.process,
    required this.processCommand,
    required this.transcript,
    required this.debugCaptures,
    required this.streaming,
    required this.contextItems,
    required this.onContextSelected,
  });

  final TaskController<void> task;
  final ProcessTaskController process;
  final ProcessTaskCommand processCommand;
  final List<TranscriptEvent> transcript;
  final int debugCaptures;
  final bool streaming;
  final List<ContextItem> contextItems;
  final void Function(ContextPanelSelectResult result) onContextSelected;

  @override
  Widget build(BuildContext context) {
    final latest = transcript.reversed.take(3).toList(growable: false);
    final progress = task.progress?.fraction ?? 0;
    final modelStatus = _demoModelStatus(task, transcript);
    final workflow = _demoWorkflowSnapshot(
      task: task,
      process: process,
      processCommand: processCommand,
      transcript: transcript,
      debugCaptures: debugCaptures,
      streaming: streaming,
      contextItems: contextItems,
      modelStatus: modelStatus,
    );
    return Semantics(
      role: SemanticRole.region,
      label: 'Demo workflow snapshot',
      state: workflow.toSemanticState(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Overview', style: CellStyle(bold: true)),
          ModelStatusBar(info: modelStatus),
          const SizedBox(height: 1),
          SizedBox(
            height: 4,
            child: ContextPanel(
              label: 'Demo context',
              items: contextItems,
              usage: modelStatus.tokenUsage,
              maxVisible: 3,
              copyOptions: const ContextPanelCopyOptions(
                clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
              ),
              onSelect: onContextSelected,
            ),
          ),
          const SizedBox(height: 1),
          TaskStatusView<void>(
            controller: task,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  task.isRunning
                      ? 'Fake task is running'
                      : 'Fake task is ${task.status.name}',
                ),
                SizedBox(width: 36, child: ProgressBar(value: progress)),
              ],
            ),
          ),
          const SizedBox(height: 1),
          _DemoTelemetry(
            progress: progress,
            transcript: transcript,
            debugCaptures: debugCaptures,
            modelStatus: modelStatus,
          ),
          Text('Debug captures: $debugCaptures'),
          const SizedBox(height: 1),
          const Text('Workflow plan', style: CellStyle(bold: true)),
          SizedBox(
            height: 4,
            child: TaskGraph(
              label: 'Demo workflow plan',
              nodes: _demoWorkflowPlan(task, debugCaptures),
            ),
          ),
          const SizedBox(height: 1),
          const Text('Recent activity', style: CellStyle(bold: true)),
          for (final event in latest)
            Text(
              '${event.source}: ${event.text}',
              style: const CellStyle(dim: true),
            ),
        ],
      ),
    );
  }
}

class _DemoTelemetry extends StatelessWidget {
  const _DemoTelemetry({
    required this.progress,
    required this.transcript,
    required this.debugCaptures,
    required this.modelStatus,
  });

  final double progress;
  final List<TranscriptEvent> transcript;
  final int debugCaptures;
  final ModelStatusInfo modelStatus;

  @override
  Widget build(BuildContext context) {
    final usage = modelStatus.tokenUsage;
    final contextPressure = usage.contextRatio ?? 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Demo telemetry', style: CellStyle(bold: true)),
        SizedBox(
          width: 36,
          child: Gauge(
            value: contextPressure,
            label: 'CTX',
            semanticLabel: 'Context pressure',
          ),
        ),
        SizedBox(
          width: 36,
          child: Sparkline(
            data: _demoTranscriptTrend(transcript),
            max: 80,
            semanticLabel: 'Transcript trend',
          ),
        ),
        SizedBox(
          width: 18,
          height: 4,
          child: BarChart(
            bars: _demoActivityBars(
              progress: progress,
              transcript: transcript,
              debugCaptures: debugCaptures,
            ),
            max: 8,
            barWidth: 2,
            gap: 1,
            showValues: true,
            semanticLabel: 'Activity mix',
          ),
        ),
      ],
    );
  }
}

List<num> _demoTranscriptTrend(List<TranscriptEvent> transcript) {
  if (transcript.isEmpty) return const <num>[0];
  return [
    for (final event in transcript.take(12)) event.text.length.clamp(0, 80),
  ];
}

List<Bar> _demoActivityBars({
  required double progress,
  required List<TranscriptEvent> transcript,
  required int debugCaptures,
}) {
  return [
    Bar('msg', transcript.length),
    Bar('wrk', (progress * 8).round()),
    Bar('dbg', debugCaptures),
  ];
}

WorkflowSnapshot _demoWorkflowSnapshot({
  required TaskController<void> task,
  required ProcessTaskController process,
  required ProcessTaskCommand processCommand,
  required List<TranscriptEvent> transcript,
  required int debugCaptures,
  required bool streaming,
  required List<ContextItem> contextItems,
  required ModelStatusInfo modelStatus,
}) {
  return WorkflowSnapshot(
    id: 'demo-console',
    title: 'Fleury Demo Console',
    messages: [
      for (final event in transcript)
        MessageEntry(
          id: event.id,
          role: MessageRole.log,
          status: _messageStatusForTranscriptEvent(event),
          author: event.source,
          text: event.text,
          metadata: {'eventKind': event.kind},
        ),
    ],
    toolCalls: [_toolCallForProcess(process, processCommand)],
    tasks: _demoWorkflowPlan(task, debugCaptures),
    modelStatus: modelStatus,
    contextItems: contextItems,
    fileMentions: _demoFileMentions,
    conversations: _demoConversations(
      task: task,
      process: process,
      transcript: transcript,
      streaming: streaming,
    ),
    traceEvents: _demoTraceEvents(
      task: task,
      process: process,
      transcript: transcript,
      debugCaptures: debugCaptures,
      streaming: streaming,
    ),
    patchFiles: _demoPatchFiles,
    logEntries: const <LogEntry>[],
    metadata: {'debugCaptures': debugCaptures, 'streaming': streaming},
  );
}

List<TaskGraphNode> _demoWorkflowPlan(
  TaskController<void> task,
  int debugCaptures,
) {
  return [
    const TaskGraphNode(
      id: 'setup',
      title: 'Open demo console',
      status: TaskGraphStatus.succeeded,
    ),
    TaskGraphNode(
      id: 'worker',
      title: 'Run fake worker',
      description: 'Exercise task progress and cancellation semantics',
      status: _taskGraphStatusForTask(task.status),
      dependsOn: const ['setup'],
      progressCurrent: task.progress?.current,
      progressTotal: task.progress?.total,
    ),
    TaskGraphNode(
      id: 'diagnostics',
      title: 'Capture diagnostics',
      status: debugCaptures > 0
          ? TaskGraphStatus.succeeded
          : TaskGraphStatus.pending,
      dependsOn: const ['worker'],
    ),
    const TaskGraphNode(
      id: 'transcript',
      title: 'Review transcript',
      status: TaskGraphStatus.pending,
      dependsOn: ['diagnostics'],
    ),
  ];
}

TaskGraphStatus _taskGraphStatusForTask(TaskStatus status) {
  return switch (status) {
    TaskStatus.idle => TaskGraphStatus.pending,
    TaskStatus.running => TaskGraphStatus.running,
    TaskStatus.succeeded => TaskGraphStatus.succeeded,
    TaskStatus.failed => TaskGraphStatus.failed,
    TaskStatus.canceled => TaskGraphStatus.cancelled,
  };
}

ModelStatusInfo _demoModelStatus(
  TaskController<void> task,
  List<TranscriptEvent> transcript,
) {
  final transcriptTokens = transcript.fold<int>(
    0,
    (total, event) => total + event.text.length,
  );
  final taskProgress = (task.progress?.current ?? 0).round();
  return ModelStatusInfo(
    model: 'fleury-prover',
    provider: 'local',
    status: _modelStatusForTask(task.status),
    mode: 'demo',
    detail: task.isRunning ? 'working' : 'ready',
    latency: const Duration(milliseconds: 42),
    queueDepth: task.isRunning ? 1 : 0,
    tokenUsage: TokenUsage(
      input: 1800 + transcriptTokens,
      output: 320 + taskProgress,
      contextUsed: 2400 + transcriptTokens + taskProgress,
      contextLimit: 128000,
    ),
  );
}

List<ContextItem> _demoContextItems({
  required TaskController<void> task,
  required List<TranscriptEvent> transcript,
  required int debugCaptures,
}) {
  final transcriptTokens = transcript.fold<int>(
    0,
    (total, event) => total + event.text.length,
  );
  return [
    const ContextItem(
      id: 'ctx.demo-console',
      label: 'Demo console source',
      detail: 'App shell, screens, commands, and demo fixtures',
      kind: ContextItemKind.file,
      priority: ContextItemPriority.high,
      tokenCount: 1200,
      source: 'packages/fleury_example_console/lib/fleury_example_console.dart',
      pinned: true,
      metadata: {'screenId': 'source'},
    ),
    const ContextItem(
      id: 'ctx.demo-scenario',
      label: 'Demo-app scenario',
      detail: 'Scenario that constrains Fleury launch implementation',
      kind: ContextItemKind.note,
      priority: ContextItemPriority.high,
      tokenCount: 900,
      source: 'docs/implementation/demo-app-scenario.md',
      pinned: true,
      metadata: {'screenId': 'docs'},
    ),
    ContextItem(
      id: 'ctx.transcript-tail',
      label: 'Transcript tail',
      detail: 'Recent transcript events available to the local demo model',
      kind: ContextItemKind.message,
      priority: transcript.length > 4
          ? ContextItemPriority.normal
          : ContextItemPriority.low,
      tokenCount: transcriptTokens,
      source: 'transcript',
      metadata: {'screenId': demoScreenTranscript},
    ),
    ContextItem(
      id: 'ctx.worker-state',
      label: 'Worker state',
      detail:
          'Fake task ${task.status.name}, events ${task.events.length}, '
          'debug captures $debugCaptures',
      kind: ContextItemKind.tool,
      priority: task.isRunning
          ? ContextItemPriority.critical
          : ContextItemPriority.normal,
      tokenCount: 240 + task.events.length * 24,
      source: 'task.fake-task',
      metadata: {'taskId': 'fake-task'},
    ),
  ];
}

ModelRuntimeStatus _modelStatusForTask(TaskStatus status) {
  return switch (status) {
    TaskStatus.idle => ModelRuntimeStatus.ready,
    TaskStatus.running => ModelRuntimeStatus.streaming,
    TaskStatus.succeeded => ModelRuntimeStatus.ready,
    TaskStatus.failed => ModelRuntimeStatus.error,
    TaskStatus.canceled => ModelRuntimeStatus.degraded,
  };
}

List<ConversationEntry> _demoConversations({
  required TaskController<void> task,
  required ProcessTaskController process,
  required List<TranscriptEvent> transcript,
  required bool streaming,
}) {
  final latest = transcript.isEmpty ? null : transcript.last.text;
  return [
    ConversationEntry(
      id: 'thread.transcript',
      title: 'Transcript thread',
      subtitle: 'Composer and streamed demo events',
      status: streaming ? ConversationStatus.active : ConversationStatus.idle,
      latestMessage: latest,
      author: transcript.isEmpty ? null : transcript.last.source,
      messageCount: transcript.length,
      pinned: true,
      metadata: {'screenId': demoScreenTranscript},
    ),
    ConversationEntry(
      id: 'thread.worker',
      title: 'Worker task',
      subtitle: 'Fake worker progress and cancellation',
      status: _conversationStatusForTask(task.status),
      latestMessage: 'Fake task ${task.status.name}',
      unreadCount: task.isRunning ? 1 : 0,
      messageCount: task.events.length,
      metadata: {'screenId': demoScreenOverview, 'taskId': 'fake-task'},
    ),
    ConversationEntry(
      id: 'thread.process',
      title: 'Process handoff',
      subtitle: 'Native command output and terminal handoff',
      status: _conversationStatusForTask(process.status),
      latestMessage: 'Process ${process.status.name}',
      unreadCount: process.status == TaskStatus.failed ? 1 : 0,
      messageCount: process.events.length,
      metadata: {'screenId': demoScreenProcess, 'taskId': 'dart-version'},
    ),
    const ConversationEntry(
      id: 'thread.diagnostics',
      title: 'Diagnostics review',
      subtitle: 'Terminal capability and debug-capture evidence',
      status: ConversationStatus.waiting,
      latestMessage: 'Capture a snapshot or run diagnose',
      unreadCount: 1,
      messageCount: 2,
      metadata: {'screenId': 'diagnostics'},
    ),
  ];
}

ConversationStatus _conversationStatusForTask(TaskStatus status) {
  return switch (status) {
    TaskStatus.idle => ConversationStatus.idle,
    TaskStatus.running => ConversationStatus.streaming,
    TaskStatus.succeeded => ConversationStatus.complete,
    TaskStatus.failed => ConversationStatus.failed,
    TaskStatus.canceled => ConversationStatus.idle,
  };
}

List<TraceTimelineEntry> _demoTraceEvents({
  required TaskController<void> task,
  required ProcessTaskController process,
  required List<TranscriptEvent> transcript,
  required int debugCaptures,
  required bool streaming,
}) {
  final lastTranscript = transcript.isEmpty ? null : transcript.last;
  return [
    const TraceTimelineEntry(
      id: 'trace.boot',
      label: 'Boot demo console',
      detail: 'App shell, screens, commands, and demo fixtures mounted',
      kind: TraceTimelineKind.app,
      status: TraceTimelineStatus.succeeded,
      source: 'app',
      duration: Duration(milliseconds: 12),
      metadata: {'screenId': 'overview'},
    ),
    TraceTimelineEntry(
      id: 'trace.fake-task',
      label: 'Fake task',
      detail:
          'status ${task.status.name}, events ${task.events.length}, '
          'outputs ${task.output.length}',
      kind: TraceTimelineKind.task,
      status: _traceStatusForTask(task.status),
      source: 'fake-task',
      duration: Duration(milliseconds: 40 + task.events.length * 8),
      metadata: {'taskId': 'fake-task', 'screenId': demoScreenOverview},
    ),
    ...traceTimelineEntriesForTaskEvents(
      task.events,
      taskId: 'fake-task',
      taskLabel: 'Fake task',
      source: 'fake-task',
      maxEvents: 3,
    ),
    TraceTimelineEntry(
      id: 'trace.process',
      label: 'Dart version process',
      detail:
          'status ${process.status.name}, events ${process.events.length}, '
          'outputs ${process.output.length}',
      kind: TraceTimelineKind.process,
      status: _traceStatusForTask(process.status),
      source: 'dart-version',
      duration: Duration(milliseconds: 60 + process.events.length * 10),
      metadata: {'taskId': 'dart-version', 'screenId': demoScreenProcess},
    ),
    ...traceTimelineEntriesForTaskEvents(
      process.events,
      taskId: 'dart-version',
      taskLabel: 'Dart version process',
      kind: TraceTimelineKind.process,
      source: 'dart-version',
      maxEvents: 3,
    ),
    TraceTimelineEntry(
      id: 'trace.diagnostics',
      label: 'Diagnostics capture',
      detail: debugCaptures == 0
          ? 'No debug capture yet'
          : 'captured semantic snapshot #$debugCaptures',
      kind: TraceTimelineKind.diagnostic,
      status: debugCaptures == 0
          ? TraceTimelineStatus.queued
          : TraceTimelineStatus.succeeded,
      source: 'diagnostics',
      duration: debugCaptures == 0
          ? null
          : Duration(milliseconds: 18 + debugCaptures * 4),
      metadata: {'screenId': demoScreenDiagnostics},
    ),
    TraceTimelineEntry(
      id: 'trace.transcript',
      label: 'Transcript stream',
      detail: lastTranscript == null
          ? 'No transcript events'
          : '${lastTranscript.source}: ${lastTranscript.text}',
      kind: TraceTimelineKind.output,
      status: streaming
          ? TraceTimelineStatus.running
          : TraceTimelineStatus.cancelled,
      source: 'transcript',
      duration: Duration(milliseconds: transcript.length * 6),
      metadata: {'screenId': demoScreenTranscript},
    ),
  ];
}

TraceTimelineStatus _traceStatusForTask(TaskStatus status) {
  return switch (status) {
    TaskStatus.idle => TraceTimelineStatus.queued,
    TaskStatus.running => TraceTimelineStatus.running,
    TaskStatus.succeeded => TraceTimelineStatus.succeeded,
    TaskStatus.failed => TraceTimelineStatus.failed,
    TaskStatus.canceled => TraceTimelineStatus.cancelled,
  };
}

const _demoFileMentions = [
  FileMentionEntry(
    path: 'packages/fleury_example_console/lib/fleury_example_console.dart',
    label: 'Demo console app',
    detail: 'App shell, screens, commands, and demo fixtures',
    language: 'dart',
    line: 1,
    mentionText: '@demo-console',
  ),
  FileMentionEntry(
    path: 'docs/implementation/demo-app-scenario.md',
    label: 'Demo-app scenario',
    detail: 'Implementation scenario that constrains Fleury launch work',
    language: 'markdown',
    mentionText: '@demo-scenario',
  ),
  FileMentionEntry(
    path: 'packages/fleury_widgets/lib/src/message_list.dart',
    label: 'MessageList widget',
    detail: 'Protocol-neutral transcript surface',
    language: 'dart',
    mentionText: '@message-list',
  ),
  FileMentionEntry(
    path: 'packages/fleury_widgets/lib/src/file_browser.dart',
    label: 'FileBrowser widget',
    detail: 'Filesystem navigation and path copy surface',
    language: 'dart',
    mentionText: '@file-browser',
  ),
];

final _connectionFormDefinition = FormDefinition(
  title: 'Connection setup',
  submitLabel: 'Connect',
  fields: [
    FormFieldSpec.text(
      id: 'project',
      label: 'Project',
      placeholder: 'my-project',
      required: true,
      asyncValidator: _validateConnectionProject,
    ),
    FormFieldSpec.select(
      id: 'environment',
      label: 'Environment',
      initialValue: 'dev',
      required: true,
      options: const [
        FormOption(value: 'dev', label: 'Development'),
        FormOption(value: 'prod', label: 'Production'),
      ],
    ),
    FormFieldSpec.select(
      id: 'region',
      label: 'Region',
      initialValue: 'us-east-1',
      required: true,
      options: const [
        FormOption(value: 'us-east-1', label: 'US East'),
        FormOption(value: 'eu-west-1', label: 'EU West'),
      ],
    ),
    FormFieldSpec.multiSelect(
      id: 'features',
      label: 'Features',
      initialValues: const ['logs', 'metrics'],
      required: true,
      minSelected: 1,
      maxSelected: 3,
      options: const [
        FormOption(value: 'logs', label: 'Logs'),
        FormOption(value: 'metrics', label: 'Metrics'),
        FormOption(value: 'traces', label: 'Traces'),
        FormOption(value: 'deploy', label: 'Deploy', enabled: false),
      ],
    ),
    FormFieldSpec.path(
      id: 'configPath',
      label: 'Config path',
      initialValue: 'config/demo.yaml',
      placeholder: 'config/demo.yaml',
      required: true,
      pathKind: FormPathKind.file,
      mustExist: false,
      allowRelative: true,
    ),
    FormFieldSpec.number(
      id: 'retries',
      label: 'Retry limit',
      initialValue: 3,
      min: 0,
      max: 10,
      allowNegative: false,
      required: true,
    ),
    FormFieldSpec.date(
      id: 'launchDate',
      label: 'Launch date',
      initialValue: DateTime(2026, 1, 15),
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime(2026, 12, 31),
      weekStartsOn: CalendarWeekStart.monday,
      required: true,
    ),
    FormFieldSpec.secret(
      id: 'apiKey',
      label: 'API key',
      placeholder: 'token',
      required: true,
    ),
    FormFieldSpec.checkbox(
      id: 'confirm',
      label: 'I understand this changes remote state',
      required: true,
    ),
  ],
);

const _connectionWizardSteps = [
  FormWizardStep(
    id: 'connection-basics',
    title: 'Basics',
    fieldIds: ['project', 'environment', 'region'],
  ),
  FormWizardStep(
    id: 'connection-runtime',
    title: 'Runtime',
    fieldIds: ['features', 'configPath', 'retries', 'launchDate'],
  ),
  FormWizardStep(
    id: 'connection-secret',
    title: 'Secret',
    fieldIds: ['apiKey', 'confirm'],
  ),
];

Future<String?> _validateConnectionProject(
  Object? value,
  FormValues values,
) async {
  await Future<void>.delayed(Duration.zero);
  final project = value?.toString().trim().toLowerCase() ?? '';
  if (project == 'reserved') return 'Project is reserved.';
  return null;
}

String _demoDate(DateTime? value) {
  if (value == null) return 'no-date';
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

class _ConnectionScreen extends StatelessWidget {
  const _ConnectionScreen({required this.controller, required this.onSubmit});

  final FormController controller;
  final void Function(FormSubmitResult result) onSubmit;

  @override
  Widget build(BuildContext context) {
    return FormWizard(
      definition: _connectionFormDefinition,
      steps: _connectionWizardSteps,
      controller: controller,
      onSubmit: onSubmit,
    );
  }
}

class _SearchScreen extends StatelessWidget {
  const _SearchScreen({
    required this.query,
    required this.queryFocus,
    required this.resultsFocus,
    required this.list,
    required this.task,
    required this.resolvedQuery,
    required this.results,
    required this.onActivateScreen,
    required this.onActivate,
  });

  final TextEditingController query;
  final FocusNode queryFocus;
  final FocusNode resultsFocus;
  final ListController list;
  final DebouncedTaskController<List<SearchResult>> task;
  final String resolvedQuery;
  final List<SearchResult> results;
  final bool Function(String screenId) onActivateScreen;
  final void Function(SearchResult result) onActivate;

  @override
  Widget build(BuildContext context) {
    final pending = task.isPending;
    final status = pending ? 'pending' : task.status.name;
    final summary = resolvedQuery.trim().isEmpty
        ? 'Search: $status'
        : 'Search: $status ${results.length} results for "$resolvedQuery"';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Global Search', style: CellStyle(bold: true)),
        TaskStatusView<List<SearchResult>>(
          controller: task.taskController,
          child: Text(summary),
        ),
        const SizedBox(height: 1),
        Expanded(
          child: SearchPanel(
            label: 'Global search',
            placeholder: 'Search screens, runs, docs, and transcript',
            queryController: query,
            queryFocusNode: queryFocus,
            resultsFocusNode: resultsFocus,
            controller: list,
            results: results,
            autofocus: true,
            onActivate: (result, _) {
              final screenId = result.metadata['screenId'];
              if (screenId is String) {
                onActivateScreen(screenId);
              }
              onActivate(result);
            },
          ),
        ),
      ],
    );
  }
}

class _IndexedLogsScreen extends StatelessWidget {
  const _IndexedLogsScreen({
    required this.entries,
    required this.searchIndex,
    required this.filter,
    required this.filterFocus,
    required this.logFocus,
    required this.controller,
    required this.task,
  });

  final List<LogEntry> entries;
  final LogRegionSearchIndex? searchIndex;
  final TextEditingController filter;
  final FocusNode filterFocus;
  final FocusNode logFocus;
  final LogRegionController controller;
  final TaskController<LogRegionSearchIndex> task;

  @override
  Widget build(BuildContext context) {
    final query = filter.text.trim();
    final effectiveIndex = task.isRunning ? null : searchIndex;
    final indexedCount = effectiveIndex?.length ?? 0;
    final summary =
        'Rows: ${entries.length}  Indexed: $indexedCount  '
        'Task: ${task.status.name}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Indexed Logs', style: CellStyle(bold: true)),
        TaskStatusView<LogRegionSearchIndex>(
          controller: task,
          child: Text(summary),
        ),
        const SizedBox(height: 1),
        TextInput(
          controller: filter,
          focusNode: filterFocus,
          autofocus: true,
          placeholder: 'Filter indexed logs',
        ),
        const SizedBox(height: 1),
        Expanded(
          child: LogRegion(
            label: 'Indexed demo logs',
            entries: entries,
            controller: controller,
            focusNode: logFocus,
            showPrefix: true,
            searchIndex: effectiveIndex,
            filter: query.isEmpty
                ? null
                : LogRegionFilterDescriptor(query: query),
            copyOptions: const LogRegionCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
          ),
        ),
      ],
    );
  }
}

List<LogEntry> _buildDemoIndexedLogs(int count) {
  return List<LogEntry>.generate(count, _demoIndexedLogEntry, growable: true);
}

LogEntry _demoIndexedLogEntry(int row) {
  const targets = [
    'target:payment',
    'target:renderer',
    'target:agent',
    'target:terminal',
  ];
  const sources = ['worker', 'indexer', 'runtime', 'agent'];
  const severities = [
    LogSeverity.info,
    LogSeverity.debug,
    LogSeverity.warning,
    LogSeverity.success,
  ];
  final target = targets[row % targets.length];
  final source = sources[(row ~/ 3) % sources.length];
  final severity = severities[row % severities.length];
  final id = 'IDX-${1000 + row}';
  final unsafe = row % 53 == 0;
  return LogEntry(
    id: id,
    severity: unsafe ? LogSeverity.error : severity,
    source: source,
    message:
        '$id $target shard:${row % 12} '
        '${unsafe ? 'unsafe\x1b]52;c;secret-$row\x07 payload' : 'cooperative index row'}',
    metadata: {
      'fixtureRow': row,
      'target': target,
      'unsafeFixture': unsafe,
      'screenId': demoScreenIndex,
    },
  );
}

class _RunsScreen extends StatelessWidget {
  const _RunsScreen({
    required this.filter,
    required this.filterFocus,
    required this.tableFocus,
    required this.table,
    required this.runs,
    required this.onSelect,
  });

  final TextEditingController filter;
  final FocusNode filterFocus;
  final FocusNode tableFocus;
  final DataTableController table;
  final List<RunRecord> runs;
  final void Function(RunRecord run) onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Runs', style: CellStyle(bold: true)),
        TextInput(
          controller: filter,
          focusNode: filterFocus,
          autofocus: true,
          placeholder: 'Filter runs',
        ),
        const SizedBox(height: 1),
        Expanded(
          child: ListenableBuilder(
            listenable: filter,
            builder: (context, _) {
              final query = filter.text.trim();
              final sourceCell = (int row, String columnId) =>
                  _runCell(runs[row], columnId);
              final rowOrder = buildDataTableRowOrder(
                rowCount: runs.length,
                columns: _runTableColumns,
                cellBuilder: sourceCell,
                filter: query.isEmpty
                    ? null
                    : DataTableFilterDescriptor(query: query),
              );
              return DataTable(
                rowCount: rowOrder.length,
                columns: _runTableColumns,
                rowKeyBuilder: (row) => runs[rowOrder[row]].id,
                cellBuilder: (row, columnId) =>
                    _runCell(runs[rowOrder[row]], columnId),
                controller: table,
                focusNode: tableFocus,
                filterText: query.isEmpty ? null : query,
                onSelect: (row) {
                  if (row >= 0 && row < rowOrder.length) {
                    onSelect(runs[rowOrder[row]]);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

const _runTableColumns = [
  DataTableColumn(id: 'id', title: 'ID', width: FixedColumnWidth(8)),
  DataTableColumn(id: 'status', title: 'Status', width: FixedColumnWidth(8)),
  DataTableColumn(id: 'title', title: 'Title', width: FlexColumnWidth()),
  DataTableColumn(id: 'owner', title: 'Owner', width: FixedColumnWidth(6)),
  DataTableColumn(
    id: 'progress',
    title: 'Progress',
    width: FixedColumnWidth(8),
  ),
];

String _runCell(RunRecord run, String columnId) {
  return switch (columnId) {
    'id' => run.id,
    'status' => run.status,
    'title' => run.title,
    'owner' => run.owner,
    'progress' => '${run.progress}%',
    _ => '',
  };
}

List<SearchResult> _globalSearchCorpus({
  required List<RunRecord> runs,
  required List<TranscriptEvent> transcript,
}) {
  final results = <SearchResult>[
    _screenSearchResult(
      screen: demoScreenOverview,
      title: 'Overview',
      subtitle: 'Task progress and recent activity',
      detail: 'summary fake worker status transcript debug captures',
    ),
    _screenSearchResult(
      screen: demoScreenSearch,
      title: 'Global Search',
      subtitle: 'Debounced search across app surfaces',
      detail: 'typeahead DebouncedTaskController SearchPanel results',
    ),
    _screenSearchResult(
      screen: demoScreenIndex,
      title: 'Indexed Logs',
      subtitle: 'Cooperative retained-log indexing',
      detail: 'TaskYieldPolicy LogRegionSearchIndex progress cancellation',
    ),
    _screenSearchResult(
      screen: demoScreenConnection,
      title: 'Connection',
      subtitle: 'Shared form definition',
      detail: 'project environment region API key prompt fallback',
    ),
    _screenSearchResult(
      screen: demoScreenRuns,
      title: 'Runs',
      subtitle: 'Dense run records',
      detail: 'DataTable filtering selection copy',
    ),
    _screenSearchResult(
      screen: demoScreenTree,
      title: 'Tree',
      subtitle: 'Framework component hierarchy',
      detail: 'TreeTable semantic graph app kernel widgets',
    ),
    _screenSearchResult(
      screen: demoScreenPayload,
      title: 'Payload',
      subtitle: 'Structured JSON payload',
      detail: 'JsonView JSON pointer parse errors safe copy',
    ),
    _screenSearchResult(
      screen: demoScreenChanges,
      title: 'Changes',
      subtitle: 'Unified diff review',
      detail: 'DiffView hunk additions deletions safe copy',
    ),
    _screenSearchResult(
      screen: demoScreenSource,
      title: 'Source',
      subtitle: 'Source-code fixture',
      detail: 'CodeView line numbers source semantics',
    ),
    _screenSearchResult(
      screen: demoScreenDocs,
      title: 'Docs',
      subtitle: 'Markdown launch notes',
      detail: _demoMarkdown,
    ),
    _screenSearchResult(
      screen: demoScreenTranscript,
      title: 'Transcript',
      subtitle: 'Log stream and composer',
      detail: 'LogRegion tailing scrollback composer copy',
    ),
    _screenSearchResult(
      screen: demoScreenProcess,
      title: 'Process',
      subtitle: 'Native process command',
      detail: 'ProcessPanel subprocess output cancellation terminal handoff',
    ),
    _screenSearchResult(
      screen: demoScreenDiagnostics,
      title: 'Diagnostics',
      subtitle: 'Terminal capabilities',
      detail: 'capability policy probe debug capture terminal matrix',
    ),
    for (final run in runs)
      SearchResult(
        id: 'run.${run.id}',
        title: run.title,
        subtitle: '${run.id} ${run.status} ${run.owner} ${run.progress}%',
        category: 'Run',
        source: 'runs',
        detail:
            'duration ${run.duration} warnings ${run.warnings} owner ${run.owner}',
        metadata: {'screenId': demoScreenRuns, 'runId': run.id},
      ),
    ..._treeSearchResults(_frameworkTreeNodes),
    SearchResult(
      id: 'payload.demo-json',
      title: 'Demo JSON payload',
      subtitle: 'capabilities semanticGraph forms jsonView',
      category: 'Payload',
      source: 'payload',
      detail: 'structured app state and safe terminal-control output',
      metadata: {'screenId': demoScreenPayload},
    ),
    SearchResult(
      id: 'changes.framework-diff',
      title: 'Framework changes diff',
      subtitle: 'reactive mode addition',
      category: 'Diff',
      source: 'changes',
      detail: 'unified diff hunk addition deletion copy',
      metadata: {'screenId': demoScreenChanges},
    ),
    SearchResult(
      id: 'source.launch-shell',
      title: 'LaunchShell source',
      subtitle: 'Dart source fixture',
      category: 'Source',
      source: 'source',
      detail: 'CodeView source inspection line copy',
      metadata: {'screenId': demoScreenSource},
    ),
    SearchResult(
      id: 'docs.launch-notes',
      title: 'Fleury Launch Notes',
      subtitle: 'Reactive TUI docs fixture',
      category: 'Docs',
      source: 'docs',
      detail: _demoMarkdown,
      metadata: {'screenId': demoScreenDocs},
    ),
    for (final event in transcript)
      SearchResult(
        id: 'transcript.${event.id}',
        title: event.text,
        subtitle: '${event.source} ${event.kind}',
        category: 'Transcript',
        source: event.source,
        metadata: {'screenId': demoScreenTranscript},
      ),
    for (final entry in _buildDemoIndexedLogs(12))
      SearchResult(
        id: 'indexed-log.${entry.id}',
        title: entry.id?.toString() ?? entry.message,
        subtitle: '${entry.source ?? 'log'} ${entry.severity.name}',
        category: 'Indexed Log',
        source: entry.source,
        detail: entry.message,
        metadata: {'screenId': demoScreenIndex, 'rowKey': entry.id},
      ),
  ];
  return List<SearchResult>.unmodifiable(results);
}

SearchResult _screenSearchResult({
  required String screen,
  required String title,
  required String subtitle,
  required String detail,
}) {
  return SearchResult(
    id: 'screen.$screen',
    title: title,
    subtitle: subtitle,
    category: 'Screen',
    source: 'app',
    detail: detail,
    metadata: {'screenId': screen},
  );
}

List<SearchResult> _treeSearchResults(List<TreeTableNode<String>> nodes) {
  final results = <SearchResult>[];

  void visit(TreeTableNode<String> node) {
    results.add(
      SearchResult(
        id: 'tree.${node.key}',
        title: node.label,
        subtitle:
            '${node.cells['status'] ?? 'unknown'} ${node.cells['owner'] ?? ''}',
        category: 'Component',
        source: 'tree',
        detail: node.value,
        metadata: {'screenId': demoScreenTree, 'rowKey': node.key},
      ),
    );
    for (final child in node.children) {
      visit(child);
    }
  }

  for (final node in nodes) {
    visit(node);
  }
  return results;
}

const _frameworkTreeColumns = [
  DataTableColumn(id: 'name', title: 'Component', width: FlexColumnWidth()),
  DataTableColumn(id: 'status', title: 'Status', width: FixedColumnWidth(10)),
  DataTableColumn(id: 'owner', title: 'Owner', width: FixedColumnWidth(10)),
];

const _frameworkTreeNodes = [
  TreeTableNode<String>(
    key: 'core',
    label: 'Core Framework',
    value: 'core',
    cells: {'status': 'ready', 'owner': 'runtime'},
    children: [
      TreeTableNode<String>(
        key: 'semantic-graph',
        label: 'Semantic Graph',
        value: 'semantic-graph',
        cells: {'status': 'active', 'owner': 'kernel'},
      ),
      TreeTableNode<String>(
        key: 'app-kernel',
        label: 'App Kernel',
        value: 'app-kernel',
        cells: {'status': 'active', 'owner': 'kernel'},
      ),
    ],
  ),
  TreeTableNode<String>(
    key: 'widgets',
    label: 'Production Widgets',
    value: 'widgets',
    cells: {'status': 'building', 'owner': 'widgets'},
    children: [
      TreeTableNode<String>(
        key: 'tree-table',
        label: 'TreeTable',
        value: 'tree-table',
        cells: {'status': 'v0', 'owner': 'widgets'},
      ),
      TreeTableNode<String>(
        key: 'file-browser',
        label: 'FileBrowser',
        value: 'file-browser',
        cells: {'status': 'v0', 'owner': 'widgets'},
      ),
      TreeTableNode<String>(
        key: 'search-panel',
        label: 'SearchPanel',
        value: 'search-panel',
        cells: {'status': 'v0', 'owner': 'widgets'},
      ),
    ],
  ),
];

class _TreeTableScreen extends StatelessWidget {
  const _TreeTableScreen({
    required this.controller,
    required this.focusNode,
    required this.nodes,
    required this.onSelect,
  });

  final TreeTableController controller;
  final FocusNode focusNode;
  final List<TreeTableNode<String>> nodes;
  final void Function(TreeTableRow<String> row) onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Tree', style: CellStyle(bold: true)),
        const Text('Framework components', style: CellStyle(dim: true)),
        const SizedBox(height: 1),
        TreeTable<String>(
          label: 'Framework component tree',
          roots: nodes,
          columns: _frameworkTreeColumns,
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          maxVisible: 10,
          copyOptions: const TreeTableCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onSelect: onSelect,
        ),
      ],
    );
  }
}

const _demoPayload = {
  'app': 'Fleury Demo Console',
  'activeScreen': 'payload',
  'runs': [
    {'id': 'RUN-1001', 'status': 'running', 'progress': 42},
    {'id': 'RUN-1002', 'status': 'failed', 'warnings': 3},
  ],
  'capabilities': {'semanticGraph': true, 'forms': true, 'jsonView': true},
  'unsafeOutput': 'bad\x1b]52;c;token\x07 payload',
};

class _PayloadScreen extends StatelessWidget {
  const _PayloadScreen({
    required this.controller,
    required this.focusNode,
    required this.onCopy,
  });

  final JsonViewController controller;
  final FocusNode focusNode;
  final void Function(JsonViewCopyResult result) onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Payload', style: CellStyle(bold: true)),
        const Text('Structured JSON fixture', style: CellStyle(dim: true)),
        const SizedBox(height: 1),
        Expanded(
          child: JsonView(
            label: 'Demo payload',
            value: _demoPayload,
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            initialExpandedDepth: 1,
            copyOptions: const JsonViewCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
            onCopy: onCopy,
          ),
        ),
      ],
    );
  }
}

const _demoDiff = '''
diff --git a/lib/framework.dart b/lib/framework.dart
index 111..222 100644
--- a/lib/framework.dart
+++ b/lib/framework.dart
@@ -1,4 +1,5 @@
 class FrameworkMode {
-  final mode = 'legacy';
+  final mode = 'reactive';
+  final note = 'safe\x1b]52;c;token\x07 payload';
 }
''';

final _demoPatchDocument = parseUnifiedDiff(_demoDiff);
final _demoPatchFiles = buildPatchReviewFiles(
  _demoPatchDocument,
  statusByPath: const {'lib/framework.dart': PatchReviewStatus.reviewing},
  summariesByPath: const {
    'lib/framework.dart': 'Retained framework mode update',
  },
);

class _ChangesScreen extends StatelessWidget {
  const _ChangesScreen({
    required this.reviewController,
    required this.controller,
    required this.focusNode,
    required this.onFileSelected,
    required this.onCopy,
  });

  final PatchReviewController reviewController;
  final DiffViewController controller;
  final FocusNode focusNode;
  final void Function(PatchReviewFileSelectResult result) onFileSelected;
  final void Function(DiffViewCopyResult result) onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Changes', style: CellStyle(bold: true)),
        const Text('Unified diff fixture', style: CellStyle(dim: true)),
        const SizedBox(height: 1),
        PatchReview.document(
          label: 'Framework patch review',
          patchId: 'demo.framework.patch',
          status: PatchReviewStatus.reviewing,
          document: _demoPatchDocument,
          files: _demoPatchFiles,
          controller: reviewController,
          diffController: controller,
          diffFocusNode: focusNode,
          diffAutofocus: true,
          diffHeight: 14,
          copyOptions: const PatchReviewCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          diffCopyOptions: const DiffViewCopyOptions(
            mode: DiffViewCopyMode.hunk,
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onSelectFile: onFileSelected,
          onDiffCopy: onCopy,
        ),
      ],
    );
  }
}

const _demoSource = '''
import 'package:fleury/fleury.dart';

final class LaunchShell extends StatelessWidget {
  const LaunchShell();

  @override
  Widget build(BuildContext context) {
    return const Text('safe\x1b]52;c;token\x07 source');
  }
}
''';

class _SourceScreen extends StatelessWidget {
  const _SourceScreen({
    required this.controller,
    required this.focusNode,
    required this.onCopy,
  });

  final CodeViewController controller;
  final FocusNode focusNode;
  final void Function(CodeViewCopyResult result) onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Source', style: CellStyle(bold: true)),
        const Text('Source-code fixture', style: CellStyle(dim: true)),
        const SizedBox(height: 1),
        Expanded(
          child: CodeView(
            label: 'Framework source',
            source: _demoSource,
            language: 'dart',
            filePath: 'lib/launch_shell.dart',
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            copyOptions: const CodeViewCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
            onCopy: onCopy,
          ),
        ),
      ],
    );
  }
}

const _demoMarkdown =
    '# Fleury Launch Notes\n'
    '\n'
    'Build **reactive** TUIs with [docs](https://fleury.dev).\n'
    '- Semantic graph drives tests\n'
    '- Capability policy guards output\n'
    '> unsafe safe\x1b]52;c;token\x07 payload stays inert\n'
    '```dart\n'
    "final shell = FleuryApp(title: 'Launch');\n"
    '```\n';

class _DocsScreen extends StatelessWidget {
  const _DocsScreen({
    required this.controller,
    required this.focusNode,
    required this.onCopy,
  });

  final MarkdownViewController controller;
  final FocusNode focusNode;
  final void Function(MarkdownViewCopyResult result) onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Docs', style: CellStyle(bold: true)),
        const Text('Markdown fixture', style: CellStyle(dim: true)),
        const SizedBox(height: 1),
        Expanded(
          child: MarkdownView(
            label: 'Launch docs',
            markdown: _demoMarkdown,
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            copyOptions: const MarkdownViewCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
            onCopy: onCopy,
          ),
        ),
      ],
    );
  }
}

class _TranscriptScreen extends StatelessWidget {
  const _TranscriptScreen({
    required this.transcript,
    required this.conversations,
    required this.fileMentions,
    required this.composer,
    required this.composerHistory,
    required this.composerFocus,
    required this.transcriptController,
    required this.transcriptFocus,
    required this.streaming,
    required this.onConversationSelected,
    required this.onMentionPicked,
    required this.onSubmit,
  });

  final List<TranscriptEvent> transcript;
  final List<ConversationEntry> conversations;
  final List<FileMentionEntry> fileMentions;
  final TextEditingController composer;
  final TextHistoryController composerHistory;
  final FocusNode composerFocus;
  final MessageListController transcriptController;
  final FocusNode transcriptFocus;
  final bool streaming;
  final void Function(ConversationNavigatorSelectResult result)
  onConversationSelected;
  final void Function(FileMentionPickResult result) onMentionPicked;
  final void Function(String text) onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Transcript', style: CellStyle(bold: true)),
        Text(streaming ? 'Stream: on' : 'Stream: paused'),
        const SizedBox(height: 1),
        const Text('Conversations', style: CellStyle(bold: true)),
        SizedBox(
          height: 5,
          child: ConversationNavigator(
            label: 'Demo conversations',
            conversations: conversations,
            maxVisible: 3,
            placeholder: 'Search conversations...',
            copyOptions: const ConversationNavigatorCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
            onSelect: onConversationSelected,
          ),
        ),
        Expanded(
          child: _TranscriptLog(
            events: transcript,
            controller: transcriptController,
            focusNode: transcriptFocus,
          ),
        ),
        const Text('File mentions', style: CellStyle(bold: true)),
        SizedBox(
          height: 5,
          child: FileMentionPicker(
            label: 'Composer file mentions',
            entries: fileMentions,
            maxVisible: 3,
            placeholder: 'Search files...',
            copyOptions: const FileMentionCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
            onPick: onMentionPicked,
          ),
        ),
        CompletionTextInput(
          provider: _demoComposerCompletionProvider,
          controller: composer,
          historyController: composerHistory,
          focusNode: composerFocus,
          placeholder: 'Type a note and press Enter',
          onSubmit: onSubmit,
          maxVisible: 4,
        ),
      ],
    );
  }
}

const _demoComposerSlashCompletions = [
  TextCompletionOption(
    id: 'summarize',
    label: '/summarize',
    replacement: '/summarize ',
    detail: 'Summarize the current transcript',
  ),
  TextCompletionOption(
    id: 'diagnose',
    label: '/diagnose',
    replacement: '/diagnose ',
    detail: 'Prepare a terminal diagnostic request',
  ),
  TextCompletionOption(
    id: 'run-task',
    label: '/run-task',
    replacement: '/run-task ',
    detail: 'Queue the fake demo task',
  ),
];

Iterable<TextCompletionOption> _demoComposerCompletionProvider(
  TextCompletionRequest request,
) {
  final query = request.query.toLowerCase();
  if (query.isEmpty) return const <TextCompletionOption>[];

  final mentionOptions = [
    for (final entry in _demoFileMentions)
      TextCompletionOption(
        id: entry.path,
        label: entry.displayMention,
        detail: entry.label,
      ),
  ];
  return [
    ..._demoComposerSlashCompletions,
    ...mentionOptions,
  ].where((option) => option.label.toLowerCase().startsWith(query));
}

class _TranscriptLog extends StatelessWidget {
  const _TranscriptLog({
    required this.events,
    required this.controller,
    required this.focusNode,
  });

  final List<TranscriptEvent> events;
  final MessageListController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return MessageList(
      label: 'Transcript events',
      controller: controller,
      focusNode: focusNode,
      showPrefix: false,
      messages: [
        for (final event in events)
          MessageEntry(
            id: event.id,
            role: MessageRole.log,
            status: _messageStatusForTranscriptEvent(event),
            author: event.source,
            text: '[${event.kind}] ${event.source}: ${event.text}',
            metadata: {'eventKind': event.kind},
          ),
      ],
    );
  }
}

MessageStatus _messageStatusForTranscriptEvent(TranscriptEvent event) {
  return switch (event.kind) {
    'error' => MessageStatus.failed,
    _ => MessageStatus.complete,
  };
}

class _ProcessScreen extends StatelessWidget {
  const _ProcessScreen({required this.controller, required this.runner});

  final ProcessTaskController controller;
  final ProcessCommandRunner runner;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Process', style: CellStyle(bold: true)),
            Text('Command: ${runner.command.displayName}'),
            const SizedBox(height: 1),
            ToolCallCard(
              record: _toolCallForProcess(controller, runner.command),
              copyOptions: const ToolCallCopyOptions(
                clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
              ),
              onCancel: controller.canCancel ? controller.cancel : null,
            ),
            const SizedBox(height: 1),
            Expanded(
              child: ProcessPanel(
                controller: controller,
                command: runner.command,
                label: 'Dart version',
                autofocus: true,
                copyOptions: const LogRegionCopyOptions(
                  clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

ToolCallRecord _toolCallForProcess(
  ProcessTaskController controller,
  ProcessTaskCommand command,
) {
  final latestOutput = controller.output.isEmpty
      ? null
      : controller.output.last.text;
  return ToolCallRecord(
    id: 'process.dart-version',
    name: command.executable,
    title: 'Dart version command',
    description: 'Native subprocess managed through ProcessCommandRunner.',
    status: _toolCallStatusForTask(controller.status),
    arguments: {
      'command': command.displayName,
      if (command.workingDirectory != null) 'cwd': command.workingDirectory,
    },
    output: latestOutput,
    error: controller.error?.toString(),
    progressCurrent: controller.progress?.current,
    progressTotal: controller.progress?.total,
    metadata: {'processCommandId': demoCommandRunProcess.value},
  );
}

ToolCallStatus _toolCallStatusForTask(TaskStatus status) {
  return switch (status) {
    TaskStatus.idle => ToolCallStatus.queued,
    TaskStatus.running => ToolCallStatus.running,
    TaskStatus.succeeded => ToolCallStatus.succeeded,
    TaskStatus.failed => ToolCallStatus.failed,
    TaskStatus.canceled => ToolCallStatus.cancelled,
  };
}

class _DiagnosticsScreen extends StatelessWidget {
  const _DiagnosticsScreen({
    required this.debugCaptures,
    required this.streaming,
    required this.traceEvents,
    required this.onTraceSelected,
  });

  final int debugCaptures;
  final bool streaming;
  final List<TraceTimelineEntry> traceEvents;
  final void Function(TraceTimelineSelectResult result) onTraceSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Diagnostics', style: CellStyle(bold: true)),
        _DiagnosticReport(debugCaptures: debugCaptures, streaming: streaming),
        const SizedBox(height: 1),
        const Text('Trace timeline', style: CellStyle(bold: true)),
        SizedBox(
          height: 5,
          child: TraceTimeline(
            label: 'Demo trace timeline',
            events: traceEvents,
            copyOptions: const TraceTimelineCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
              includeTimestamp: false,
            ),
            onSelect: onTraceSelected,
          ),
        ),
      ],
    );
  }
}

class _DiagnosticReport extends StatelessWidget {
  const _DiagnosticReport({
    required this.debugCaptures,
    required this.streaming,
  });

  final int debugCaptures;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final snapshot = _DemoDiagnosticSnapshot.fromContext(
      context,
      debugCaptures: debugCaptures,
      streaming: streaming,
    );
    return Semantics(
      role: SemanticRole.diagnostic,
      label: 'Terminal diagnostics',
      actions: const {SemanticAction.diagnose, SemanticAction.captureDebug},
      onAction: (action) async {
        switch (action) {
          case SemanticAction.diagnose:
            await _invokeDemoCommand(context, demoCommandDiagnose);
            return;
          case SemanticAction.captureDebug:
            await _invokeDemoCommand(context, demoCommandCaptureDebug);
            return;
          case _:
            return;
        }
      },
      state: snapshot.semanticState,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Terminal profile: ${snapshot.diagnosis.capabilities.colorMode.name}',
          ),
          Text(
            'Native images: ${snapshot.diagnosis.capabilities.imageProtocol.name}',
          ),
          Text('OSC 52: ${snapshot.diagnosis.capabilities.osc52Clipboard}'),
          Text('OSC 8: ${snapshot.diagnosis.capabilities.osc8Hyperlinks}'),
          Text('Log stream: ${streaming ? 'on' : 'paused'}'),
          Text('Debug captures: $debugCaptures'),
          const SizedBox(height: 1),
          for (final item in snapshot.capabilities)
            _DiagnosticCapabilityRow(item: item),
        ],
      ),
    );
  }
}

final class _DemoDiagnosticSnapshot {
  const _DemoDiagnosticSnapshot({
    required this.diagnosis,
    required this.capabilities,
    required this.semanticState,
  });

  factory _DemoDiagnosticSnapshot.fromContext(
    BuildContext context, {
    required int debugCaptures,
    required bool streaming,
  }) {
    final media = MediaQuery.of(context);
    // The widget layer only sees neutral surface capabilities; protocol
    // details (which escape protocol, tmux passthrough) are presenter
    // concerns and never reach MediaQuery. The demo's requirement
    // resolution reports inline-image availability through the
    // side-channel, like the Image widget does.
    final surfaceImages = media.capabilities.images;
    final capabilities = TerminalCapabilities(colorMode: media.colorMode);
    final availableFeatures = surfaceImages == InlineImageSupport.placements
        ? const <TerminalFeature>{TerminalFeature.inlineImages}
        : const <TerminalFeature>{};
    final driver = FakeTerminalDriver(
      size: media.size,
      capabilities: capabilities,
    );
    final diagnosis = diagnoseTerminal(
      driver,
      environment: const <String, String>{
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      },
      stdinIsTerminal: true,
      stdoutIsTerminal: true,
    );
    final color = resolveCapabilityRequirement(
      const CapabilityRequirement(
        feature: TerminalFeature.colorTruecolor,
        level: CapabilityLevel.preferred,
        reason: 'Render full-fidelity color in rich widgets.',
        fallback: CapabilityFallback(label: 'ANSI color'),
      ),
      capabilities,
    );
    final images = resolveCapabilityRequirement(
      const CapabilityRequirement(
        feature: TerminalFeature.inlineImages,
        level: CapabilityLevel.preferred,
        reason: 'Render native images when the terminal supports them.',
        fallback: CapabilityFallback(label: 'glyph image'),
      ),
      capabilities,
      additionalAvailableFeatures: availableFeatures,
    );
    final osc8 = resolveCapabilityRequirement(
      const CapabilityRequirement(
        feature: TerminalFeature.osc8Hyperlinks,
        level: CapabilityLevel.prohibited,
        reason: 'Markdown links stay visible and inert by default.',
        fallback: CapabilityFallback(label: 'visible URL'),
      ),
      capabilities,
      policyBlockedFeatures: const <TerminalFeature>{
        TerminalFeature.osc8Hyperlinks,
      },
    );
    final clipboard = resolveCapabilityRequirement(
      const CapabilityRequirement(
        feature: TerminalFeature.clipboardWrite,
        level: CapabilityLevel.preferred,
        reason: 'Copy selected text while preserving an in-app fallback.',
        fallback: CapabilityFallback(label: 'in-process register'),
      ),
      capabilities,
    );
    final osc52 = resolveCapabilityRequirement(
      const CapabilityRequirement(
        feature: TerminalFeature.osc52Clipboard,
        level: CapabilityLevel.preferred,
        reason: 'Copy over SSH/tmux when platform clipboard is unavailable.',
        fallback: CapabilityFallback(label: 'in-process register'),
      ),
      capabilities,
    );
    final rows = <_CapabilityDiagnosticItem>[
      _CapabilityDiagnosticItem(
        label: 'Color fidelity',
        value: diagnosis.capabilities.colorMode.name,
        resolution: color,
      ),
      _CapabilityDiagnosticItem(
        label: 'Inline images',
        value: surfaceImages.name,
        resolution: images,
      ),
      _CapabilityDiagnosticItem(
        label: 'Markdown links',
        value: 'visible URL',
        resolution: osc8,
        extraState: const <String, Object?>{
          'osc8Policy': 'disabledByDefault',
          'linkFallback': 'visible URL',
        },
      ),
      _CapabilityDiagnosticItem(
        label: 'Clipboard write',
        value: clipboard.state.name,
        resolution: clipboard,
        extraState: <String, Object?>{
          'clipboardPolicy': TextClipboardPolicy.allowed.name,
          'clipboardCapability': clipboard.feature.name,
          'clipboardCapabilityResolution': clipboard.state.name,
          if (clipboard.fallbackLabel != null)
            'clipboardFallback': clipboard.fallbackLabel,
          'clipboardRedacted': false,
        },
      ),
      _CapabilityDiagnosticItem(
        label: 'OSC 52 clipboard',
        value: diagnosis.capabilities.osc52Clipboard,
        resolution: osc52,
        extraState: const <String, Object?>{
          'clipboardPolicy': 'policyGated',
          'clipboardTransport': 'osc52',
        },
      ),
    ];
    return _DemoDiagnosticSnapshot(
      diagnosis: diagnosis,
      capabilities: rows,
      semanticState: SemanticState({
        'diagnosisSchemaVersion': diagnosis.schemaVersion,
        'terminalColumns': diagnosis.terminal.size.cols,
        'terminalRows': diagnosis.terminal.size.rows,
        'terminalColorMode': diagnosis.capabilities.colorMode.name,
        'imageProtocol': diagnosis.capabilities.imageProtocol.name,
        'fallbackCount': diagnosis.fallbacks.length,
        'warningCount': diagnosis.warnings.length,
        'unsupportedFeatureCount': diagnosis.unsupportedFeatures.length,
        'capabilityRowCount': rows.length,
        'clipboardPolicy': TextClipboardPolicy.allowed.name,
        'clipboardCapability': clipboard.feature.name,
        'clipboardCapabilityResolution': clipboard.state.name,
        'clipboardRedacted': false,
        'osc52Policy': diagnosis.capabilities.osc52Clipboard,
        'osc8Policy': 'disabledByDefault',
        'debugCaptureCount': debugCaptures,
        'streaming': streaming,
      }),
    );
  }

  final TerminalDiagnosis diagnosis;
  final List<_CapabilityDiagnosticItem> capabilities;
  final SemanticState semanticState;
}

final class _CapabilityDiagnosticItem {
  const _CapabilityDiagnosticItem({
    required this.label,
    required this.value,
    required this.resolution,
    this.extraState = const <String, Object?>{},
  });

  final String label;
  final String value;
  final CapabilityResolution resolution;
  final Map<String, Object?> extraState;

  String get summary {
    final fallback = resolution.fallbackLabel;
    if (fallback == null) return '${resolution.state.name} ($value)';
    return '${resolution.state.name} ($value, fallback: $fallback)';
  }
}

class _DiagnosticCapabilityRow extends StatelessWidget {
  const _DiagnosticCapabilityRow({required this.item});

  final _CapabilityDiagnosticItem item;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      role: SemanticRole.diagnostic,
      label: item.label,
      value: item.value,
      actions: const {SemanticAction.diagnose},
      onAction: (action) async {
        if (action == SemanticAction.diagnose) {
          await _invokeDemoCommand(context, demoCommandDiagnose);
        }
      },
      state: item.resolution.toSemanticState().merge(item.extraState),
      child: Text('${item.label}: ${item.summary}'),
    );
  }
}

Future<void> _invokeDemoCommand(BuildContext context, CommandId id) async {
  final registry = CommandRegistryScope.maybeOf(context);
  if (registry == null) return;
  await registry.invoke(id, buildContext: context);
}
