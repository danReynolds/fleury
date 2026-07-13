# RFC 0017: OSC 8 Hyperlinks

**Status:** Accepted — Stage 1 (terminal emission core) in progress.
**Date:** 2026-07-13
**Decision point for:** how Fleury emits real terminal hyperlinks (OSC 8), how a
link is carried from a widget through the cell grid to both surfaces, and the
staging that keeps the wire byte-identical until the browser half lands.

This RFC anchors the OSC 8 work. It captures what OSC 8 is, the two-halves
capability framing it slots into, the carrier design (`CellStyle.linkUri`), the
renderer's close obligation, why the renderer suppresses links under tmux, the
Stage 2 wire plan, scheme allow-listing, and the three-stage rollout. It records
the decisions taken so later stages don't relitigate them.

Cross-references: **RFC 0013** (capability & security contract — the trust model
OSC 8 output rides on) and
[`docs/implementation/wire-protocol.md`](../implementation/wire-protocol.md)
(the serve/shell framing the Stage 2 codec change lives in).

---

## 1. What OSC 8 is

OSC 8 is the de-facto terminal hyperlink escape (originated by iTerm2 and
GNOME VTE, now in a wide set of emulators). A hyperlink wraps display text so
the emulator makes it clickable while the glyphs still render normally:

```
ESC ] 8 ; params ; URI ESC \      open a link (URI applies to text that follows)
   …the clickable display text…
ESC ] 8 ; ;      ESC \            close the link (empty URI ends it)
```

Concretely, "open `https://x`" is `\x1B]8;;https://x\x1B\\` and "close" is
`\x1B]8;;\x1B\\`. The `params` field (between the two semicolons of the open) is
a `key=value:key=value` list; the only widely-honored key is `id=`, which groups
non-contiguous runs into one logical link for hover-highlighting. Stage 1 emits
**empty params**; `id=` is a Stage 3 refinement (see §8).

Two properties drive the whole design:

- **The link is a cell attribute, like SGR.** The emulator applies the active
  link to characters *as they are printed*. Moving the cursor without printing
  does not link the skipped cells. This is what makes the cursor-jump case safe
  by construction (see §4).
- **`ESC[0m` does NOT close a link.** SGR reset and the OSC 8 link are
  independent terminal state. A dangling open link bleeds onto everything the
  terminal prints afterward — including the shell prompt after the app exits —
  until an explicit close. The renderer therefore owns an explicit close
  obligation that is entirely separate from its SGR bookkeeping (see §4).

## 2. Two-halves capability framing

Fleury already models terminal features as explicit capabilities (RFC 0013).
Hyperlinks are split across two capability names, and they mean different
things:

| Capability | Meaning | Before this RFC | After Stage 1 |
| --- | --- | --- | --- |
| `hyperlinks` (generic) | "This surface has a real link concept at all." | `true` (browser anchors; terminal-agnostic) | unchanged |
| `osc8Hyperlinks` (emission) | "OSC 8 specifically works here, right now." | hardcoded `false` (stubbed off) | **derived from detection** |

The generic `hyperlinks` capability was already `true` — including on the
browser surface, whose DOM client renders anchors and has no OSC 8 concept. The
browser half is real and shipping. What was stubbed off was the *terminal
projection* and the *emission path*: `TerminalCapabilities.toSurfaceCapabilities`
hardcoded `hyperlinks: false`, and `TerminalFeature.osc8Hyperlinks` hardcoded
`return false`.

Stage 1 flips the terminal emission half from "stubbed off" to "detected": a
terminal that a startup env probe recognizes as OSC-8-capable (and is not under
tmux) reports `hyperlinks: true`, and the ANSI renderer built for that session
emits OSC 8. Nothing that lacks the detected capability changes by a byte.

## 3. Design: `CellStyle.linkUri` as the carrier

A link is carried as one nullable field on the immutable `CellStyle`:

```dart
final String? linkUri; // OSC 8 target for this run, or null.
```

Why a field on `CellStyle` rather than a parallel structure:

- **Shared by reference → zero per-cell allocation.** A run of linked cells all
  point at the *same* `String` instance (and typically the same `CellStyle`
  instance) that the producing widget created once. Adding the field costs one
  pointer slot on a value that is already heap-shared across every cell of a
  run; it does not allocate per cell. This is the property the alloc-gate
  guards, and it holds by construction.
