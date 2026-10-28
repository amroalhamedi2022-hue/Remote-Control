# Remote Control — Live engineering status

Date: **2026-10-28**. Canonical repo: **https://github.com/amroalhamedi2022-hue/Remote-Control** (PUBLIC at owner's explicit direction).

## Operating contract

- **This normal ChatGPT conversation** manages development, source edits, tests, GitHub Actions, pull requests and milestone verification.
- **ChatGPT Work is not responsible for implementation** and need not be invoked for routine steps.
- No Codex, no access to other projects (including NetKit).
- Search for reputable, licensed, maintained implementations before reinventing cryptography, protocols, codecs or capture components.
- Visual source of truth: `design/LIQUID_FUSION_MASTER_REFERENCE.png` (original byte-for-byte).
- Never mark hardware/OS functionality verified from a screenshot or synthetic media test.

## Milestone gates

| Milestone | Verified evidence | Status |
|---|---|---|
| M0 Source migration | 77 baseline source/asset files, source + design checksums | **DONE** |
| M1 Android and Windows debug builds | Latest source checks pass; build jobs intentionally skipped in run 40620978659 | **PARTIAL** — source validated; current-head APK/Windows bundle not built |
| M2 Secure LAN/pairing | On-device offline trials; vetted transport; peer/key recovery tests | **LAB ONLY**, custom protocol not approved for privileged features |
| M3 Windows host → Android viewer | Real MSI desktop capture + Pad 5 playback + measured latency | **NOT VERIFIED** |
| M4 Remote keyboard/mouse | Opt-in host authorisation, safe input boundaries, device tests | **NOT STARTED** |
| M5 Android Host | MediaProjection, Accessibility and OEM consent evidence | **NOT STARTED** |
| M6 Bidirectional Android ↔ Android | Phone/tablet physical tests | **NOT STARTED** |
| M7 Clipboard/files/audio/multisession | Explicit permissions, independent integration tests | **NOT STARTED** |
| M8 Performance/security/release | Measured performance + real hardware + release gates | **NOT STARTED** |

## Evidence separation

- **Previously verified locally**: 31/31 Node lab protocol/media tests using local processes and synthetic FFmpeg input.
- **New v0.9 local unit tests**: 5/5 artifact validator tests, intentionally including malformed APK and fake Windows exe rejection.
- **Not verified yet**: Flutter analysis, compiled Flutter APK/Windows executable, real device LAN, interactive input, commercial-quality codec latency or security audit.
- CI only closes an individual build sub-gate after its artifact verifier passes and the binary is retrievable; it does NOT close device experience milestones.

## Next admin action

Inspect the v0.9 pull request's three GitHub Actions jobs; if any fails, read the failing job log, fix the code in this chat and rerun until the build is reproducible. Preserve architectural separation and the design master asset.


## 2026-10-28 — M85 viewer-disconnect lifecycle hardening

- **Production change:** MJPEG and experimental H.264 capture now watch socket disconnects while FFmpeg is silent, stop the child process, reject the capture as disconnected, and do not emit a successful completion.
- **Exact code-head evidence:** [CI 40620978659](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40620978659) passed on `ce109ffbbce609ad46f901973c98fff5fb856d52`: Node 102/102; stream/video 26 pass, 7 skipped; Flutter source/analyzer/widget checks pass; Windows capture lifecycle pass.
- **Specific regressions:** silent MJPEG disconnect PASS; silent H.264 disconnect PASS.
- **M1:** PARTIAL — source validation passes, but Android APK/Windows bundle jobs were skipped for this run. No build or device acceptance claimed.
- **M2/M3/M5/M7/M8:** remain LAB ONLY / NOT VERIFIED as appropriate. Real Windows↔Xiaomi Pad 5 pairing, MediaProjection/Accessibility, file/clipboard, audio and screen playback still require device evidence. FFmpeg/FFprobe integration tests were not run because the runner did not have those executables.
- **No merge, no main write, no root or permission bypass.**


## 2026-10-28 — M86 MJPEG encoder exit status

- Source: `b75080c926dee7e8e839051bf475d057e5f889e1`; final test head: `dbdeb64e113c19236f7dc209493c11668d2d4776`.
- The MJPEG sender now propagates a natural nonzero FFmpeg exit even when valid frames were already emitted; intentional policy stops are not misreported as encoder failures.
- Exact-head CI: [run 40627761134](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40627761134) — Node 102/102, stream/video 27 pass and 7 optional FFmpeg skips, Flutter 153 tests pass, Windows capture lifecycle 3/3 pass.
- M1 remains **PARTIAL**: source CI is green, but no APK/Windows bundle was built in this batch. M2/M3/M5/M7/M8 remain lab-only or not verified; physical pairing, file/clipboard, screen/audio, and permission lifecycle acceptance still required.
- Live Google Docs handoff: **SYNC FAILED**; this repository ledger is not a replacement for the live Drive document. No merge or `main` write.

