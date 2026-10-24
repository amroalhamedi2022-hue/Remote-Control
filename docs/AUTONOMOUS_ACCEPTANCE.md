# Remote Control — Autonomous acceptance ledger (2026-10-23)

AUTOMATION_COMPLETE: BLOCKED

## This development batch
- Production fix: `flutter/lib/network/lan_discovery.dart` casts the typed socket stream before UTF-8 decoding, and consumes complete TCP response lines. This addresses the **actual** Windows Flutter analyzer error in CI run 39945211030 / 39945275996; a fragmented `PONG\n` no longer incorrectly fails the probe.
- Flutter widget/unit regressions: `flutter/test/lan_discovery_ping_test.dart` exercises fragmented and invalid PONG responses against a loopback TCP server.
- CI reliability: `.github/workflows/ci.yml` runs the Linux bootstrap through Bash, so a non-executable script file no longer produces exit 126.
- Analyzer hygiene: resolve all ten original analyzer findings, including two multiline guard clauses found by follow-up CI run 39946185155.
- This commit changes **production source**, a regression test, and CI invocation. No paid API or service.

## Verification and remaining requirements
| Gate | State | Evidence / what is missing |
| --- | --- | --- |
| Node discovery/pairing/video labs | PASS ON PREVIOUS SHA ONLY | CI 39945275996 node-protocol-tests success; must rerun on this commit. |
| Flutter analyze and widget tests | NOT TESTED ON THIS SHA | Run 39946185155 removed the Utf8Decoder type error but failed on two remaining info-level curly-brace lints; this patch addresses them. A new CI run on the latest SHA is required. |
| Android APK / Windows runner | NOT TESTED | Previous CI jobs failed before compilation, no verified artifact SHA. |
| Real Windows ↔ Xiaomi Pad 5 LAN/pairing | NOT TESTED | Needs physical devices and verified permission/consent. |
| H.264 Android viewer and real desktop capture | NOT TESTED | Existing Node synthetic-media lab is not device proof. |
| Android host / input / clipboard / files / audio / multisession | NOT IMPLEMENTED / NOT TESTED | Future roadmap gates M4–M8. |
| Security / design / performance | NOT TESTED | Custom lab pairing not approved for privileged access; master Liquid Fusion reference remains unchanged. |

**Next:** inspect CI on the new SHA, fix any further Flutter compilation errors, then obtain real APK and Windows bundle and validate on hardware. Never call the product complete from CI alone.

## 2026-10-23 — LAN-only boundary enforcement across Flutter and Node
- **Flutter production:** added `flutter/lib/network/lan_address_policy.dart` with explicit RFC1918 + IPv4 link-local allowlist (loopback only when opted into local testing). `LanDiscovery` rejects public-origin UDP packets, manual public IP probes and public TCP ping targets. `PairingLab` rejects public outbound pairing/preview and inbound connections from public source addresses before showing a pairing dialog.
- **Windows Node production:** `tools/lan_probe/protocol.mjs` exports the equivalent IPv4 policy, and manual `parseEndpoint` refuses public addresses. `host_presence.mjs` rejects nonlocal UDP/TCP sources, while `pair_agent.mjs` restricts incoming and outgoing pairing to local IPv4. Loopback remains enabled for Node's existing isolated integration tests; neither helper authenticates a peer or proves the route is physically on the same Wi-Fi (VPN/private routes still possible).
- **New regressions:** `flutter/test/lan_address_policy_test.dart` checks RFC1918 boundaries, link-local, public/special ranges, manual discovery refusal and public TCP ping refusal. `tools/lan_probe/agent.test.mjs` checks the same Node policy, including rejecting CGNAT/public/ambiguous addresses while retaining localhost test compatibility.
- **Commits (production and tests):** `c066e7d46748845810bbe639494fc9ac3213d023`, `77a9962d56c31ad8e3b1ad687d036fc7461ccc53`, `2dcbd833a9725072f340f0c0c72e623ffef2a808`, `08feb0dfad564c027c77e3917aa9c834d275e6b9`, `675272367e62125eb7969db6d7181674283da9ec`, `6f8d5f4035e11445ef8cf9d6132ca112288e2801`, `eedac7d7c3829425bd22cee1a4ccb636e9f03db7`, `f5ebfd5134c43153311a9959c81fae4e92b6bac0`.
- **PR:** https://github.com/amroalhamedi2022-hue/Remote-Control/pull/1. **Existing previous CI** run https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/39953196734 was green on **previous** source SHA, NOT proof of this patch.
- **PASS:** source/test changes committed to existing independent Remote Control PR; no changes to NetKit or main; no API costs, remote-control privileges or silent device permission changes.
- **NOT TESTED ON PATCH SHA:** Node/Flutter unit suite and Android/Windows builds on new source; no actual Windows/Pad 5 LAN capture, secure pairing interoperability, clipboard, input, files, audio or multi-session device tests. Current GitHub Actions results must be checked by run ID after the last commit. Do not mark this product LAN-secure or complete: source-IP allowlisting alone is not a firewall, route binding or a replacement for reviewed pairing and explicit screen permission.
- **Next:** verify current CI and artifact SHA; test real same-LAN Windows↔Android pairing, rejection on public/VPN routes and network interface changes, then replace experimental protocol with audited authenticated transport before any input/file permissions.

