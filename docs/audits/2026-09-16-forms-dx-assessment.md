# Forms and validation DX assessment

Audited remote main as of 2026-09-16 `19a8978cb18e2c1853ec670d17088a41e5d2d0b0` in an isolated checkout. This records the baseline assessment before implementation.

## Follow-up decision

The user chose to retain the callback signature and have `submit()` return false
when a callback leaves a mounted, enabled field with an error. The implementation
applies pending UI updates and restores temporarily locked controls before the
final error check. It preserves successful form closure and explicit
`clearErrors()` after a reset; callback exceptions still propagate.

The focus option is named `validate(autofocus: false)`, with a documented default
of true and an any-caller-requests-focus rule for concurrent calls. Validation
timing modes remain deferred. The guide now uses four shared, runnable examples
with source/test tabs. The recommendations below describe the original audit,
not additional changes authorized or required by this implementation.

## Recommendation

Keep the existing architecture: values belong to application state, ordinary controls integrate through FormField, and Form coordinates validation, focus/reveal, and submission. Address the submission contract before making async saving the guide's recommended pattern. Add a way to validate without moving focus. Validation timing is a smaller optional extension; the current submit-first default is reasonable.

## Verified behavior

- 63 existing form tests pass, including controlled errors, dependent-field updates, first-invalid reveal, controller replacement, nested forms, reentrant submission, and custom-field focus diagnostics.
- Eight additional characterization probes pass. They assert observed behavior, including undesirable behavior; passing does not mean those API issues are fixed.
- Form.of(context) already subscribes to controller changes through Scope. A descendant submit button can read isBusy without an additional ListenableBuilder.
- Validators are synchronous. The Future returned by validate() waits for pending rebuilds; it does not mean asynchronous validators are supported.
- Before an explicit validation, edits and blur do not reveal validator errors. Once validation has run, changes revalidate revealed feedback, including dependent fields.
- clearErrors() clears validator feedback, not values or controlled server errors. This matches the ownership model and should remain explicit.

## 1. Make submission outcomes explicit, and unify error reporting

Source: packages/fleury_widgets/lib/src/form.dart:44-77, 354-365.

Today onSubmit is FutureOr<void> Function(). FormController.submit() returns true whenever that callback completes normally. Both of these were reproduced:

1. onSubmit returns false, which Dart permits in a void-result callback; submit() nevertheless returns true.
2. The save callback receives a server rejection and sets FormField.error = 'Name already exists'; submit() returns true while that error is visibly present.

Consequently, `if (await form.submit()) closeDialog()` can close a form whose server rejected the operation. The implementation follows its narrow callback-completed contract, but the boolean looks like an application success result.

Recommendation: give the submit callback an explicit accepted/rejected result and propagate that through the controller. Keep local validation rejection and unexpected exceptions distinguishable. A small typed result avoids silently discarding callback outcomes; choose its exact spelling during implementation design. Avoid inferring success by revalidating after the callback: fields may be disabled during saving, data may have changed, or the form may intentionally have unmounted.

There is also a failure-routing inconsistency:

- The guide recommends Button(onPressed: form.submit) and TextInput(onSubmit: (_) => form.submit()). These void callbacks discard the returned future. A thrown save error reaches the uncaught-error handler; runApp's handler treats an uncaught asynchronous error as fatal.
- The form's own semantic submit action catches the same exception and discards it, with no form-level reporting hook. The app stays alive but the user need not see feedback.
- Awaiting submit directly correctly exposes the exception.

The probes confirm the button/semantic difference in a guarded zone. Native terminal teardown itself was not exercised in this audit; its fatal behavior is established by run_app.dart's handler.

Recommendation: provide one observable submission-failure policy across button, Enter, command, and semantic entry points. Expected service failures need app-owned visible feedback; unexpected failures must remain available to callers/reporting. Assess a form-level error hook or a safe form submit binding together with the outcome change. Do not fix this by swallowing all errors globally or by rewriting the generic Button API just for forms. Meanwhile, the guide must show one shared save handler that handles expected failures.

External comparison: React Hook Form explicitly documents submit error ownership and preserves the callback result in its current API. This supports clarifying Fleury's contract; it does not require adopting React Hook Form's field-name registry or schema model.

## 2. Separate validation from moving keyboard focus

Source: packages/fleury_widgets/lib/src/form.dart:37-42, 277-299.

FormController.validate() always reveals feedback and focuses/reveals the first invalid field. The probe focuses Notes, calls validate(), and observes focus move to Name.

This is appropriate after an explicit submit. It is disruptive for a validation check while editing another field, a status panel, or an application reacting to a server response.

Recommendation: add a per-call option such as `validate(focusInvalid: false)`; preserve the existing default and have submit explicitly request focus/reveal. This option would still display errors. A silent validity query is a separate feature and should not be implied by this flag. Define how concurrent/coalesced validation requests with different focus policies combine; do not silently let the first call's choice win by accident.

External comparison: React Hook Form's manual trigger has a shouldFocus option, while failed submission focuses the first error by default. Fleury can retain its strong default without forcing focus movement for every validation call.

