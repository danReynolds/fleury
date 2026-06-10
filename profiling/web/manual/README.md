# Fleury web manual validation evidence

This directory is for reviewed manual evidence that automation cannot fully
prove. The current v1 release gate does not require manual browser evidence.
Real browser IME behavior and screen-reader interaction remain explicit
roadmap validation targets for the retained DOM host.

Generate the current validation plan:

```sh
fleury benchmark web-manual-validation --write-plan=profiling/web/manual/plan.md
```

The manual validation page reports readiness through
`document.body[data-fleury-manual-validation]`. Start manual checks only after
the value is `"ready"`. The intermediate `"mounted"` value
means the retained DOM host was constructed, but it does not prove the first
retained DOM frame has presented.
The VoiceOver follow-up template also records this as
`manual-page-ready-semantic-host` so standalone screen-reader evidence can prove
retained semantic DOM readiness when that pass starts.
Run the plan's Chrome browser smoke command before collecting evidence. It
preflights retained DOM page wiring, semantic projection, safe-link projection,
and hidden-textarea caret metadata, but it does not replace any future real IME
or screen-reader check.
The page also writes evidence metadata to `document.body`:
`data-fleury-manual-browser-version`, `data-fleury-manual-platform`,
`data-fleury-manual-user-agent`, and `data-fleury-manual-page`. Templates list
the same contract under `reviewInstructions.provenanceAttributes`. Use the
browser-version attribute for `--browser-version` after confirming the page is
open in the intended Chrome session.

Generate a JSON evidence template for one target:

```sh
fleury benchmark web-manual-validation --write-template=profiling/web/manual/templates/chrome-ime-macos.template.json --template-target=chrome-ime-macos
```

Template files ending in `.template.json` are ignored by audits. After
completing manual validation, copy the template to a non-template evidence file
such as `profiling/web/manual/evidence/chrome-ime-macos-2026-06-08.json`, set
the top-level `status` and each required check status, replace the blank
`capturedAt` value with the actual validation time, and include reviewer and
environment details.

Release-action packets may also generate no-overwrite starter evidence files
under `profiling/web/manual/evidence/*.review.json`. Those files are valid
pending evidence entries, not reviewed passes. Fill in the same provenance and
check statuses after manual validation, then rerun the strict audit.

To fill only provenance on a starter or copied evidence file without changing
the top-level status or required-check status, run:

```sh
fleury benchmark web-manual-validation --update-provenance=profiling/web/manual/evidence/chrome-ime-macos.review.json --template-target=chrome-ime-macos '--reviewed-by=<reviewer>' --captured-at=now '--browser-version=<Chrome version used for manual validation>'
```

To record one observed required page signal without hand-editing JSON, run:

```sh
fleury benchmark web-manual-validation --update-page-signal=profiling/web/manual/evidence/chrome-ime-macos.review.json --template-target=chrome-ime-macos --signal-id=<required-page-signal-id> --signal-status=pass --observed-value=<expected-value> '--signal-notes=<reviewer observation>'
```

To record one observed required check without hand-editing JSON, run:

```sh
fleury benchmark web-manual-validation --update-check=profiling/web/manual/evidence/chrome-ime-macos.review.json --template-target=chrome-ime-macos --check-id=<required-check-id> --check-status=pass '--check-notes=<reviewer observation>'
```

Strict audits require more than `status: "pass"`. Each passing evidence entry
must include non-empty `reviewedBy`, `capturedAt`,
`environment.browser`, `environment.browserVersion`, `environment.platform`,
`environment.fleuryWebPage`, and the target-specific
`environment.inputMethod` or `environment.assistiveTechnology` field. The
browser, platform, and assistive-technology values must match the target being
validated. Missing or mismatched provenance leaves the target in `needsReview`.

Audit reviewed entries:

```sh
fleury benchmark web-manual-validation --input=profiling/web/manual --output=profiling/web/manual/review.md --json-output=profiling/web/manual/manual-validation-audit.json --strict
```

The explicit v1 target preset currently covers no required manual browser
targets. `primary` remains a compatibility alias for that current release set,
but release packets should use `--target-preset=v1` so the scope is visible in
generated artifacts. The roadmap manual targets remain available through
explicit target selection:

- `chrome-ime-macos`: primary-browser real IME smoke.
- `chrome-voiceover-macos`: primary-browser VoiceOver smoke.

Use `--target=chrome-ime-macos`, `--target=chrome-voiceover-macos`, or
`--target-preset=all` when that follow-up validation is in scope. Add more
target entries as the supported release evidence set expands. A passing entry
means the reviewer set the top-level `status` to `pass` and every required
check for that target also has `status: "pass"`.
