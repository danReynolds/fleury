import 'package:fleury/fleury_core.dart';

import 'controls.dart' show Button, ButtonVariant;
import 'dialog.dart' show Dialog;

/// Severity for a protocol-neutral approval request.
enum ApprovalSeverity { info, warning, destructive }

/// User decision emitted by [ApprovalPrompt].
enum ApprovalDecision { approved, denied }

/// Protocol-neutral approval request data.
///
/// This intentionally avoids ACP, JSON-RPC, or provider-specific terminology.
/// Adapter packages can map their own permission or confirmation objects onto
/// this shape while Fleury owns the reusable UI, semantics, and test surface.
final class ApprovalRequest {
  const ApprovalRequest({
    required this.id,
    required this.title,
    required this.message,
    this.subject,
    this.details = const <String>[],
    this.severity = ApprovalSeverity.info,
    this.confirmLabel = 'Approve',
    this.cancelLabel = 'Deny',
  });

  /// Stable request identifier exposed through the semantic app graph.
  final String id;

  /// Heading shown at the top of the approval dialog.
  final String title;

  /// Primary explanation shown beneath [title].
  final String message;

  /// Optional resource or action that the decision applies to.
  final String? subject;

  /// Supplemental detail lines rendered as a bulleted list.
  final List<String> details;

  /// Visual severity and safe-focus policy for the request.
  final ApprovalSeverity severity;

  /// Label shown on the button that emits [ApprovalDecision.approved].
  final String confirmLabel;

  /// Label shown on the button that emits [ApprovalDecision.denied].
  final String cancelLabel;
}

/// A yes/no decision dialog for one [ApprovalRequest]: title, explanation,
/// optional subject and detail lines, and Approve/Deny buttons with `y`/`n`
/// key shortcuts. Destructive requests focus Deny by default, so a stray
/// Enter can't trigger an irreversible action.
class ApprovalPrompt extends StatelessWidget {
  const ApprovalPrompt({
    super.key,
    required this.request,
    required this.onDecision,
    this.width = 56,
    this.autofocusApprove,
  });

  /// Request content and severity to present.
  final ApprovalRequest request;

  /// Called whenever the user approves or denies [request].
  final void Function(ApprovalDecision decision) onDecision;

  /// Total dialog width, including its border; null sizes to the content.
  final int? width;

  /// Whether the confirm button is focused on open. When null (the default)
  /// this is severity-aware: a [ApprovalSeverity.destructive] request focuses
  /// *Deny* so a single Enter can't trigger an irreversible action — the
  /// safe-default convention used by every agent CLI. Non-destructive requests
  /// focus confirm. Pass an explicit value to override.
  final bool? autofocusApprove;

  bool get _autofocusApprove =>
      autofocusApprove ?? request.severity != ApprovalSeverity.destructive;

  void _approve() => onDecision(ApprovalDecision.approved);
  void _deny() => onDecision(ApprovalDecision.denied);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final approveFocused = _autofocusApprove;
    final Widget prompt = Semantics(
      role: SemanticRole.approval,
      label: request.title,
      value: request.subject,
      actions: const {SemanticAction.submit, SemanticAction.cancel},
      state: SemanticState({
        'approvalId': request.id,
        'severity': request.severity.name,
        if (request.subject != null) 'approvalSubject': request.subject,
        'detailCount': request.details.length,
        'confirmLabel': request.confirmLabel,
        'cancelLabel': request.cancelLabel,
      }),
      onAction: (action) {
        switch (action) {
          case SemanticAction.submit:
            _approve();
            return;
          case SemanticAction.cancel:
            _deny();
            return;
          case _:
            return;
        }
      },
      child: KeyBindings(
        // y/n raw-key shortcuts — the universal CLI confirm convention — so a
        // keyboard-first user decides without moving focus to a button.
        bindings: <KeyBinding>[
          KeyBinding(
            KeyCode.char('y'),
            onTrigger: () => _approve(),
            hideFromHintBar: true,
          ),
          KeyBinding(
            KeyCode.char('n'),
            onTrigger: () => _deny(),
            hideFromHintBar: true,
          ),
        ],
        child: Dialog(
          title: request.title,
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(request.message),
              if (request.subject != null)
                Text('Subject: ${request.subject}', style: theme.mutedStyle),
              if (request.details.isNotEmpty) ...[
                const SizedBox(height: 1),
                for (final detail in request.details) Text('- $detail'),
              ],
              if (request.severity == ApprovalSeverity.destructive) ...[
                const SizedBox(height: 1),
                Text(
                  '! Destructive — this cannot be undone.',
                  style: CellStyle(
                    foreground: theme.colorScheme.error,
                    bold: true,
                  ),
                ),
              ],
              const SizedBox(height: 1),
              Row(
                children: [
                  Button(
                    label: request.confirmLabel,
                    variant: _confirmVariant(request.severity),
                    autofocus: approveFocused,
                    onPressed: _approve,
                  ),
                  const SizedBox(width: 1),
                  Button(
                    label: request.cancelLabel,
                    autofocus: !approveFocused,
                    onPressed: _deny,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    // styled component, not selectable text
    return SelectionArea.disabled(child: prompt);
  }
}

ButtonVariant _confirmVariant(ApprovalSeverity severity) {
  return switch (severity) {
    ApprovalSeverity.info => ButtonVariant.primary,
    ApprovalSeverity.warning => ButtonVariant.warning,
    ApprovalSeverity.destructive => ButtonVariant.error,
  };
}
