# Launch-hardening security audit (2026-07-08)

**Status:** Findings report (analysis only)  
**Date:** 2026-07-08  
**Tree:** branch `fleury-main-sync`  
**Companions:**  
- [launch-bug-audit-2026-07-08.md](launch-bug-audit-2026-07-08.md)  
- [launch-perf-audit-2026-07-08.md](launch-perf-audit-2026-07-08.md)  
- [launch-architecture-audit-2026-07-08.md](launch-architecture-audit-2026-07-08.md)  

**Primary sources:** RFC 0013, `packages/fleury/test/security/**`, serve/remote/sanitizer/clipboard/process code, live security-related test re-run (41 passed).

---

## Purpose

Assess Fleury’s **trust boundaries** for launch: what is untrusted, what sinks are privileged, which deployments are in-bar, and where the contract is incomplete. This is not a penetration test of production cloud hosting; it is a framework security review against the documented model (“untrusted text remains data”) and realistic launch deployments.

### Threat models in scope

| Model | Description | Launch expectation |
| --- | --- | --- |
| **TM-Local** | Developer runs a TUI on a real TTY; untrusted subprocess/LLM/log text; same user OS account | **In bar** — core product |
| **TM-Serve-loopback** | `fleury serve` on `127.0.0.1`; browser on same machine; same OS user | **In bar** for demos |
| **TM-Serve-LAN** | Serve bound off loopback (LAN/VPN); shared URL | **Optional**; must not silently look “safe” |
| **TM-Serve-public** | Internet-facing without reverse-proxy auth | **Out of bar** unless hardened — document as unsafe |
| **TM-Multi-user-host** | Hostile co-tenant on same multi-user Unix host | **Documented OS boundary** (socket/handle possession) — not full isolation |

Severity relative to these models (not “can we be CVE-proof on the public internet by default”).

---

## Executive summary

Fleury’s security architecture is **stronger than most TUI frameworks** on the axis it chose:

> **Untrusted text remains data** — controls never become terminal protocol, browser markup, or privileged effects unless they pass an explicit framework-owned API.

Evidence: central `sanitizeForDisplay`, security boundary tests, process/spawn log sanitization, browser `textContent` / HTML escape tests, process spawn as argv (not shell by default), serve origin policy, frame payload caps, grid size clamps, bridge single-session, spawn single-connect-per-socket.

**Launch risk is concentrated on the serve/remote trust model**, not on local cell paint:

1. **WS ownership = full app control** (keys, semantics, optional debug) — by design; token optional; missing Origin allowed.  
2. **Spawn mode has no session admission control** — fork bomb / resource DoS if reachable.  
3. **INIT has no timeout** — stuck app processes.  
4. **Debug wire default-on in non-product builds** — stacks/logs over WS.  
5. **Token in query string** — logs, Referer, browser history leakage.  
6. **Same-user Unix socket = full control** — documented; still a multi-user footgun.  
7. **Local path gaps** — OSC 52 under fd-capture (bug F6); CRLF double-enter interop.

**Local untrusted-output path (TM-Local)** is largely launch-ready if sanitizer stays on all text sinks and SB.9-class safety remains green.

### Priority-ordered findings

| P | ID | Title | Severity | Models |
| --- | --- | --- | --- | --- |
| P0 | SEC1 | Serve WS grants full UI control; auth is optional | **high** | LAN/public |
| P0 | SEC2 | Spawn: no max sessions / rate limit | **high** | LAN/public |
| P0 | SEC3 | Remote INIT unbounded → process leak | **high** | LAN/public |
| P0 | SEC4 | Debug wire on by default (non-product) over serve | **high** | LAN |
| P1 | SEC5 | Token via `?token=` query string | **medium** | LAN |
| P1 | SEC6 | Missing `Origin` allowed on WS upgrade | **medium** | LAN |
| P1 | SEC7 | Same-origin policy assumes `http://` | **medium** | HTTPS deploy |
| P1 | SEC8 | Unix handle/socket same-user trust boundary | **medium** | multi-user host |
| P1 | SEC9 | Peer can inject `SignalEvent` (session kill) | **medium** | serve peer |
| P1 | SEC10 | OSC 52 / clipboard under fd-capture + SSH | **medium** | local/SSH |
| P1 | SEC11 | Redaction is opt-in / heuristic for inspection | **medium** | serve semantics |
| P1 | SEC12 | 64 MiB frame cap + image count cap (not byte budget) | **medium** | hostile peer |
| P2 | SEC13 | `allow-origin=*` disables origin checks | **low** | misconfig |
| P2 | SEC14 | CellBuffer does not re-sanitize (contract) | **note** | author misuse |
| P2 | SEC15 | MCP / ACP out of this pass | **note** | deferred packages |
| — | SEC-S* | Strengths (sanitize, argv spawn, static 2-file serve, caps, tests) | **strength** | all |