## 2026-10-28 — M87 bounded preview-frame chunking

- **Source/test SHA:** `5e9ea06b849ea103f513aecb9c2f5f3a7982f073`; acceptance-ledger update: `439d8e071604a81e09dc9fd931c30b1d72a39eaa`.
- The preview receiver rejects a new frame header while the prior frame is incomplete and enforces fixed-size non-final chunks, preventing a 512 KiB frame from being represented as hundreds of thousands of tiny retained buffers.
- **PASS — CI:** [run 40633124181](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40633124181): Node protocol suite 102/102; streaming/video 28 PASS, 0 FAIL, 7 optional FFmpeg skips; Flutter and Windows capture lifecycle checks PASS.
- **NOT BUILT / NOT TESTED:** no APK/EXE was built for this lab parser change; physical Android↔Windows pairing, file/clipboard, screen/audio and MediaProjection/Accessibility remain unverified.
- Live Google Docs handoff remains **SYNC FAILED** because no authorized Docs write/read connector is available in this run. No merge or `main` write.



## 2026-10-28 — M88 viewer half-close lifecycle

- Source/test SHA: `20cb56919b3444a9c3317f86b2ca85dc9dec4882`.
- Exact-source CI: **PASS**, run [40638533763](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40638533763): Flutter source checks, Node protocol/stream tests and Windows capture lifecycle passed.
- Android APK / Windows bundle: **SKIPPED**; no build was warranted for this source-level lifecycle fix.
- Physical device acceptance: **NOT TESTED**; M2/M3/M4/M5/M6/M7/M8 remain open as previously recorded.
- Live Google Docs handoff: **SYNC FAILED**. No merge or `main` write.


## 2026-10-28 — M89 capture-lab status

- Latest source/test SHA: `3fe059622ecfa3346f87e3fc2a6b7061314602bd`.
- Viewer TCP half-close is now checked at the actual frame emission boundary as well as the idle watcher; regression prevents a JPEG from being sent after a peer FIN.
- Exact-head CI: [40644654563](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40644654563) — Node 102/102; stream/video 31 PASS, 7 optional FFmpeg skips; Flutter 153 tests and Windows lifecycle 3/3 PASS.
- Android APK / Windows bundle: NOT BUILT. Physical device acceptance: NOT TESTED. Experimental pairing/media security remains unapproved for production privileged control.
- Live Google Docs Handoff: SYNC FAILED (no authorized Docs write/read connector in this run).


## 2026-10-28 — M90 preview protocol integer validation

- Head: `959244066a7554b4ef1900b0a45910b6dd14acf4`.
- Preview frame part IDs/offsets and end IDs now reject JSON doubles such as `1.0` / `0.0`; regression tests cover all three fields.
- Exact-head CI: [40647301044](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40647301044) — Node 102/102; streaming/video 31 PASS, 7 optional FFmpeg skips; Flutter analyzer clean and 154 tests passed; Windows capture lifecycle 3/3 PASS.
- APK/Windows bundle NOT BUILT; device acceptance NOT TESTED. Real-codec optional tests remain skipped, not passed.
- Live Google Docs Handoff: **SYNC FAILED** (no authorized Docs write/read connector in this run).

## M91 — 2026-10-28 — Enforce exact TCP probe framing across stream events (PR #1)

- **Scope/branch:** `feature/build-reliability-v0_9` only; no merge or `main` write.
- **Functional change:** `LanDiscovery.readProbeReply` no longer reports success as soon as a valid-looking `PONG\\n` or `PONG\\r\\n` is seen. It requires EOF after the exact line, rejects any extra bytes in the same or a later stream event, and returns false if the peer keeps the connection open until the deadline. This is reachability-only protocol hardening, not authentication or remote-control authorization.
- **Regression coverage:** added a split-event trailing-payload test and a no-EOF timeout test. Existing fragmented PONG, CRLF, malformed, oversized and timeout cases remain.
- **Exact latest source/test commit available at recording:** [5a5badead5e78369ca0d144d9f1b1d022e5fb89b](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/5a5badead5e78369ca0d144d9f1b1d022e5fb89b).
- **CI:** **NOT VERIFIED** at handoff write time. The configured [Remote validation workflow](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/workflows/ci.yml) was inspected, but the available status/run query returned no checks for this push head. No CI PASS is claimed.
- **Build/device:** APK and Windows bundle **NOT BUILT** because this is a parser-only regression; physical Android↔Windows LAN probing **NOT TESTED**.
- **Security boundary:** no root, Accessibility/MediaProjection bypass, new dependency, paid API, or secret. LAN discovery and PONG remain unauthenticated reachability signals only; they cannot authorize files, clipboard, screen, audio or input.
- **Live Google Docs handoff:** **SYNC FAILED** — no authorized Google Docs write/read connector is exposed in this runtime; this repository ledger is not a substitute for the existing live Drive document.
