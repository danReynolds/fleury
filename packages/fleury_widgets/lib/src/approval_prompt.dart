import 'package:fleury/fleury_core.dart';

import 'dialog.dart' show Dialog;
import 'semantic_roles.dart';

/// How serious an [ApprovalRequest] is. It sets the confirm button's color;
/// `destructive` also adds a "cannot be undone" warning and, by default,
/// focuses the deny button.
enum ApprovalSeverity { info, warning, destructive }

/// User decision emitted by [ApprovalPrompt].
enum ApprovalDecision { approved, denied }

/// What an [ApprovalPrompt] asks the user to approve: a title, a message, an
/// optional subject and detail lines, a severity, and the button labels.
///
/// It isn't tied to any agent protocol, so map your own permission or
/// confirmation objects onto it.
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
///
/// Esc denies, as the semantic cancel action does. In a dialog shown with
/// `present`, Esc answers the request through [onDecision] instead of closing
/// the dialog around it. The route `present` makes can still close it
/// unanswered, with null as `present`'s result: through the route's semantic
/// dismiss action, which an agent can invoke, or through
/// [NavigatorState.maybePop], as a Back command does. Pass
/// `barrierDismissible: false`, as below, to turn both off, so every way out
/// goes through [onDecision]. Close the prompt from there; popping with the
/// decision makes it `present`'s result:
///
/// ```dart
/// final decision = await context.present<ApprovalDecision>(
///   ApprovalPrompt(request: request, onDecision: context.pop),
///   barrierDismissible: false,
/// );
/// ```
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

  /// Called whenever the user approves or denies [request]: with a button,
  /// `y` or `n`, Esc (which denies), or a semantic action. The prompt doesn't
  /// close itself; dismiss it from here.
  final void Function(ApprovalDecision decision) onDecision;

  /// Total dialog width, including its border; null sizes to the content.
  final int? width;

  /// Whether the confirm button is focused on open. When null (the default),
  /// an [ApprovalSeverity.destructive] request focuses the deny button, so a
  /// single Enter can't trigger an irreversible action, and other requests
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
    return Semantics(
      role: WidgetRoles.approval,
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
            onTrigger: (_) => _approve(),
            hideFromHintBar: true,
          ),
          KeyBinding(
            KeyCode.char('n'),
            onTrigger: (_) => _deny(),
            hideFromHintBar: true,
          ),
          // Esc cancels, and cancelling a request is denying it. Bound here,
          // it answers before a dialog route's Esc would close the prompt
          // around a request nobody answered.
          KeyBinding(
            KeySequence.escape,
            onTrigger: (_) => _deny(),
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
                    text: request.confirmLabel,
                    variant: _confirmVariant(request.severity),
                    autofocus: approveFocused,
                    onPressed: _approve,
                  ),
                  const SizedBox(width: 1),
                  Button(
                    text: request.cancelLabel,
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
    // NB: no blanket opt-out here. The Dialog title and the Buttons are chrome
    // and opt out on their own; the message / subject / details are CONTENT the
    // user may want to select and copy (the command, path, etc.).
  }
}

ButtonVariant _confirmVariant(ApprovalSeverity severity) {
  return switch (severity) {
    ApprovalSeverity.info => ButtonVariant.primary,
    ApprovalSeverity.warning => ButtonVariant.warning,
    ApprovalSeverity.destructive => ButtonVariant.error,
  };
}