---

## Baseline evidence (this pass)

| Check | Result |
| --- | --- |
| `test/security/**` + `text_sanitizer_test` + `remote_codec_test` + `serve_stale_handle_test` | **41 passed** |
| Prior serve-production-readiness claims (origin, payload cap, grid clamp, backpressure) | Re-verified in code paths below |
| Bug/perf audits | Cross-linked where security-relevant |

---

## Trust model (as designed)

### Privileged sinks

| Sink | Who may write | Gate |
| --- | --- | --- |
| Terminal control sequences | Framework presenters only | App text → `sanitizeForDisplay` first |
| OSC 52 / platform clipboard | `Clipboard` / `SystemClipboard` | Policy (`ClipboardWritePolicy`) |
| Subprocess / external editor | Explicit effect APIs | Argv preferred; shell opt-in |
| Browser DOM | Presenters | `textContent` / HTML escape; no innerHTML for cells |
| Native image protocols | Image widgets + encoder | Capability + framework path |
| Semantic actions / key injection | Local focus or **serve peer** | Serve = peer is the user |

### Untrusted sources (must stay data)

App state strings, files, subprocess stdout/stderr, stray `print`, markdown/model output, remote frame payloads (as content), semantic labels, log lines, spawn child logs.

### Explicit non-goals (documented)

- Isolating two untrusted users on one Unix host without OS sandboxing.  
- Making bare internet-facing serve “enterprise multi-tenant” without reverse proxy auth.  
- Full secret-scanning redaction of every string (hooks + opt-in flags, not DLP).

---

## Findings

### P0 — Must address for any non-loopback serve / multi-user URL

---

#### SEC1 — Serve WebSocket ownership is full app control; authentication is optional

| Field | Detail |
| --- | --- |
| **Severity** | **high** (LAN/public); **acceptable** on loopback with eyes open |
| **Class** | Design + operational footgun |

**What happens**

A successful `/ws` upgrade receives the full remote protocol: input events (keys, paste, mouse), semantic actions, clipboard effects on the structured path, and the (optionally redacted) semantic tree. Off loopback, the binary **warns** but still binds; `--token` is optional and only warned when missing.

```
// bin/fleury.dart — token optional; null ⇒ authorize all
bool _isAuthorizedWebSocketRequest(HttpRequest req, String? token) {
  if (token == null) return true;
  return req.uri.queryParameters['token'] == token;
}
```

**Assumption challenged**

“Same-origin browser defaults make serve safe enough for LAN demos.”

**First principles**

Origin checks stop *browser pages* from other sites (with caveats SEC6/SEC7). They do not stop: curl, scripts, other local processes, or non-browser clients. Without a token (or external auth), **network reachability = drive the app**. That matches ttyd-class tools, but must be loud in launch docs and preferably fail-closed off loopback for release builds.

**Recommended fix**

1. Off loopback: **require** `--token` (or `--i-understand-open-serve`) in non-debug builds.  
2. Document threat model in `fleury serve --help` and serving docs.  
3. Prefer reverse-proxy auth for anything beyond LAN.

---

#### SEC2 — Spawn mode has no concurrent session cap (process DoS)

| Field | Detail |
| --- | --- |
| **Severity** | **high** if serve URL is shared |
| **Class** | Resource exhaustion |

**What happens**

`fleury serve --spawn` starts a full app process per browser (warm standby + cold path). No max sessions, no rate limit. Tests explicitly allow multi-browser isolation.

**Assumption challenged**

“Token/origin make multi-user serve capacity-safe.”

**First principles**

Authentication without admission control still allows **authenticated DoS**: N tabs × Dart VM. On a laptop demo this is annoying; on a shared host it is a fork bomb.

**Recommended fix**

