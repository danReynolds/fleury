# Agent Adapter Readiness Audit

**Status:** M1.5 complete for Fleury launch scope  
**Scope:** Protocol-neutral readiness only. ACP implementation remains
deferred to `fleury_acp`.

## Purpose

Confirm that Fleury can support a fast-follow agent adapter package without
putting ACP schemas, JSON-RPC transport, protocol models, or ACP-specific
widgets into Fleury core.

This audit closes M1.5 as a boundary/readiness milestone. It does not start
`fleury_acp`.

## Readiness Checklist

- [x] Semantic graph can represent commands, text inputs, message transcripts,
  tool calls, task graphs, model/context status, token meters, file mentions,
  conversation/thread navigation, context packs, trace timelines,
  patch-review surfaces, tasks/progress, output summaries, selections, dialogs,
  approval prompts, data rows/cells, diagnostics, and capability fallback state.
  - Evidence:
    [semantic core](../../packages/fleury/lib/src/semantics/semantics.dart),
    [semantic tests](../../packages/fleury/test/semantics/semantics_test.dart),
    [MessageList tests](../../packages/fleury_widgets/test/message_list_test.dart),
    [ToolCallCard tests](../../packages/fleury_widgets/test/tool_call_card_test.dart),
    [TaskGraph tests](../../packages/fleury_widgets/test/task_graph_test.dart),
    [ModelStatusBar tests](../../packages/fleury_widgets/test/model_status_bar_test.dart),
    [FileMentionPicker tests](../../packages/fleury_widgets/test/file_mention_picker_test.dart),
    [ConversationNavigator tests](../../packages/fleury_widgets/test/conversation_navigator_test.dart),
    [ContextPanel tests](../../packages/fleury_widgets/test/context_panel_test.dart),
    [TraceTimeline tests](../../packages/fleury_widgets/test/trace_timeline_test.dart),
    [PatchReview tests](../../packages/fleury_widgets/test/patch_review_test.dart),
    [ApprovalPrompt tests](../../packages/fleury_widgets/test/approval_prompt_test.dart),
    [DataTable tests](../../packages/fleury_widgets/test/data_table_test.dart),
    [demo app tests](../../packages/fleury_example_console/test/demo_console_test.dart).

- [x] App kernel exposes command IDs, command invocation, screen state, status,
  command palette integration, and tester command routing.
  - Evidence:
    [app shell](../../packages/fleury/lib/src/app/app.dart),
    [commands](../../packages/fleury/lib/src/app/commands.dart),
    [tester command helpers](../../packages/fleury/lib/src/testing/fleury_tester.dart),
    [app tests](../../packages/fleury/test/app/fleury_app_test.dart),
    [command tests](../../packages/fleury/test/app/command_registry_test.dart),
    [command palette tests](../../packages/fleury_widgets/test/command_palette_test.dart).

- [x] Worker/task model exposes success, failure, cancellation, progress,
  ordered output, subprocess handoff boundaries, and semantic task state.
  - Evidence:
    [task controller](../../packages/fleury/lib/src/effects/task.dart),
    [process task controller](../../packages/fleury/lib/src/effects/process_task.dart),
    [task tests](../../packages/fleury/test/effects/task_test.dart),
    [process task tests](../../packages/fleury/test/effects/process_task_test.dart),
    [demo app task workflow](../../packages/fleury_example_console/test/demo_console_test.dart).

- [x] Sanitized output pipeline handles active terminal sequences, unsafe
  OSC/DCS/APC payloads, malformed UTF-8, huge lines, markdown links,
  DataTable export/copy, clipboard reports, and redaction hooks before debug
  capture or inspector output.
  - Evidence:
    [text sanitizer tests](../../packages/fleury/test/rendering/text_sanitizer_test.dart),
    [process output tests](../../packages/fleury/test/effects/process_task_test.dart),
    [clipboard tests](../../packages/fleury/test/runtime/clipboard_test.dart),
    [markdown tests](../../packages/fleury_widgets/test/markdown_text_test.dart),
    [debug capture tests](../../packages/fleury/test/debug/debug_capture_test.dart),
    [debug shell tests](../../packages/fleury/test/debug/debug_shell_test.dart).