## 3. Optional validation timing: useful, not a prerequisite

Form and FormField currently expose no mode for first feedback on blur or change. Achieving that requires manual field-state/focus plumbing, or eagerly populating the controlled error property.

Flutter exposes AutovalidateMode, including interaction and unfocus policies. Textual Input exposes validate_on for changed/submitted/blur. These are established capabilities, but not a reason to add every policy to Fleury immediately.

If we want this now, add a small form-level validation policy with a field override, preserving submit-first plus revalidation as the default. A blur-first option is the most useful addition; it should validate the field left behind without stealing focus or revealing errors on untouched peers. Defer debounce/async validation machinery unless a real demo requires it.

## Guide-only improvements; no new API needed

- Teach isBusy for the submit/back actions and isSubmitting for locking fields after validation. A probe confirms that disabling a required Checkbox with isBusy causes it to be skipped by validation and allows the save. This is a misuse of already-documented disabled-field semantics, not evidence that disabled fields should start validating.
- Show an async save that snapshots submitted values, keeps them on failure, distinguishes field errors from a general service failure, supports retry, and reports success. Any early remote check must ignore stale responses; this can remain application-owned.
- Use Form.of(context) in a small descendant submit control to demonstrate its existing reactive behavior. Retain an external controller for parent actions and shortcuts.
- Explain synchronous, side-effect-free validators and dependent values. Do not imply that returning a Future<String?> is supported.
- Use visible labels as well as semantic labels. Errors should explain the correction, and successful completion needs visible feedback.
- Show clearErrors and reset as different operations. The application resets values and controlled errors; the form clears validator feedback.

## Rewrite plan

Replace the current single-demo, reference-heavy guide with four focused runnable examples:

1. **Validate a form**: one or two fields, submit empty, see inline feedback and focus, correct and submit. Show the first-invalid reveal in a constrained pane when needed.
2. **Save and retry**: controllable fake service with success, duplicate-name rejection, and offline failure; visibly show pending state, retry, and preserved values. Use the same handler for button and Enter.
3. **Validate related fields**: a small date range or confirmation pair showing dependent feedback after an attempt; introduce blur timing here only if the optional policy is approved.
4. **Build a custom field**: one small composite demonstrating focusNode, valueChanged, and error/semantics forwarding. Keep it as an advanced example after the common path.

Use complete source files shared by the live demos and tests, initially scrolled to the relevant section. The current MDX snippet, doc_snippets/forms.dart, and registry demo duplicate logic: the MDX slug validator uses raw slug.text, while the runnable versions validate slug.text.trim(). The snippet also omits visible labels present in the live demo. Importing the actual source removes that drift.

Tests should exercise each demonstrated user outcome, not merely render the initial form. The existing guide fixture test is a render smoke test. Dogfood the rewritten examples with keyboard and mouse, a narrow viewport, and pending/error states before declaring the guide ready.

Keep the basic comparison/ownership explanation short. Move exhaustive control lists, custom styling details, sensitive-input recipes, and API tables to linked reference pages where appropriate.

## Baseline audit evidence and limits

- Baseline: origin/main `19a8978c`, 2026-09-16.
- Existing suite receipt: /tmp/fleury-forms-dx-existing-tests.log (63 passed).
- Audit probes: /tmp/fleury-forms-dx-audit-probe-baseline.dart; receipt /tmp/fleury-forms-dx-probes.log (8 passed).
- Current guide fixture: doc_snippets_test.dart forms render test passed; receipt /tmp/fleury-forms-dx-guide-test.log.
- Probe development included correcting an unsupported StatefulBuilder helper and an initial hypothesis about Form.of subscription. The latter was disproved: Form.of is reactive. No missing reactive API is proposed.
- At the time of this baseline audit, production code and the published guide were unchanged. The follow-up decision above records the subsequent implementation scope.
- No browser screenshot, real screen-reader session, native PTY dogfood, or performance measurement was performed during the baseline assessment. Unit/semantic probes do not substitute for those checks.

## Primary sources consulted

- Flutter Form validation tutorial: https://docs.flutter.dev/cookbook/forms/validation
- Flutter AutovalidateMode: https://api.flutter.dev/flutter/widgets/AutovalidateMode.html
- Flutter forceErrorText: https://api.flutter.dev/flutter/widgets/FormField/forceErrorText.html
- React Hook Form official handleSubmit source documentation: https://github.com/react-hook-form/documentation/blob/master/src/content/docs/useform/handlesubmit.mdx
- React Hook Form official trigger source documentation: https://github.com/react-hook-form/documentation/blob/master/src/content/docs/useform/trigger.mdx
- React Hook Form official useForm source documentation: https://github.com/react-hook-form/documentation/blob/master/src/content/docs/useform.mdx
- Textual Input validation: https://textual.textualize.io/widgets/input/#validating-input
- W3C WAI form notifications: https://www.w3.org/WAI/tutorials/forms/notifications/

React Hook Form's site returned 403 to the browser tool, so its official documentation repository was read instead. Source links reflect the current docs, rather than a pinned historical package version.
