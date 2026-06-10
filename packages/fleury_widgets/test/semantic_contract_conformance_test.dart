// Semantic-contract conformance for the fleury_widgets catalog.
//
// The semantic tree is the framework's headline differentiator, so "every
// widget contributes meaningful semantics" must be enforced, not assumed. Two
// layers:
//
//   1. Runtime sample — render representative widgets and assert their declared
//      SemanticRole actually materializes in the live semantic tree.
//   2. Catalog drift guard — a registry of every widget that declares a
//      SemanticRole, checked against source. Adding a widget that contributes
//      semantics (or removing semantics from one) fails the test until the
//      registry is updated, so the contract surface stays explicit and can't
//      silently drift.
//
// Note on capability fallback: color and grapheme-width degradation are handled
// centrally (renderer color downsampling + width resolver), and the only
// protocol-gated widgets (Image, MarkdownText hyperlinks; DataTable) already
// declare CapabilityRequirements. So there is deliberately no per-widget
// capability-fallback contract for chart/Unicode-glyph widgets — that would be
// cargo-cult. See architecture-priorities.md.

import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

/// Registry of every widget source file that contributes a [SemanticRole],
/// mapped to the sorted set of roles it declares. Derived from source; the
/// drift guard keeps it honest.
const Map<String, List<String>> _semanticCatalog = {
  'approval_prompt': ['approval'],
  'autocomplete': ['menu', 'menuItem'],
  'bar_chart': ['chart'],
  'calendar_heatmap': ['chart'],
  'code_view': ['code', 'codeLine'],
  'color_picker': ['list', 'radio'],
  'command_palette': ['command', 'commandPalette'],
  'completion_text_input': ['menu', 'menuItem'],
  'context_panel': ['contextItem', 'contextPanel'],
  'controls': ['button'],
  'conversation_navigator': ['conversation', 'conversationNavigator'],
  'data_table': ['table', 'tableCell', 'tableRow'],
  'date_picker': ['datePicker'],
  'dialog': ['dialog'],
  'diff_view': ['diff', 'diffLine'],
  'digits': ['text'],
  'file_browser': ['tree', 'treeItem'],
  'file_mention_picker': ['fileMention', 'fileMentionPicker'],
  'file_picker': ['tree', 'treeItem'],
  'form': ['app', 'form', 'formField', 'region'],
  'gauge': ['chart'],
  'heatmap': ['chart'],
  'histogram': ['chart'],
  'image': ['image'],
  'json_view': ['json', 'jsonNode'],
  'line_chart': ['chart'],
  'log_region': ['listItem', 'log'],
  'markdown_text': ['link', 'markdown', 'markdownBlock'],
  'menu': ['button', 'menu', 'menuItem'],
  'message_list': ['message', 'messageList'],
  'model_status_bar': ['modelStatus', 'tokenMeter'],
  'patch_review': ['patchFile', 'patchReview'],
  'process_panel': ['task'],
  'progress_bar': ['progress'],
  'range_slider': ['slider'],
  'search_panel': ['listItem', 'region'],
  'select': ['button', 'checkbox', 'list', 'menu', 'menuItem'],
  'sparkline': ['chart'],
  'stepper': ['spinButton'],
  'table': ['table', 'tableCell'],
  'tabs': ['tab'],
  'task_graph': ['task', 'taskGraph'],
  'toaster': ['notification'],
  'tool_call_card': ['toolCall'],
  'tooltip': ['region', 'text'],
  'trace_timeline': ['traceEvent', 'traceTimeline'],
  'tree': ['tree', 'treeItem'],
  'tree_table': ['tableCell', 'tree', 'treeItem'],
};

void _expectRole(FleuryTester tester, Widget widget, SemanticRole role) {
  tester.pumpWidget(SizedBox(width: 24, height: 8, child: widget));
  tester.render(size: const CellSize(24, 8));
  final roles = tester.semantics().nodes.map((n) => n.role).toSet();
  expect(
    roles,
    contains(role),
    reason: '${widget.runtimeType} must contribute a $role semantic node',
  );
}