### Compiler-driven repair and CI cost control (2026-10-23)
- **Observed actual CI:** https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/39962239926 — Node protocol tests **PASS**; Android and Windows Flutter analyzer **FAIL** at `lib/network/lan_discovery.dart:205,207` because `InternetAddress.tryParse` returns nullable `InternetAddress?` and the helper-only guard did not promote it. This is a real analyzer failure, not a network or device failure.
- **Production fix:** commit `4c4e5ac553c2788796f832be405b178e319ca932` adds an explicit `address == null ||` guard before passing the value to `_send` and accessing `.address`. Await a successful current-SHA Flutter analyzer/build before marking PASS.
- **CI efficiency:** commit `070e4bae4c417212f9d45fc204819e883ff1ec46` limits `push` workflows to `main` while retaining PR checks, preventing duplicate full Android+Windows runner jobs on every review-branch push. No merge or release.
- **NOT TESTED on repair SHA:** final Android APK/Windows bundle verification and device pairing; old green CI must not be substituted.

## 2026-10-23 — Bounded Flutter LAN probe response (new production patch)
- **Observed prior CI failure:** run 39962239926 on SHA `4daba7a4...` passed Node protocol tests but failed Android/Windows Flutter analysis due to nullable `InternetAddress?` in `lan_discovery.dart:205,207`; a subsequent source revision already added an explicit null guard. Later runs were cancelled while successive commits landed; do **not** interpret cancellations as pass or fail of the newest source.
- **Actual production change:** `flutter/lib/network/lan_discovery.dart` replaces unbounded UTF-8/LineSplitter TCP `PONG` parsing with a **6-byte maximum**, strict `PONG\\n` or `PONG\\r\\n` parser and a 2-second timeout. The listener is cancelled after completion; it remains an unauthenticated reachability probe, not secure pairing.
- **Regression:** `flutter/test/lan_discovery_ping_test.dart` adds fragmented CRLF, trailing bytes, a 64 KiB no-newline payload and a timeout under an endless input stream, retaining real loopback TCP tests.
- **Implementation SHAs:** `0345c142904276a778f2a450bc8ca11cfbf1a287`, `6e467bd6a5270897d0e5a704aad913613b479bf6`, `7787114078aba98c284b54d60ee8567486aced3d` in existing PR #1, no main merge.
- **Status at ledger edit:** source and test changes committed, **Flutter analyzer/widget tests and Android/Windows CI for final SHA PENDING**; no real Android↔Windows pairing/capture/input/audio/files test, no approval for experimental lab cryptography or privileged control. Do not claim product readiness.
- **Next:** inspect latest CI for the final SHA and repair any analyzer/compiler failures; validate APK/Windows bundle hashes and then actual physical device consent, LAN-only routing and Liquid Fusion visual acceptance.