- **Run-split, dedupe, and mirror come for free via `==`/`hashCode`.** The diff
  renderer, the wire codec's per-frame style table, and the browser mirror all
  key on `CellStyle` equality. Adding `linkUri` to `==` and `hashCode` means two
  cells that differ only by their link are correctly treated as different
  styles — they split into different runs, dedupe to different table entries,
  and round-trip without merging. This is **required**: omitting the field from
  `==` would let the diff renderer and wire dedupe silently merge link-differing
  cells and drop the link.
- **A simple null-or-value field.** Unlike the bool attributes, a link has no
  tri-state "explicitly off" need — absence is null, presence is the URI.
  `CellStyle.empty` and the shared const singletons keep `linkUri == null` and
  are unaffected. `merge` takes the other's link when set, else keeps this one —
  matching how colors and attributes already merge.

To offset the one extra comparison the field adds to the equal-style hot path,
`CellStyle.==` gains an `identical(this, other)` fast-path at the top (it had
none — comparison was unconditionally field-by-field). Because linked runs share
one `CellStyle` instance, the fast-path resolves most in-run comparisons before
any field is read.

**Trust boundary.** `linkUri` is set only by trusted widget code. Untrusted
output never reaches a cell with a link: `sanitizeForDisplay` strips OSC 8 (and
every other escape) from untrusted text before it can become cell content, and
producers apply scheme allow-listing (§6) before setting the field. The field is
documented to that effect.

## 4. Renderer emission and the close obligation

The ANSI renderer gains a `bool hyperlinks` constructor flag (default **false**,
matching the stubbed-off status quo). It is the emission gate: with
`hyperlinks: false` the renderer emits nothing link-related regardless of what a
cell carries, so link-free output and unsupporting terminals are byte-identical
to today. All OSC 8 logic lives under `if (hyperlinks)`.

**Emission at the style choke point.** The renderer already has a single point
where it notices a style change per cell. Beside the emitted-style tracker it
threads an `emittedLink` tracker (the currently-open URI, or null). When a
cell's `linkUri` differs from `emittedLink`, it emits — *after* any SGR delta and
*before* the grapheme — a close (if a link was open) and/or an open (if the new
link is non-null), then updates `emittedLink`. Because the grapheme is written
while the link is active, exactly the written cell carries it.

**SGR/link decoupling.** Since `ESC[0m` does not close a link and the SGR
encoders never read `linkUri`, the renderer reasons about *visual* style
(colors + attributes) for its SGR decisions and about `linkUri` separately for
OSC 8. Concretely, the style choke and its empty-style branch compare visual
style (`sameVisualStyleAs` / `isVisuallyEmpty`, which ignore `linkUri`), so a
link-only change drives an OSC 8 transition and never a spurious `ESC[0m`. For
link-free buffers these visual comparisons are identical to full `==`, so the
non-link path is byte-for-byte unchanged; for `hyperlinks: false` they make the
output identical whether or not cells happen to carry a link.

**Frame-end close (critical).** A link still open after the last cell is closed
explicitly at frame end — a *separate* close from the existing SGR reset, since
the reset does not close it. Without this, the link bleeds into the shell prompt
on exit.

**Cursor-jump handling — rely on the per-cell choke (no close-on-move).** The
two candidate strategies were (a) close the link before every non-advancing CUP
and reopen at the destination, or (b) rely on the choke re-evaluating `linkUri`
at every cell. Fleury takes **(b)**. It is correct because the emulator links
only cells that are *printed*: a CUP that skips cells writes nothing to them, so
an open link cannot leak onto them, and the destination cell re-evaluates its
own link at the choke. (b) is also fewer bytes — it never closes+reopens a
same-URI run that a jump merely stepped over. The one write-path that *does*
emit skipped cells is the gap rewrite, handled next.

**Gap-rewrite threading (critical).** The renderer sometimes rewrites an
unchanged gap between two dirty cells as literal text instead of a cursor move,
threading the emitted style through it. That path writes the intervening cells,
so an open link would leak onto them. Under `hyperlinks: true` the gap rewrite
**bails** (falls back to a cursor move, which is always link-safe) if any gap
cell's `linkUri` differs from the currently-open link — so a rewritten run only
ever happens when every cell in it shares exactly the active link. Its internal
style comparisons are visual (as above), so `hyperlinks: false` leaves the gap
path byte-identical regardless of link presence.

## 5. Wire plan (Stage 2)

Nothing on the wire changes in Stage 1. The `linkUri` field is not serialized;
the serve/shell path stays byte-identical because no producer sets a link yet
and the structured presenter does not read the field.

