import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  group('ModelStatusBar', () {
    testWidgets('renders sanitized model and token status semantics', (tester) {
      tester.pumpWidget(
        ModelStatusBar(
          info: ModelStatusInfo(
            model: 'gpt-proof\x1b]52;c;secret\x07',
            provider: 'local',
            status: ModelRuntimeStatus.streaming,
            mode: 'agent',
            detail: 'drafting',
            latency: const Duration(milliseconds: 123),
            queueDepth: 2,
            tokenUsage: const TokenUsage(
              input: 400,
              output: 600,
              cached: 100,
              contextUsed: 1100,
              contextLimit: 2000,
            ),
            metadata: const {'adapterReady': true},
          ),
        ),
      );

      final output = tester.renderToString(
        size: const CellSize(120, 3),
        emptyMark: ' ',
      );
      expect(output, contains('Model: local/gpt-proof'));
      expect(output, contains('streaming agent 123ms q2 drafting'));
      expect(output, contains('Context: 1.1k/2k'));
      expect(output, contains('55%'));
      expect(output, isNot(contains('secret')));
      expect(output, isNot(contains('\x1b]52')));

      final model = tester.semantics().single(
        role: SemanticRole.modelStatus,
        label: 'Model status',
        value: 'streaming',
      );
      expect(model.busy, isTrue);
      expect(model.state.modelName, 'gpt-proof\ufffd');
      expect(model.state.modelProvider, 'local');
      expect(model.state.modelStatus, 'streaming');
      expect(model.state.modelMode, 'agent');
      expect(model.state.modelLatencyMs, 123);
      expect(model.state.modelQueueDepth, 2);
      expect(model.state.tokenInput, 400);
      expect(model.state.tokenOutput, 600);
      expect(model.state.tokenCached, 100);
      expect(model.state.tokenTotal, 1100);
      expect(model.state.contextUsed, 1100);
      expect(model.state.contextLimit, 2000);
      expect(model.state.contextRemaining, 900);
      expect(model.state.contextRatioPercent, 55);
      expect(model.state['adapterReady'], isTrue);

      final token = tester.semantics().single(
        role: SemanticRole.tokenMeter,
        label: 'Context',
        value: '1100/2000',
      );
      expect(token.state.contextRatioPercent, 55);
      expect(token.state['contextNearLimit'], isFalse);
      expect(token.state['contextOverLimit'], isFalse);

      final modelFallback = tester.accessibilitySnapshot().single(
        role: SemanticRole.modelStatus,
        label: 'Model status',
      );
      expect(
        modelFallback.states,
        contains(
          'model status model gpt-proof\ufffd, provider local, '
          'status streaming, mode agent, 123ms latency, queue 2',
        ),
      );

      final tokenFallback = tester.accessibilitySnapshot().single(
        role: SemanticRole.tokenMeter,
        label: 'Context',
      );
      expect(
        tokenFallback.states,
        contains(
          'token meter 1100 of 2000 context, 900 remaining, 55%, '
          '1100 tokens, 400 input, 600 output, 100 cached',
        ),
      );
    });

    testWidgets('token meter reports near and over limit state', (tester) {
      tester.pumpWidget(
        const TokenMeter(usage: TokenUsage(contextUsed: 85, contextLimit: 100)),
      );

      var token = tester.semantics().single(role: SemanticRole.tokenMeter);
      expect(token.state['contextNearLimit'], isTrue);
      expect(token.state['contextOverLimit'], isFalse);

      tester.pumpWidget(
        const TokenMeter(usage: TokenUsage(contextUsed: 99, contextLimit: 100)),
      );

      token = tester.semantics().single(role: SemanticRole.tokenMeter);
      expect(token.state['contextNearLimit'], isFalse);
      expect(token.state['contextOverLimit'], isTrue);
    });
  });
}
