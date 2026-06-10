# Fleury Web Manual Validation Plan

This plan covers the empirical gates that browser automation and
frame captures cannot prove: real IME behavior and screen-reader
interaction with the retained DOM host.

## Setup

```sh
cd packages/fleury_web
dart compile js web/manual_validation.dart -o web/manual_validation.dart.js
dart test -p chrome test/manual_validation_page_test.dart
dart pub global activate dhttpd
dart pub global run dhttpd --path web
```

The browser smoke command verifies the retained DOM page wiring before
manual checks begin. It does not replace real IME or screen-reader
evidence.

Open `http://localhost:8080/manual_validation.html` from the local server.
Start manual checks only after the page reports
`document.body data-fleury-manual-validation="ready"`;
`mounted` only means host construction finished, not that the first
retained DOM frame has presented.

The page also exposes evidence provenance hints on `document.body`:
- `data-fleury-manual-browser-version`
- `data-fleury-manual-platform`
- `data-fleury-manual-user-agent`
- `data-fleury-manual-page`

Use `data-fleury-manual-browser-version` as the browser-version
value in the provenance command after confirming the manual
session is running in the intended browser.

Record one JSON entry per target using the template command:

```sh
dart run tool/web_manual_validation.dart --write-template=../../profiling/web/manual/templates/<target>.template.json --template-target=<target>
```

Template files ending in `.template.json` are ignored by audits.
After completing validation, copy the template to a non-template
evidence file such as
`../../profiling/web/manual/evidence/<target>-<date>.json`.

To fill only the provenance fields on a starter or copied evidence
file without changing target/check status, run:

```sh
dart run tool/web_manual_validation.dart --update-provenance=../../profiling/web/manual/evidence/<target>.review.json --template-target=<target> '--reviewed-by=<reviewer>' --captured-at=now '--browser-version=<Chrome version used for manual validation>'
```

Before review can pass, each evidence entry must include:

- top-level `status: "pass"`;
- non-empty, non-placeholder `reviewedBy`;
- parseable ISO-8601 `capturedAt`;
- environment `browser`, `browserVersion`, `platform`, and
  `fleuryWebPage`;
- `browser` and `platform` values matching the target metadata;
- `fleuryWebPage: "manual_validation.html"`;
- target-specific `inputMethod` for IME entries or
  matching `assistiveTechnology` for screen-reader entries;
- `status: "pass"` for every required check;
- reviewer observation notes on every passed check, rather
  than copied template instruction text.

## chrome-ime-macos: Chrome primary-browser IME smoke on macOS

- Phase: Phase 3
- Category: ime
- Browser: Chrome
- Platform: macOS
- Input method: Any real composing IME, such as Japanese Romaji

Required checks:

- `manual-page-loads-dom-host`: manual_validation.html reaches data-fleury-manual-validation="ready", retained DOM host output is visible, and no xterm element is present.
- `keyboard-capture-focused`: The hidden textarea keeps browser focus while the Fleury text field is focused.
- `composition-start-update-visible`: Starting and updating a real IME composition updates the focused Fleury field without committing duplicate text.
- `composition-end-commits-once`: Ending composition commits the selected text exactly once into the Fleury text field.
- `candidate-window-near-caret`: The hidden textarea reports data-fleury-caret-state="positioned", and the browser IME candidate window appears near the Fleury caret, not at the page origin.
- `typing-continues-after-composition`: Normal keyboard input continues after composition without manually refocusing the page.

## chrome-voiceover-macos: Chrome VoiceOver screen-reader smoke on macOS

- Phase: Phase 4
- Category: screenReader
- Browser: Chrome
- Platform: macOS
- Assistive technology: VoiceOver

Required checks:

- `manual-page-ready-semantic-host`: manual_validation.html reaches data-fleury-manual-validation="ready", retained semantic DOM output is reachable, and no xterm element is present.
- `visual-grid-hidden`: VoiceOver does not navigate the visual .fleury-screen row grid as a live terminal log.
- `semantic-root-exposed`: VoiceOver can reach the semantic textbox, action button, link, and status content.
- `focused-textbox-announced`: The focused Fleury text field is announced as an editable textbox with its value.
- `semantic-action-works`: Activating the sample action through VoiceOver updates the Fleury status text.
- `keyboard-capture-restored`: After semantic activation, typing goes back into the Fleury text field.
- `safe-link-announced`: The sample safe link is announced as a link and exposes the expected URL.
