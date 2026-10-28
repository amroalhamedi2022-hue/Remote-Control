# LIVE HANDOFF — Remote Control (Android + Windows)
**Updated:** 2026-10-28  
**Purpose:** Continue from the current implementation and validation evidence; do not restart the project.

## Repository and active review line
- Repository: https://github.com/amroalhamedi2022-hue/Remote-Control
- PR #1: https://github.com/amroalhamedi2022-hue/Remote-Control/pull/1
- Active branch: `feature/build-reliability-v0_9`
- PR #1 remains Draft/unmergeable. No auto-merge, no `main` write, and no branch mixing.

## Latest verified milestone — M103 final verification (2026-10-28)
**Goal:** Harden LAN discovery ingress and repair desktop receive staging validation.

- Discovery source-port enforcement: [31dc85ba](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/31dc85ba2db774ef4a2bc4594b9fc034e04634e0); final test/source head is superseded by the final verified head below.
- Desktop receive-staging repair: [70036111](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/7003611178d397b0b949a89e7be42f416b4820c7) removed a malformed duplicate tail; [3356d005](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/3356d005317263991af0dc6b65b332d845d02334) restored full file metadata/hash checks and queued-write barrier.
- Final source/test head: [3356d005](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/3356d005317263991af0dc6b65b332d845d02334).
- Exact-head CI: **PASS**, [CI 40747424353](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40747424353). Flutter analyzer/widget tests, Node protocol tests and Windows capture lifecycle passed.
- Android SAF policy tests, Android APK build and Windows debug bundle were skipped in this workflow; no APK/EXE was produced.
- Physical Android↔Windows acceptance: **NOT TESTED** — discovery, authenticated pairing, file transfer, clipboard, screen/audio mirroring and real control remain open.
- Discovery is untrusted reachability metadata; it does not authenticate or authorize a session.

## Product scope that must remain
- LAN-only Android ↔ Windows connectivity; no external relay/server by default.
- QR/manual pairing with explicit trust and session authorization.
- Reliable file transfer and clipboard transfer, with bounded writes, integrity checks and safe cancellation.
- Screen and audio mirroring and real input control only through supported OS APIs and user-granted permissions.
- Windows capture lifecycle and Liquid Fusion UI.
- **No root** and no bypass of Android MediaProjection, Accessibility or Windows security/consent boundaries.

## Acceptance gates
| Gate | Status | Evidence / next action |
|---|---|---|
| M103 source repair + regression tests | PASS | [source/test head](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/3356d005317263991af0dc6b65b332d845d02334) |
| Exact-head CI | PASS | [40747424353](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40747424353) |
| Flutter analyzer/widget tests | PASS | See exact-head CI |
| Node protocol tests | PASS | See exact-head CI |
| Windows capture lifecycle | PASS | See exact-head CI |
| Android SAF policy tests | SKIPPED / NOT TESTED | Run where supported |
| Android APK and Windows bundle | NOT BUILT | Build only for named device acceptance or final delivery |
| Real Android↔Windows LAN discovery | NOT TESTED | Validate interface/port changes and same-LAN operation |
| Authenticated QR pairing/session authorization | NOT ACCEPTED | Discovery must never imply trust; test replay/invalid pairing and revocation |
| File + clipboard transfer | NOT TESTED on devices | Verify size/hash, cancellation, overwrite consent and cleanup |
| Screen/audio mirroring + input control | NOT TESTED on devices | Respect MediaProjection/Accessibility and Windows consent; no root |
| Production security approval | NOT APPROVED | Lab cryptography/protocols are not production approval |

## Next work, in order
1. Recheck CI on the exact active PR #1 head before making new claims.
2. Exercise receive staging with concurrent chunks, quota boundaries, hash mismatch, cancellation and cleanup in CI.
3. Run Android↔Windows LAN acceptance with recorded OS/device versions, logs, file hashes and explicit PASS/FAIL.
4. Build Android APK and Windows bundle only when needed for that device test; retain artifact URLs and SHA-256.
5. Continue authenticated pairing and session lifecycle before treating file/clipboard/screen/audio/input features as production-ready.

## Delivery policy
- No routine hourly APK/EXE builds. A package must serve a named engineering/device test or final handoff.
- Keep compile, artifact verification and physical-device acceptance as separate gates.
- Final delivery requires a verified Android APK and Windows EXE/bundle artifact, SHA-256 for each, build logs, and device acceptance evidence.
- Free tools only; review open-source licenses/security before new dependencies.
- Update this handoff after each completed development batch with dated milestone, source/test SHA, CI links, build/device evidence and remaining gates.
