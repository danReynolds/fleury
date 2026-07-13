# Fleury serve/shell wire protocol — compatibility policy

**Status:** Normative. This is the source of truth for the wire-protocol
**compatibility policy**. The frame **codes and encodings** are defined by the
`FrameType` enum and the header comment in
[`packages/fleury/lib/src/remote/remote_protocol.dart`](../../packages/fleury/lib/src/remote/remote_protocol.dart);
keep this doc and that file in sync when frames change.

The wire framing carries a fleury app's rendered output and a remote display's
input between the app and a peer (`fleury serve`'s browser client, or
`fleury shell`) over any ordered, bidirectional byte stream — a Unix socket, a
WebSocket, etc.

## Not a public integration surface

**The wire is an internal transport between a fleury server and its own
embedded client. It is not a public, stable integration surface, and third
parties should not build against it.** The frame codes, payload encodings, and
protocol version may change between fleury releases **without a compatibility
shim** — prelaunch fleury ships no migration or compat layers. The supported,
stable integration points are the framework API and the semantic / agent
surfaces, not the raw wire.

This holds because the browser client bundle is **embedded in the fleury
binary**: a server and the client it serves always ship from the **same fleury
build**, so the two never need to negotiate encodings across versions.

## Frame envelope

All multi-byte values are big-endian.

```
┌──────────┬───────────┬──────────┐
│ 1 byte   │ 4 bytes   │ N bytes  │
│ type     │ length N  │ payload  │
└──────────┴───────────┴──────────┘
```

Five bytes of overhead per frame, so out-of-band events (a resize) travel
cleanly beside the input byte stream instead of being smuggled inside ANSI.

## Protocol version

Current version: **4** (`remoteProtocolVersion`). It is carried in the INIT
handshake as `v=<n>`; a peer that omits `v` is treated as **v1** (the legacy
ANSI host).

| Version | Added |
| --- | --- |
| v1 | Baseline ANSI host: INIT / INPUT / RESIZE / OUTPUT / BYE. |
| v2 | Structured host: PLAN, SEMANTICS, INPUT_EVENT (and the frames that support them). |
| v3 | SEMANTIC_ACTION_RESULT, and the app-side INIT echo (app → peer) so the client can detect version skew. |
| v4 | Optional OSC 8 link in the PLAN cell-style entry: spare set-mask bit 6 flags "has link" and, when set, a varint-prefixed UTF-8 URI rides after the two mask bytes (before the colors). Version-gated — a link-free style leaves bit 6 clear and writes no URI, so link-free frames stay byte-identical to v3, and the app emits links only to a peer that negotiated v>=4. |

## Frame types

Direction is informational — nothing in the encoder rejects an off-direction
frame, so test harnesses can inject either side. "Peer" is `serve` / `shell`;
"App" is the fleury application.

| Code | Frame | Direction | Purpose |
| --- | --- | --- | --- |
| `0x01` | INIT | Peer → App | Handshake: display size, color mode, glyph tier, image protocol, tmux passthrough, protocol version. Sent once before any input; echoed app → peer since v3. |
| `0x02` | INPUT | Peer → App | Raw stdin bytes (escape sequences, key chords, paste) — legacy byte input path. |
| `0x03` | RESIZE | Peer → App | Remote display resized (`cols`, `rows`). |
| `0x10` | OUTPUT | App → Peer | Raw ANSI render bytes — legacy ANSI host (retired-but-reserved; the structured host emits PLAN/SEMANTICS instead). |
| `0x11` | BYE | Either | Clean shutdown. Empty payload. |
| `0x12` | PLAN | App → Peer | Binary presentation plan — the structured host's per-frame output driving a visual surface. |
| `0x13` | SEMANTICS | App → Peer | UTF-8 JSON semantic snapshot of the rendered frame (accessibility + agent drivability). |
| `0x14` | INPUT_EVENT | Peer → App | Structured `TuiEvent` (key / mouse / paste / resize / composition) — the structured input path that replaces raw INPUT. |
| `0x15` | SEMANTIC_ACTION | Peer → App | The peer activates a node in its accessible tree (screen reader / agent driving semantics, not the visual grid). |
| `0x16` | INLINE_IMAGE | App → Peer | One inline image (browser surface), keyed by content-hash id; sent once before the first PLAN that places it, then referenced by id so bytes ride the wire only once. |
| `0x17` | CLIPBOARD_WRITE | App → Peer | Place text on the peer's (the user's) clipboard; answered by CLIPBOARD_RESULT. |
| `0x18` | CLIPBOARD_RESULT | Peer → App | Outcome of a CLIPBOARD_WRITE: written / denied / unavailable. |
| `0x19` | CARET | App → Peer | The focused editable's caret rectangle in cell space (for IME positioning), or absent when nothing editable is focused. |
| `0x1A` | SEMANTIC_ACTION_RESULT | App → Peer | Invocation status for a peer's SEMANTIC_ACTION: ran / disabled / not found / unsupported / threw. |
| `0x1B` | DEBUG_REQUEST | Peer → App | Pull-style debug query ("send me your recent `<kind>` records"); answered by DEBUG_RESPONSE. |
| `0x1C` | DEBUG_RESPONSE | App → Peer | The app's answer to a DEBUG_REQUEST: JSON records for the requested kind. |

## Compatibility rule

One rule, in two halves:

1. **Additive changes are safe and require no version bump.** *New frame types*
   and *optional trailing payload fields* are additive: a decoder skips unknown
   type discriminators and tolerates absent trailing fields, so peers one
   version apart interoperate. An older peer simply ignores a frame or field it
   doesn't know; a newer peer degrades to not showing that capability.

2. **Encoding changes are version-gated.** Changing the *cell or enum encoding
   inside an existing frame* is a breaking change: it requires a **version bump**
   and matching peers. This is safe precisely because of the same-build
   invariant above — server and client are never mismatched in practice.

Worked examples:

- SEMANTIC_ACTION's optional trailing `set_value` byte was added additively (no
  bump).
- v3 added SEMANTIC_ACTION_RESULT (`0x1A`) and the app-side INIT echo, both
  additive: a v2 peer skips the result frame and ignores the echo; a v3 client
  merely can't show action results or detect version skew against a v2 app.
- DEBUG_REQUEST / DEBUG_RESPONSE (`0x1B` / `0x1C`) are new frame types: an app
  predating them drops the request (unknown discriminator), and the peer treats
  a missing response as "unsupported".
- v4's optional OSC 8 link in the PLAN cell-style entry is a version-gated
  *encoding* change (a spare set-mask bit + a URI inside an existing frame), so
  it took a version bump rather than riding as an additive field. The app
  serializes links only to a peer that negotiated v>=4; a stale v3 client — whose
  decoder would misalign on the unexpected URI and lose stream framing — never
  receives them, and a link-free frame is byte-identical to v3 either way.