void main() {
  group('semantic role materializes at runtime', () {
    testWidgets('Button → button', (t) {
      _expectRole(
        t,
        Button(label: 'OK', onPressed: () {}),
        SemanticRole.button,
      );
    });
    testWidgets('ProgressBar → progress', (t) {
      _expectRole(t, const ProgressBar(value: 0.5), SemanticRole.progress);
    });
    testWidgets('Gauge → chart', (t) {
      _expectRole(t, const Gauge(value: 0.5), SemanticRole.chart);
    });
    testWidgets('Sparkline → chart', (t) {
      _expectRole(
        t,
        const Sparkline(data: <double>[1, 3, 2, 4]),
        SemanticRole.chart,
      );
    });
    testWidgets('Heatmap → chart', (t) {
      _expectRole(
        t,
        const Heatmap(
          values: [
            [0, 1],
            [1, 0],
          ],
          cellWidth: 1,
        ),
        SemanticRole.chart,
      );
    });
    testWidgets('Stepper → spinButton', (t) {
      _expectRole(
        t,
        Stepper(value: 1, onChanged: (_) {}),
        SemanticRole.spinButton,
      );
    });
    testWidgets('RangeSlider → slider', (t) {
      _expectRole(
        t,
        RangeSlider(values: const (0, 10), min: 0, max: 10, onChanged: (_) {}),
        SemanticRole.slider,
      );
    });
    testWidgets('MultiSelect → checkbox list', (t) {
      t.pumpWidget(
        SizedBox(
          width: 24,
          height: 8,
          child: MultiSelect<String>(
            values: const {'red'},
            options: const [
              SelectOption(value: 'red', label: 'Red'),
              SelectOption(value: 'green', label: 'Green'),
            ],
            onChanged: (_) {},
          ),
        ),
      );
      t.render(size: const CellSize(24, 8));

      final roles = t.semantics().nodes.map((n) => n.role).toSet();
      expect(roles, contains(SemanticRole.list));
      expect(roles, contains(SemanticRole.checkbox));
    });
    testWidgets('Dialog → dialog', (t) {
      _expectRole(t, const Dialog(child: Text('body')), SemanticRole.dialog);
    });
    testWidgets('DataTable → table', (t) {
      _expectRole(
        t,
        DataTable(
          rowCount: 3,
          columns: const [
            DataTableColumn(id: 'a', title: 'A', width: FixedColumnWidth(6)),
          ],
          cellBuilder: (row, column) => 'r$row',
        ),
        SemanticRole.table,
      );
    });
  });

  group('catalog drift guard', () {
    test('source semantic-role surface matches the registry', () {
      final dir = Directory('lib/src');
      expect(dir.existsSync(), isTrue, reason: 'run from the package root');

      final pattern = RegExp(r'role:\s*SemanticRole\.(\w+)');
      final fromSource = <String, List<String>>{};
      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final name = entity.uri.pathSegments.last.replaceAll('.dart', '');
        final roles =
            pattern
                .allMatches(entity.readAsStringSync())
                .map((m) => m.group(1)!)
                .toSet()
                .toList()
              ..sort();
        if (roles.isNotEmpty) fromSource[name] = roles;
      }

      final newOrChanged = <String>[];
      fromSource.forEach((file, roles) {
        final known = _semanticCatalog[file];
        if (known == null) {
          newOrChanged.add('$file: NEW, declares $roles');
        } else if (!_listEq(known, roles)) {
          newOrChanged.add('$file: CHANGED, was $known now $roles');
        }
      });
      final removed = _semanticCatalog.keys
          .where((f) => !fromSource.containsKey(f))
          .map((f) => '$f: removed all semantics')
          .toList();

      expect(
        [...newOrChanged, ...removed],
        isEmpty,
        reason:
            'Semantic-contract surface drifted. A widget gained, lost, or '
            'changed its SemanticRole(s). Update _semanticCatalog (and confirm '
            'the change is intended) — the catalog is the explicit contract '
            'registry.',
      );
    });
  });
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