## 2026-10-23 — Expiring paired-session indicator (not control authorization)
- **Production:** `flutter/lib/security/pair_session_ledger.dart` now limits the ephemeral post-handshake paired-address indicator to ten minutes and 64 entries, evicts expired/oldest addresses, refreshes only on a new authenticated handshake and revokes all addresses associated with a forgotten fingerprint. `PairingLab` uses this ledger instead of an unbounded permanent in-memory map. This indicator is **not** a privileged session token and does **not** authorize input, screen capture, clipboard or file access.
- **Regression:** `flutter/test/pair_session_ledger_test.dart` checks exact TTL expiry, re-pair refresh, revoke, bounded eviction, no extension on reads and invalid arguments. Uses only Dart core APIs; no new dependency, paid service or license change. Master Liquid Fusion reference remains untouched.
- **Changed commits:** `108edbbb08aee8929078a7a58e4eda10181d947d`, `53c7bcab6d7fa9da1dbccc2792135abee28a2e2e`, `3401382daaa06714906a3d0c63baec4c2a037fc0`. PR #1 remains DRAFT; no main merge.
- **PASS (previous baseline only):** CI run `39970427152` completed Node protocol, Android and Windows build jobs on previous SHA `49a826836f149587d821a8583968855a36cadb67`; it does **not** verify this lease patch.
- **NOT TESTED (current lease SHA):** exact-SHA Flutter analyzer/widget tests and Android/Windows builds in run `39978184942` were pending at ledger edit. Physical Windows↔Pad 5 capture, QR pairing, audio/input/files/clipboard, per-operation permission consent and Liquid Fusion screenshot matching remain unverified.
- **Next:** verify exact final SHA in CI; do a separate attended physical-device recheck only when complete, and replace/audit bespoke lab handshake before enabling privileged remote controls.

### Exact-source CI result — PASS (2026-10-23)
- **PASS** GitHub Actions run [39978267095](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/39978267095) completed successfully on exact source+regression+ledger SHA `ba589f3933ca3fd5dbbc7360067f908b4a4790a7`.
- **PASS** Node protocol/lab tests, Flutter analyzer, new pairing-session TTL/revoke/eviction widget tests, Android Debug APK build + artifact structure/SHA validation, Windows Debug bundle build + PE/assets/SHA validation, per all three successful jobs.
- **PASS** Android artifact ID `12512970711`, artifact ZIP SHA-256 `f8b45885b9dc81ab3cbe70a1674bb93a347e2e09c12160203d81f62199b385cd`; Windows artifact ID `12513305001`, artifact ZIP SHA-256 `2565118a335c7bfbac628f96ba71c1bf97f8c651ce8dedec3482048d071ba821`. These are archive digests, **not** real-device runtime proof.
- **NOT TESTED:** physical Android↔Windows↔Android streaming and controls, Android MediaProjection/Accessibility consent, audio/files/clipboard/QR pairing, security audit of experimental pairing, multi-session and Liquid Fusion screenshot parity. PR #1 stays DRAFT; no main merge.
- This acceptance-only documentation commit does not change the source tested above; a new CI run on the documentation SHA, if triggered, is a separate gate.

## 2026-10-23 — Discovery label spoofing protection and independent artifact recheck
- **Production:** tools/lan_probe/protocol.mjs and flutter/lib/network/lan_discovery.dart now reject empty, overlong, bidi-direction-override, invisible separator and control-character names/platform labels in **unauthenticated UDP discovery**. Normal Arabic labels are accepted. This prevents deceptive peer display only; it is NOT pairing authentication, route isolation, or control authorization.
- **Regressions:** tools/lan_probe/agent.test.mjs and flutter/test/lan_address_policy_test.dart exercise spoofing/control negatives and valid Arabic names. Node and Flutter changes belong only to Remote Control PR #1.
- **FAIL then FIX:** GitHub Actions run https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/39995890644 failed Android Flutter analyzer on test/lan_address_policy_test.dart:11 prefer_interpolation_to_compose_strings; fixed the test string interpolation in source commit 05f75f1f05fed33d91d05bbcdd37175a3935dc72. Superseded/cancelled runs are not counted as passes.
- **PASS — current source head SHA:** 05f75f1f05fed33d91d05bbcdd37175a3935dc72; GitHub Actions run https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/39996298757 completed success for all three jobs: Node protocol tests, Flutter analyzer/widget tests + real Android Debug APK build, and Windows Flutter Debug bundle build with structural SHA verifier.
- **PASS — independently downloaded and checked ZIP bytes:** Android artifact ID 12519932244, ZIP SHA-256 4eeecd6e6be8aacc871301c8ad79da147b804c049c7848072b0856f49bb3e704; contained APK 159333591 bytes with SHA-256 0773d702c9215cc6738a34ed5ebdcfd632e908dc56e6112ff7a300ae4d451383. Windows artifact ID 12520141566, ZIP SHA-256 cfeb97e4e7481036a3a80391c3edfa55bff985419c0161055dc742486e205287; contained EXE SHA-256 5a7dfadab9d62a1f50644f64ad508e1976c6a77c5e43f55f22115ab9625df45b plus required Flutter DLL/assets. Both ZIPs passed CRC extraction check; embedded JSON evidence hashes match independently calculated binary hashes. These are DEVELOPMENT DEBUG builds, not final releases.
- **Artifact links:** https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/39996298757/artifacts/12519932244 and https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/39996298757/artifacts/12520141566 .
- **NOT TESTED / BLOCKED:** physical Windows/Pad 5/phone installation or execution; genuine screen capture/codec/audio/input/clipboard/file transfer; authenticated production pairing, QR, explicit MediaProjection/Accessibility consent and session revocation; LAN/VPN interface isolation, multi-session, Liquid Fusion screenshot parity, measured performance and independent physical-device acceptance. Do not label the project complete, merge PR #1 or disable the automation. No main writes, no paid APIs.
- **CI nuance:** Actions checks out GitHub's PR merge ref, combining the stated head with the base; the tested head is recorded above, not a claim that a standalone device build was independently installed. This ledger-only commit is newer than the verified code SHA.

