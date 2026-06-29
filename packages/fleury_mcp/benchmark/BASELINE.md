# `fleury_mcp` performance baseline

Recorded numbers for the M1/M2 hardening, so the "leading" claims are provable
and regressions are caught. Each metric measures **both** the pre-change path and
the new path in one run (both still exist), so "vs where we started" is honest
without checking out old commits.

- **Measure:** `dart run benchmark/mcp_benchmarks.dart` (`--json`, `--rows=N`)
- **Gate (CI):** `test/mcp_perf_gate_test.dart` — runs in `dart test`; a change
  that erodes a win below the thresholds fails. Byte metrics use absolute
  thresholds (deterministic); latency uses relative ones (robust to CI load).

## Numbers — dashboard of 80 rows (332 nodes), 2026-06-29

| Metric | Where we started | Now | Win | Gate |
| --- | --- | --- | --- | --- |
| **WS-1 delta push** — bytes to learn of + locate a 1-node change | full get_ui re-read: **23,505 B** | delta notification: **73 B** | **0.3% of a re-read (≈322× less)** | delta < 2% of full |
| …and to *act* on it (delta + read the one node) | 23,505 B | **136 B** | 0.6% of a re-read | act < 5% of full |
| **WS-9/WS-4 affordances** — valueSchema + untrusted marker on get_ui | baseline: 22,951 B | with: **23,505 B** | **+2.4%** (typed contract ~free) | overhead < 10% |
| **WS-2 capped settle** — wall-clock on a *ticking* app | uncapped (old, runs to timeout): **602 ms** | capped: **164 ms** | **3.7× faster** | capped < 0.7× uncapped |

Notes:
- The settle bench scales durations down (cap 150 ms / timeout 600 ms) to stay
  fast; the shipped config is `settleCap` 500 ms / `timeout` 2 s, so the
  real-world never-close case improves from ~2 s to ~500 ms (~4×).
- Delta savings scale with tree size: bigger UIs → larger `full re-read`, same
  tiny delta, so the ratio only improves. (`--rows=200` to see it.)

## Reliability tests (correctness-oriented, not metrics)

These guard the robustness claims; they assert pass/fail, not numbers.

| Area | Test | What it proves |
| --- | --- | --- |
| Wire robustness | `remote_semantics_test` — structural fuzz (1000 random envelopes) + byte-corruption (every truncation length + 200 bit-flips) + not-wedged recovery | the decoder never throws / never wedges on a hostile or buggy peer |
| Concurrency | `mcp_server_test` — mutex gate (a 2nd concurrent mutation can't dispatch until the 1st settles; **verified to fail if the mutex is bypassed**) | mutations serialize; no interleaved settle/revision corruption |
| End-to-end | `mcp_e2e_test` (subprocess), `mcp_host_e2e_test` (real binary over stdio), `mcp_showcase_e2e_test` (real showcase apps: discover-by-role, resize, type_text, set_value) | the full agent-driving path works against real apps |
| Rate limit | `mcp_server_test` — burst throttled + refills over (injected) time | a runaway agent is bounded; normal bursts pass |
| Stale guard | `mcp_server_test` — positional swap fails safe; value-tick + virtualized container don't livelock | no silent mis-target; no false-reject on live UIs |

## Gaps / future (not blocking)

- Per-revision node-index latency (WS-7) — `where(id:)`/`nodeById` are currently
  O(nodes) on the MCP side; a benchmark + gate belongs with WS-7.
- A soak/endurance loop and latency percentiles over the e2e path — would add
  reliability *metrics* on top of the correctness e2e above.