Hard cap (e.g. 1–4 default, configurable); 503 when full; document. Pair with SEC3.

---

#### SEC3 — Remote INIT handshake has no timeout

| Field | Detail |
| --- | --- |
| **Severity** | **high** with SEC2 |
| **Class** | Availability / resource leak |

**What happens**

`RemoteTerminalDriver.enter` awaits `_handshake!.future` with no deadline. Silence leaves the app blocked in enter. Spawn connect timeout exists; INIT timeout does not.

**Recommended fix**

Bounded INIT deadline; tear down process/session on failure.

---

#### SEC4 — Debug wire enabled by default in non-product builds over serve

| Field | Detail |
| --- | --- |
| **Severity** | **high** for shared demos; **low** for solo loopback |
| **Class** | Information disclosure |

**What happens**

`DebugConfig` defaults to enabled when not `dart.vm.product`. When enabled, `runApp` answers peer `DebugRequest` with frame stats, logs, and error stacks over the wire.

**Assumption challenged**

“`dart run` demos don’t export diagnostics unless the developer opts in.”

**First principles**

WS already owns the UI; debug adds **log and stack exfiltration** for typical JIT demos. LAN “share this URL” is exactly the risky path.

**Recommended fix**

Default debug wire off for remote sinks; require explicit `DebugConfig` / env; always off when `dart.vm.product`.

---

### P1 — Should fix or tightly document before launch

---

#### SEC5 — Token passed as URL query parameter

| Field | Detail |
| --- | --- |
| **Severity** | **medium** |
| **Class** | Secret leakage |

**What happens**

Client forwards `?token=` from page URL to `/ws?token=…` (`remote_client.dart`). Tokens appear in browser history, server access logs, Referer on subsequent navigations, and shoulder-surfing screenshots.

**Recommended fix**

Prefer `Authorization` header or first-message auth after WS open; short-lived tokens; document residual risk if query token remains for convenience.

---

#### SEC6 — Missing `Origin` header is allowed

| Field | Detail |
| --- | --- |
| **Severity** | **medium** |
| **Class** | Intentional + footgun |

```
if (origin == null || origin.isEmpty) return true;
```

Non-browser clients and some tools omit Origin. Documented as “origin stops cross-site **pages**.” Combined with optional token, any TCP client can connect.

**Recommended fix**

For off-loopback: require Origin **or** token; or require token always off-loopback (SEC1).

---

#### SEC7 — Same-origin check hardcodes `http://` scheme

| Field | Detail |
| --- | --- |
| **Severity** | **medium** (availability / footgun, not RCE) |
| **Class** | Deployment correctness |

Same-origin is built as `http://${Host}`. HTTPS reverse-proxy deployments fail WS unless `--allow-origin=https://…` is set. Operators may “fix” with `allow-origin=*` (SEC13).

**Recommended fix**

Honor `X-Forwarded-Proto` / config scheme; clearer 403 body.

---

#### SEC8 — Local shell/serve IPC is same-user possession

| Field | Detail |
| --- | --- |
| **Severity** | **medium** on multi-user hosts; **acceptable** on single-user dev machines |
| **Class** | Documented OS trust boundary |

`.fleury/handle` + Unix domain socket: any process as the same UID that can open the socket can attach. Stale-handle takeover is tested (good). No evidence of intentional cross-user auth.

**Recommended fix**

Document “do not run serve on shared multi-user hosts without isolation”; consider `0700` dir + restrictive socket mode if not already guaranteed by umask; refuse world-writable handle paths.

---

#### SEC9 — Remote peer can inject `SignalEvent` (session terminate)

| Field | Detail |
| --- | --- |
| **Severity** | **medium** (within WS trust model) |
| **Class** | Protocol surface |

Codec encodes/decodes signals; unclaimed `SignalEvent` exits the app. Intentional for host shutdown, but any WS peer can kill the session. Browser client may not send it; protocol allows it.

**Recommended fix**

Policy: ignore peer-synthesized signals unless authenticated admin channel; or document as “peer is supervisor.”

---

#### SEC10 — Clipboard / OSC 52 path under fd-capture (and SSH)

| Field | Detail |
| --- | --- |
| **Severity** | **medium** (integrity of “copy succeeded”) |
| **Class** | Confirmed wiring bug (bug audit F6) |

