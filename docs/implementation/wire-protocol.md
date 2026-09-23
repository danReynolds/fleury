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

The legal cross-package entry points are
`package:fleury/fleury_wire.dart` for platform-neutral frames and codecs, plus
`package:fleury/fleury_wire_io.dart` when a peer needs the Unix-socket
transport; their names and library docs make this unstable tier explicit. The
browser client bundle is
**embedded in the Fleury binary**, so a server and the client it serves ship
from the same build. Separately launched first-party peers, notably
`fleury_mcp`, must resolve a matching Fleury build. Both sides reject any
other version at INIT (see [Lockstep rule](#lockstep-rule)); there is no
cross-version compatibility lane.

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

The producer and decoder share the same payload limits: 16 MiB globally,
64 KiB for control frames, 1 MiB for input, and 8 MiB for document frames;
INLINE_IMAGE alone may use the 16 MiB global maximum.
The Unix-socket sender separately caps pending output at 64 MiB and 4096
frames; crossing either bound fails the session closed without dropping an
individual diff-bearing frame.

## Protocol version

The structured protocol version is **7** (`remoteProtocolVersion`). It is
carried in the INIT handshake as `v=<n>`; `fleury shell` negotiates
`remoteAnsiProtocolVersion` (**1**) because it is the ANSI terminal host, which
receives raw OUTPUT bytes instead of structured frames.

| Version | Introduced |
| --- | --- |
| v1 | The ANSI host: INIT / INPUT / RESIZE / OUTPUT / BYE. |
| v2 | The structured host: PLAN, SEMANTICS, INPUT_EVENT (and the frames that support them). |
| v3 | SEMANTIC_ACTION_RESULT, and the app-side INIT echo (app → peer). |
| v4 | OSC 8 links in the PLAN cell-style entry: set-mask bit 6 flags a link, and a varint-prefixed UTF-8 URI follows the two mask bytes, before the colors. |
| v5 | Original-box geometry for inline-image placements: PLAN flag bit 2 declares four varints after each placement (`boxCols`, `boxRows`, `boxOffsetCol`, `boxOffsetRow`). |
| v6 | The app-issued target token on SEMANTIC_ACTION for positional ids. |
| v7 | Fixed-shape frames: no optional trailing extensions. INPUT_EVENT keys always carry the position/synthesized pair, a paste always carries its phase byte (a segment then its id), SEMANTIC_ACTION always carries the token-presence byte, and every PLAN placement carries its window (flag bit 2 is gone). INIT requires `v`, `color`, `glyph`, `image`, and `tmux`; the optional params are validated rather than defaulted. |

The table is history, not a support matrix: an app and a structured peer speak
exactly the current version.

## Frame types

Direction is informational — nothing in the encoder rejects an off-direction
frame, so test harnesses can inject either side. "Peer" is `serve` / `shell`;
"App" is the fleury application.

| Code | Frame | Direction | Purpose |
| --- | --- | --- | --- |
| `0x01` | INIT | Peer → App | Handshake: display size, color mode, glyph tier, image protocol, tmux passthrough, protocol version. Sent once before any input; the app echoes its own to a structured peer. |
| `0x02` | INPUT | Peer → App | Raw stdin bytes (escape sequences, key chords, paste) — the ANSI host's input path. |
| `0x03` | RESIZE | Peer → App | Remote display resized (`cols`, `rows`). |
| `0x10` | OUTPUT | App → Peer | Raw ANSI render bytes for the `fleury shell` ANSI host; structured hosts emit PLAN/SEMANTICS instead. |
| `0x11` | BYE | Either | Clean shutdown. Empty payload. |
| `0x12` | PLAN | App → Peer | Binary presentation plan — the structured host's per-frame output driving a visual surface. |
| `0x13` | SEMANTICS | App → Peer | UTF-8 JSON semantic snapshot of the rendered frame (accessibility + agent drivability). |
| `0x14` | INPUT_EVENT | Peer → App | Structured `TuiEvent` (key / mouse / paste / resize / composition) — the structured input path that replaces raw INPUT. |
| `0x15` | SEMANTIC_ACTION | Peer → App | The peer activates a node in its accessible tree (screen reader / agent driving semantics, not the visual grid). Positional ids carry the app-issued target token observed by the peer so a recycled id cannot silently target another mounted contributor, and role/label/advertised-action changes on a reused contributor also invalidate the claim. |
| `0x16` | INLINE_IMAGE | App → Peer | One inline image (browser surface), keyed by content-hash id; sent once before the first PLAN that places it, then referenced by id so bytes ride the wire only once. |
| `0x17` | CLIPBOARD_WRITE | App → Peer | Place text on the peer's (the user's) clipboard; answered by CLIPBOARD_RESULT. |
| `0x18` | CLIPBOARD_RESULT | Peer → App | Outcome of a CLIPBOARD_WRITE: written / denied / unavailable. |
| `0x19` | CARET | App → Peer | The focused editable's caret rectangle in cell space (for IME positioning), or absent when nothing editable is focused. |
| `0x1A` | SEMANTIC_ACTION_RESULT | App → Peer | Invocation status for a peer's SEMANTIC_ACTION: ran / disabled / not found / unsupported / threw. |
| `0x1B` | DEBUG_REQUEST | Peer → App | Pull-style debug query ("send me your recent `<kind>` records"); answered by DEBUG_RESPONSE. |
| `0x1C` | DEBUG_RESPONSE | App → Peer | The app's answer to a DEBUG_REQUEST: JSON records for the requested kind. |

## Lockstep rule

1. **One version.** A structured peer and the app speak exactly
   `remoteProtocolVersion`. The app echoes its INIT to a structured peer; for
   any other structured version it sends that echo — so the peer can report
   the skew — and then fails the session closed. First-party peers reject an
   echo that does not match their own and send nothing but INIT until it does.
2. **Every encoding change bumps the version.** A new frame type, a new field,
   or a changed cell/enum encoding is a new version. There are no emission
   gates, no down-shifted shapes for an older peer, and no tolerance for a
   newer one.
3. **Decoders are strict.** An unknown frame type, an unknown enum value, an
   unknown flag bit, a missing required field, or trailing bytes are a
   protocol error. Every binary frame is fixed-shape: an optional field is a
   presence byte (or, for a paste, its phase) followed by its value, never an
   absent trailing extension. INIT's optional params (`images`, `hyperlinks`,
   `keyboard`, `provisional`, `debug`) mean "not declared" when absent and are
   validated when present.
