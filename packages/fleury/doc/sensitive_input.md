# Sensitive input with ordinary Fleury controls

Use `TextInput` for one line or `TextArea` for multiple lines. Both support
`obscureText`; revealing a value should update that property on the same
controller, not mount a second plaintext preview.

```dart
TextArea(
  controller: draft,
  focusNode: valueFocus,
  semanticLabel: 'Value',
  obscureText: !revealed,
  clipboardPolicy: TextClipboardPolicy.redacted,
  minLines: 1,
  maxLines: 6,
)
```

An explicit `redacted` clipboard policy keeps semantic values, copy/cut and
kill-ring capture redacted even while the value is visible. Use `disabled` to
block copy/cut entirely. Masking never weakens `disabled`. A separate app-owned
Copy action can deliberately deliver the original value using the application's
clipboard transport and feedback policy.

Masking is a presentation policy. It does not encrypt controller text, hide
length or line breaks, erase terminal history, or prevent screenshots. Do not
put values in semantic labels, error messages, log output or debug captures.

## Own the draft for exactly the form's lifetime

Keep its controller and focus node in the form's `State`. A reveal toggle must
not replace the controller. Temporary concealment can keep the editor mounted;
if a layout removes it, the external controller preserves committed edits.

Close/cancel should unmount the form, dispose its controller and focus node,
and drop the application's references to them. Create a fresh controller for
the next form so it cannot inherit the previous form's undo history.
Disposal releases the controller's current value and editing history; retained
references to a disposed controller read an empty value and cannot edit it.
Assigning `draft.text = ''` also resets editing history, even when already empty.
`draft.clear()` is an undoable edit. Finish the form's lifetime with disposal;
Dart strings have no guaranteed memory-zeroing operation.

## Choose a paste boundary deliberately

By default, large received pastes are applied over several frames. The editor
owns the pending tail and cancels it when unmounted, disabled, or made read-only,
even when its external controller survives. Submission through the field's
`onSubmit` completes its received paste first. Reading `controller.text` from
an unrelated action is not a paste-completion barrier.

For forms whose application already bounds input size, set
`pastePolicy: const TextPastePolicy.immediate()` from the start of the form.
Changing policy does not flush an already active chunked paste. Each received
segment is fully applied before returning to input dispatch; immediate
unmount/remount cannot lose an already received tail. Segments in one paste
retain a single undo step.
There is no disposal callback that can repopulate an intentionally cleared form.
This policy does not enforce a size limit or preserve future terminal segments
that arrive after the field disappears. Keep the default for unbounded editors,
and preserve their mounted lifetime while accepted input finishes.

## Explicit native session policy

A native-only application can choose its driver and runtime options directly:

```dart
await runApp(
  app,
  driver: PosixTerminalDriver(suspendOnCtrlZ: false),
  enableHotReload: false,
  debug: const DebugConfig(enabled: false),
);
```

Bind Ctrl+Z in the application to conceal/close the form, perform its cleanup,
and request exit. With the option above, interactive raw startup requires native
termios support; it fails if only Dart's line/echo fallback is available. The
default remains the driver's restore/stop/resume behavior. External SIGTSTP,
SIGSTOP and process termination are not converted into application callbacks by
this option. Foreground checks, clipboard transport, idle timeout and storage
security remain application responsibilities.