Default `SystemClipboard` uses `stdout.write` for OSC 52 while frames use the real TTY handle under fd capture. SSH skips platform tools → OSC 52 is the only remote path and can be swallowed.

**Security reading**

Not classic injection; **false success** on clipboard write can lead users to paste secrets into the wrong place or believe redaction/copy policy applied when it did not.

**Recommended fix**

Wire OSC 52 through driver/terminal handle; regression under fd-capture.

---

#### SEC11 — Semantic redaction is opt-in and heuristic on inspection export

| Field | Detail |
| --- | --- |
| **Severity** | **medium** for serve/agent exfiltration of secrets in UI state |
| **Class** | Policy completeness |

Inspection redacts when `redactedValue` / `obscureText` / `clipboardRedacted` flags are set; sensitive **state keys** matching `value|text|secret|password|token|query` are redacted when those flags apply. Password inputs set obscure/redact flags. **App authors must mark secrets.** Unmarked tokens in labels/values still ship on the wire/semantics tree.

**Recommended fix**

Launch docs: “semantics are visible to the serve peer”; require PasswordInput / redaction flags for secrets; consider default-redact for debug exports.

---

#### SEC12 — Payload/image resource bounds are large / incomplete

| Field | Detail |
| --- | --- |
| **Severity** | **medium** (DoS, not RCE) |
| **Class** | Resource limit |

| Control | Limit | Note |
| --- | --- | --- |
| Frame payload | **64 MiB** | Large; rejects oversize |
| Grid size | **4000×4000** | Clamped |
| Pending browser pre-pair | payload cap | Present |
| Inline images | **512 ids**, not total bytes | Memory pressure possible |
| Spawn sessions | **none** | SEC2 |

**Recommended fix**

Lower defaults for non-loopback; image **byte** budget; session cap.

---

### P2 / notes

---

#### SEC13 — `--allow-origin=*` disables origin checks

Operator footgun. Acceptable for advanced use; pair with required token off-loopback.

---

#### SEC14 — `CellBuffer` does not re-sanitize

Documented: widgets must pass `sanitizeForDisplay`. Renderer trust boundary is intentional for performance. Author bypass is an app bug; framework widgets and process paths cover the common case. Conformance tests + security matrix row help.

**Do not** “fix” by double-sanitizing every cell write without measuring paint cost.

---

#### SEC15 — MCP / ACP / public multi-tenant

Out of scope for this launch audit. `fleury_mcp` and future `fleury_acp` need their own trust-boundary reviews before those packages are launch claims.

---

## Strengths (do not regress)

| ID | Strength | Evidence |
| --- | --- | --- |
| SEC-S1 | **Central sanitizer** collapses escape-led sequences (OSC 52/8, DCS, APC), not just ESC byte | `text_sanitizer.dart`; sanitizer + boundary tests |
| SEC-S2 | **Widget/process/spawn/output-capture paths sanitize** | process_task, spawn logs, Text/TextInput/Markdown paths, security tests |
| SEC-S3 | **ProcessTask / spawn use argv**, shell opt-in | `runInShell` default false; effects security tests with hostile paths |
| SEC-S4 | **External editor** passes path as argument / quoted shell env | effects_security_boundary_test |
| SEC-S5 | **Serve static surface is two files** (`/`, client JS) — no arbitrary path serve | `_serveStaticAsset` 404 else |
| SEC-S6 | **WS origin policy** (same-origin default + allow list) | serve integration tests |
| SEC-S7 | **Frame size/payload clamps + codec rejection** | remote_protocol / remote_driver |
| SEC-S8 | **Backpressure** on Unix/WS pumps; producer gate under stall | transport + frame_driver |
| SEC-S9 | **Bridge single-session**; spawn single accept then close listen | spawn.dart comments + code |
| SEC-S10 | **Browser cells via textContent / escaped HTML** | browser_security_boundary_test |
| SEC-S11 | **Markdown links** restricted schemes (http/https/mailto) | markdown_text.dart |
| SEC-S12 | **Stale handle** detection and takeover path tested | serve_stale_handle_test |
| SEC-S13 | **Security matrix + owner tests** in repo | `test/security/README.md` |
| SEC-S14 | **Capability/policy framing** (RFC 0013) | diagnose, clipboard policies, image fallbacks |

---

## Threat-model verdicts

