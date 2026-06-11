# Fleury Web Manual Validation Plan

This plan covers the empirical gates that browser automation and
frame captures cannot prove: manual browser behavior with the
retained DOM host.

## Setup

```sh
cd packages/fleury_web
dart compile js web/manual_validation.dart -o web/manual_validation.dart.js
dart test -p chrome test/manual_validation_page_test.dart
dart pub global activate dhttpd
dart pub global run dhttpd --path web
```

The browser smoke command verifies the retained DOM page wiring before
manual checks begin. It does not replace manual browser behavior
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

To update one required page signal after observing it, run:

```sh
dart run tool/web_manual_validation.dart --update-page-signal=../../profiling/web/manual/evidence/<target>.review.json --template-target=<target> --signal-id=<required-page-signal-id> --signal-status=pass --observed-value=<expected-value> '--signal-notes=<reviewer observation>'
```

To update one required check after observing it, run:

```sh
dart run tool/web_manual_validation.dart --update-check=../../profiling/web/manual/evidence/<target>.review.json --template-target=<target> --check-id=<required-check-id> --check-status=pass '--check-notes=<reviewer observation>'
```

Before review can pass, each evidence entry must include:

- top-level `status: "pass"`;
- non-empty, non-placeholder `reviewedBy`;
- parseable ISO-8601 `capturedAt`;
- environment `browser`, `browserVersion`, `platform`, and
  `fleuryWebPage`;
- `browser` and `platform` values matching the target metadata;
- `fleuryWebPage: "manual_validation.html"`;
- target-specific `inputMethod` for IME entries
  or matching `assistiveTechnology` for screen-reader entries;
- `observedPageSignals` entries with `status: "pass"` and
  `observedValue` matching each required page signal;
- `status: "pass"` for every required check;
- reviewer observation notes on every passed check, rather
  than copied template instruction text.