Stage 2 adds link carriage under a **version bump to v4** (per the
wire-protocol compatibility rule, a cell/enum *encoding* change inside an
existing frame is version-gated, not additive). The cell-style encoding packs
the tri-state bool attributes into a "set" mask byte using bits 0–5; **bits 6–7
are spare**. Stage 2 claims one spare set-mask bit as "has link" and, when set,
writes a length-prefixed UTF-8 URI after the style's colors. When `linkUri` is
null the bit stays clear and no string is written, so **a link-free frame is
byte-identical to today's v3 encoding** — the added cost is paid only by frames
that actually carry links. The browser mirror reads the bit and renders an
anchor.

## 6. Scheme allow-listing

RFC 0013 specifies an `OutputSecurityPolicy` with an `allowOsc8` gate and a
default-safe scheme allow-list (`https`, `http`, `mailto`; `file` only on
explicit opt-in; custom schemes require opt-in). That policy type is **RFC-only
today** — it is not yet a built type in the tree. OSC 8 does not wait on it:
enforcement lands **at the producers in Stage 2** (the widgets that set
`linkUri` — e.g. `MarkdownText`), which validate the scheme before populating the
field. The renderer stays a dumb emitter: by the time a URI reaches a cell it is
already trusted and allow-listed. This keeps the security decision at the trust
boundary (the producer that knows the content source) rather than in the byte
emitter, consistent with RFC 0013's "trust is local to the content source."

## 7. Staging

- **Stage 1 — terminal emission core (this RFC, in progress).** `CellStyle`
  carries the link; the ANSI renderer emits OSC 8 gated by a detected,
  tmux-suppressed capability; detection + diagnostics + capability wiring.
  Exercised by tests only — **no real widget produces a link yet**, so terminal
  output is unchanged by construction and the wire stays byte-identical.
- **Stage 2 — wire + browser + producers.** The v4 codec bit (§5); the browser
  DOM client rendering anchors; the producers (`MarkdownText` and friends) that
  set `linkUri`, with scheme allow-listing (§6) and the inspectable-suffix
  opt-out (§8).
- **Stage 3 — polish.** OSC 8 `id=` params to group multi-line / non-contiguous
  runs into one hover target; any active-probe refinement of detection;
  revisiting the tmux `terminal-features` passthrough if demand warrants.

## 8. Decisions recorded

- **Keep the inspectable `(url)` suffix by default, with an opt-out (Stage 2).**
  Following RFC 0013's "keep the URL visible or semantically inspectable," a
  producer that emits an OSC 8 link still shows the URL as trailing text by
  default, so the destination is visible on terminals that don't honor OSC 8 and
  auditable everywhere. Producers expose an opt-out for the clean-link look on
  terminals known to support it. The suffix is a *producer* concern; the
  renderer neither adds nor knows about it.
- **Suppress OSC 8 under tmux by default; `FLEURY_HYPERLINKS=1` overrides.** The
  renderer has no tmux awareness — suppression is done in detection (§ below).
  OSC 8 in tmux requires an explicit `terminal-features` opt-in on the user's
  part and is unreliable in the wild, so detection returns `false` whenever a
  multiplexer is detected, regardless of the outer terminal, unless the user
  forces it with `FLEURY_HYPERLINKS=1`.
- **Detection is env-derived, allow-list-based, default-deny.** An explicit
  `FLEURY_HYPERLINKS=0|1` wins outright. Otherwise a known-supporting terminal
  (via `TERM_PROGRAM` ∈ {iTerm.app, WezTerm, ghostty}, `VTE_VERSION` present,
  Kitty via `KITTY_WINDOW_ID`/`TERM=xterm-kitty`, Windows Terminal via
  `WT_SESSION`) enables it; anything unknown defaults to `false`. tmux
  suppression (above) is applied on top. This mirrors the existing
  glyph-tier/ambiguous-width detectors.

## References

- [OSC 8 hyperlink specification](https://gist.github.com/egmontkob/eb114294efdcd5adb1944c9f3cb5feda)
  (the community spec: parameters, `id=` grouping, security notes).
- RFC 0013 (`docs/rfcs/0013-capability-security-contract.md`) — capability model,
  `OutputSecurityPolicy`, OSC 8 scheme allow-list, "keep the URL inspectable."
- `docs/implementation/wire-protocol.md` — compatibility policy and the
  version-gated-encoding rule the Stage 2 v4 bump follows.
- In-repo carriers: `packages/fleury/lib/src/rendering/cell.dart`
  (`CellStyle.linkUri`), `.../rendering/ansi_renderer.dart` (emission),
  `.../terminal/capabilities.dart` (detection + projection),
  `.../terminal/capability_requirements.dart` (`osc8Hyperlinks` feature).