| Model | Verdict | Why |
| --- | --- | --- |
| **TM-Local** | **PASS for launch** with residual SEC10 clipboard wiring | Sanitize + lifecycle + process argv solid; keep SB.9 green |
| **TM-Serve-loopback** | **PASS with caveats** | Same-user OS boundary; no token needed if you trust local processes; debug wire still noisy (SEC4) |
| **TM-Serve-LAN** | **FAIL until SEC1–SEC4 hardened** | Optional token, open spawn, INIT hang, debug default |
| **TM-Serve-public** | **FAIL** without reverse-proxy auth + caps + product build | Not a launch claim |
| **TM-Multi-user-host** | **FAIL isolation** | Same-UID socket possession — document only |

---

## Assumption validation

| Assumption | Verdict |
| --- | --- |
| Untrusted text cannot become terminal protocol via normal widgets | **PASS** (if authors use framework text widgets / process APIs) |
| Cell buffer is a hard re-sanitize boundary | **FAIL** (by design: trust upstream sanitize) — documented |
| Serve is safe on loopback without token | **PASS** only under single-user machine trust |
| Serve is safe on LAN with warnings only | **FAIL** |
| Origin validation alone is a network ACL | **FAIL** (SEC6) |
| Redaction protects all secrets on the wire | **FAIL** without author flags |
| Resource exhaustion is bounded on serve | **PARTIAL** (payload/grid yes; sessions/images partial) |
| Security regression surface is tested | **PASS** for matrix rows; re-run 41 tests green this pass |

---

## Cross-links to other audits

| Other audit | Security reading |
| --- | --- |
| Bug F6 OSC 52 | SEC10 |
| Bug F8/F9 spawn/INIT | SEC2/SEC3 |
| Bug F15 debug wire | SEC4 |
| Bug F14 HTTPS origin | SEC7 |
| Perf P2 serve full scan | Availability under load (not confidentiality) |
| Arch multi-surface | WS peer is a full user of the app |

---

## Prioritized recommendations

### Must before LAN/public serve claims

1. **Require token (or hard refuse) off loopback** in release/serve defaults (SEC1).  
2. **Session cap + INIT timeout** on spawn (SEC2/SEC3).  
3. **Debug wire off** for remote unless explicit opt-in (SEC4).  
4. Document TM-Local vs TM-Serve threat models in serve help + website.

### Should before general launch

5. Token not only in query string (SEC5).  
6. OSC 52 via terminal handle (SEC10).  
7. Image byte budget + tighter non-loopback defaults (SEC12).  
8. Peer SignalEvent policy (SEC9).  
9. Redaction guidance for secret fields (SEC11).  
10. HTTPS same-origin / forwarded proto (SEC7).

### Maintain (do not regress)

11. Sanitizer corpus + security matrix tests on every PR that touches sinks.  
12. Argv-not-shell defaults.  
13. Two-file static serve surface.  
14. Codec/grid clamps and backpressure.

### Explicit non-claims for launch copy

- “Multi-tenant safe serve”  
- “Internet-ready without a reverse proxy”  
- “Automatic secret redaction of all UI text”  
- “Cross-user isolation on shared Unix hosts”

---

## Suggested sequencing

```
1. Document threat models + fail-closed off-loopback token policy
2. Spawn max sessions + INIT timeout
3. Remote debug opt-in only
4. Fix OSC 52 wiring (shared with bug audit)
5. Token transport hardening
6. Resource budgets (images, lower WAN defaults)
```

---

## Related documents

| Doc | Role |
| --- | --- |
| [RFC 0013](../rfcs/0013-capability-security-contract.md) | Capability + security contract |
| [test/security/README.md](../../packages/fleury/test/security/README.md) | Boundary matrix + owner tests |
| [serve-production-readiness.md](serve-production-readiness.md) | Serve hardening narrative |
| [workstreams/terminal-capability-security.md](workstreams/terminal-capability-security.md) | Workstream history |
| Launch bug / perf / architecture audits (2026-07-08) | Companion findings |

---

## Method note

Code review of serve, remote codec/driver/spawn, sanitizer, clipboard, process/editor effects, semantics inspection redaction, and browser security tests; re-ran the security-tagged suites (41 pass). No adversarial internet red-team or multi-user OS lab in this pass — residual multi-user and public-serve claims remain **unvalidated** and should stay out of launch marketing.