- [x] Data/developer-tool widgets expose protocol-neutral selection, copy,
  patch review, virtualization, filtering/sorting helpers, semantic state, and
  benchmark evidence.
  - Evidence:
    [DataTable](../../packages/fleury_widgets/lib/src/data_table.dart),
    [PatchReview](../../packages/fleury_widgets/lib/src/patch_review.dart),
    [DataTable tests](../../packages/fleury_widgets/test/data_table_test.dart),
    [PatchReview tests](../../packages/fleury_widgets/test/patch_review_test.dart),
    [DataTable baseline](../../packages/fleury_widgets/benchmark/results/phase1-widgets-2026-05-31.json),
    [demo app Runs workflow](../../packages/fleury_example_console/test/demo_console_test.dart).

- [x] Debug capture and inspector hooks can snapshot terminal/input/frame
  events, semantic state, output summaries, capability state, tasks, and
  selected semantic nodes without a protocol-specific replay format.
  - Evidence:
    [debug capture](../../packages/fleury/lib/src/debug/debug_capture.dart),
    [debug events](../../packages/fleury/lib/src/debug/debug_events.dart),
    [debug panel](../../packages/fleury/lib/src/debug/debug_panel.dart),
    [debug capture tests](../../packages/fleury/test/debug/debug_capture_test.dart),
    [debug shell tests](../../packages/fleury/test/debug/debug_shell_test.dart),
    [demo app capture-to-test workflow](../../packages/fleury_example_console/test/demo_console_test.dart).

- [x] Capability/security policy is visible to widgets, semantics, diagnostics,
  tests, and the demo app.
  - Evidence:
    [capability requirements](../../packages/fleury/lib/src/terminal/capability_requirements.dart),
    [diagnostics](../../packages/fleury/lib/src/terminal/diagnostics.dart),
    [diagnostics tests](../../packages/fleury/test/terminal/diagnostics_test.dart),
    [image tests](../../packages/fleury_widgets/test/image_test.dart),
    [demo app diagnostics tests](../../packages/fleury_example_console/test/demo_console_test.dart).

- [x] Fleury core and widgets have no ACP/JSON-RPC/protocol-schema imports.
  - Evidence: `rg -n "\bACP\b|agentclientprotocol|JSON-RPC|jsonrpc|session/prompt|session/update|terminal/output|Acp" packages/fleury packages/fleury_widgets`
    returned no matches on 2026-05-31.

## Deferred To `fleury_acp`

- ACP transport and JSON-RPC framing.
- ACP schema/version handling.
- ACP session, prompt-turn, tool-call, permission, terminal, and cancellation
  models.
- ACP-specific widgets such as session lists, prompt-turn views, tool-call
  cards, permission prompts, terminal attachments, and ACP replay fixtures.

`ApprovalPrompt` is no longer deferred as a generic Fleury widget. ACP-specific
permission prompts, permission schemas, and ACP request/outcome mapping remain
deferred to `fleury_acp`.

## Remaining Fast-Follow Widgets

These should follow demo-app or later flagship pressure rather than becoming
launch blockers:

- Richer protocol-neutral workflow surfaces beyond the current approval,
  transcript, tool-call, task-graph, model/status, file-reference,
  conversation, context, trace, and patch-review set when demo-app or later
  flagship pressure shows a concrete need.
- ACP-specific permission widgets beyond generic `ApprovalPrompt`.

## Conclusion

Fleury is adapter-ready for launch scope: a later `fleury_acp` package can map
ACP concepts onto semantic nodes, app commands, task/effect state, sanitized
output, workflow timelines, patch-review surfaces, capability policy,
selection/copy, debug capture, and the demo-app tested widget/runtime surfaces
without changing Fleury core.