## 2026-10-24 — Milestone R15-A: Android SAF picker → Windows Node receiver

**Scope and implementation:** `flutter/lib/security/file_transfer_lab.dart` implements bounded one-shot `FILE_OFFER / FILE_READY / FILE_CHUNK / FILE_ACK / FILE_END / FILE_OK` over the existing SAS-confirmed AES-GCM channel. Signed CLIENT_HELLO intent is `file` (separate from clipboard), and the Windows `pair_agent.mjs --listen --receive-file=<folder>` must independently ask for FILE approval. The Flutter File Transfer card now invokes the native Android picker, streams chunks with per-chunk acknowledgement, rehashes source and requires final receiver SHA-256 acknowledgement. Maximum file size 64 MiB, raw chunk size 3072 bytes. No broad Android storage permission and no unattended access. This does NOT implement Android receiving, folders via Flutter, screen/audio/control, or production security.

**Acceptance gates (exact-SHA evidence required):**

| Gate | State | Evidence / acceptance question |
| --- | --- | --- |
| R15-A1: signed file intent + scoped picker + sender protocol wired to actual UI | CODE COMPLETE — CI PENDING | `flutter/lib/main.dart`, `models/app_state.dart`, `security/pairing_lab.dart`, `security/file_transfer_lab.dart` |
| R15-A2: bounded chunk, SHA-256, refusal, wrong ACK, zero-byte regression | CODE COMPLETE — CI PENDING | `flutter/test/file_transfer_lab_test.dart`; `flutter test` and analyzer on exact head SHA |
| R15-A3: Node receiver contract and explicit local consent | CODE EXISTS — DEVICE NOT TESTED | `tools/lan_probe/file_transfer.mjs`, `pair_agent.mjs`, Node tests; run attended Android→Windows LAN |
| R15-A4: real Android SAF picker and Windows received file hash equality | NOT TESTED | Xiaomi Pad 5 and Windows 11, zero-byte, Arabic name, 64 MiB, revoke/deny/disconnect; independently compare SHA-256 |
| R15-A5: security, cross-platform integration, error/recovery and usability acceptance | NOT TESTED | independent crypto review, actual device/permission tests, benchmark and Liquid Fusion screenshots |

**Evidence summary at documentation time:** 0/5 accepted on hardware; source implementation present but new Flutter tests and CI are **PENDING** (never infer PASS from a previous SHA). Existing Windows Node lab already supports file receiving, but Android interoperability remains unproven. No APK/Windows build in this milestone: the next efficient gate is Flutter analyzer/unit CI; request a milestone build only if source checks pass and an attended cross-device test can follow.

**Licensing:** file_selector and crypto are Flutter/Dart-maintained BSD-3-Clause packages (see `docs/LICENSE_LEDGER.md`). No merge, main edits, paid services or external storage reads without picker consent.
