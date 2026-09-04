# Launch hardening fixes — September 4, 2026

Follow-up to the launch audit, initially based on `main` at
`3950a9a358c621359636fe0dfd0974ec8de12276`, then rebased onto `0efa7ffd`
after the commands cleanup in PR #213. The embedded client was regenerated
from the combined sources. The pre-existing working checkout
and its uncommitted changes were preserved. This branch addresses the five
reproduced defects and the terminal test's environment dependence.

| Finding | Result | Regression evidence |
| --- | --- | --- |
| F1: moving right over `🇨🇦ष` selects both graphemes | Resolve the cluster end by forward segmentation from its locally resolved start; retain local scanning | Minimized selection/deletion test, 2,000 seeded Unicode/malformed UTF-16 strings checked at every offset, existing large-document cost test |
| F2: malformed child logs kill the serve host | Tolerant UTF-8 decoding; contain pipe errors in the log channel | Real serve tests emit malformed and split multibyte output on stdout and stderr, then exchange browser traffic and test concurrent sessions |
| F3: a throwing validator retains a pending submission | Complete the future with the original error and stack; clear pending validation in `finally` | Both `validate` and `submit` fail promptly, coalesce concurrent calls, and succeed on retry without unmounting |
| F4: a throwing listener strands later UI listeners | Report each listener error to the zone and continue the pass; apply the same isolation to ticker callbacks | Widget observes two committed model updates despite an earlier failing observer; later tickers receive both frames; existing listener lifecycle tests retained |
| F5 / N12: drawing cells ignore ambiguous-wide policy | Use one-cell ASCII drawing symbols on affected surfaces; measure and paint chart labels under the text policy; preserve measured table cells during replay | Cross-policy rendering matrix, including labels, tooltips, tables, images, five canvas modes and standalone sub-cell buffers; retained widget policy changes |
| P3: terminal lifecycle test assumes width probing is enabled | Match the query assertions to the environment's probe policy | Entire lifecycle file passes under `TERM=dumb` |

The F5 fallback is a deliberate rendering tradeoff: plot geometry and values
stay the same, while Unicode blocks and ornaments become ASCII symbols on
ambiguous-wide surfaces. Image cell art uses one averaged background color per
cell, or ASCII density in monochrome. Native image placements keep their
resolution. Chart labels retain Unicode and apply the surface's emoji lowering
policy. No new application-facing API is introduced for text projection; the
widget package uses the existing first-party internal barrel.

Validation commands for the combined patch:

```sh
TERM=xterm-256color dart tool/fleury_dev.dart check
TERM=xterm-256color dart tool/fleury_dev.dart benchmark gates
(cd packages/fleury && dart run tool/hot_reload_probe/driver.dart)
(cd packages/fleury && TERM=dumb dart test test/terminal/posix_driver_lifecycle_test.dart)
(cd website && npm run build)
```

Local results on product revision `0b72f21f` (Dart 3.12.2, macOS arm64):

| Check | Result |
| --- | --- |
| Full contributor gate | Exit 0; **5,323 tests passed, 1 skipped**, including 520 web/Chrome tests and 63 process/PTY integration tests |
| Static analysis | All package/tool analyses passed; no errors or warnings; existing informational lints remain |
| Drawing policy regressions | All 54 passed; included in the full gate count |
| Terminal lifecycle under `TERM=dumb` | All 20 passed |
| Fast performance gates | All 8 counter/invariant gates passed |
| VM-service hot reload | All 7 assertions passed |
| Documentation site | Build passed; 142 pages and compiled examples |
| GitHub CI | See the PR checks for validation of the rebased branch; the counts above describe the original local run |

One earlier full run timed out in the web CLI numeric-option test while the
documentation and performance builds overlapped. The same case passed unchanged
in six seconds alone, and the subsequent full gate passed with no competing
build jobs. No timeout thresholds or assertions were relaxed. The performance
run's wall-clock diagnostics were elevated under that overlapping load; those
are warn-only measurements, not evidence of a measured speed improvement or
regression. Its deterministic counters and structural assertions all passed.

PR review found and corrected one additional image fallback defect: reducing
sampling to one color per cell must preserve the terminal's 1:2 cell aspect.
Six new cases cover `contain`, `cover`, and `none` under both text policies;
all three ambiguous-wide cases reproduced the distortion before the fix.
Chart labels also reuse the shared single-line sanitizer. Copilot's review
identified redundant label projection and measurement in the line-chart paint
path; reference labels and legends now reuse a prepared label and its width.

This closes the reproduced code defects, not the entire release checklist.
Dependency remediation, the Ctrl+Z ownership decision, and fresh human terminal/accessibility
walkthroughs remain separate release work. Local automated checks do not stand
in for those terminal walkthroughs or CI on a merged release candidate.
