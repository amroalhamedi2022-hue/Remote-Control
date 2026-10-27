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


## 2026-10-25 — M7 laboratory milestone: Dart receives encrypted Node file frames transactionally

**Scope:** PR #1 only; no main/NetKit edits.
**Functional outcome:** Dart now has the receiver half of the Node `FILE_OFFER → FILE_READY → FILE_CHUNK/ACK → FILE_END/FILE_OK` protocol. User consent precedes staging; strict filename/size/SHA-256/base64/sequence/budget checks precede acknowledgement; chunks hash incrementally and go to a **private transactional sink**. The sink commits only after the final digest matches; rejection and failures abort staging. The caller must supply an already authenticated SAS-confirmed file-intent channel and an OS-specific atomic staging adapter. No unapproved disk writes are performed by this module.

**Source:** `flutter/lib/security/file_transfer_lab.dart`, `flutter/test/file_transfer_lab_test.dart`. New tests cover valid bytes, denial, wrong sequence, oversized chunk, malformed base64, bad digest, failed commit, and invalid offer.

**Acceptance gate (6 checks):**
1. Receiver state machine and streaming SHA implemented: **PASS (source inspection)**.
2. Denial/negative-path regression scenarios committed: **PASS (source inspection)**.
3. Flutter analyzer and tests on exact SHA: **NOT TESTED** until https://github.com/amroalhamedi2022-hue/Remote-Control/actions completes.
4. Native Windows atomic file staging adapter: **NOT TESTED / not integrated**.
5. Android SAF destination/commit adapter and Flutter UI wiring: **NOT TESTED / not integrated**.
6. Physical Android↔Windows LAN transfer, signed consent, file hashes: **NOT TESTED**.

**Boundary:** This is protocol/transport **lab interoperability**, not production remote access. Never infer actual Android SAF/Windows file transfer or audited encryption from passing Dart tests. No APK/EXE build was requested for this source-only gate.

## 2026-10-25 — M7 Android SAF attended inbound FILE_OFFER (native integration)

**Scope:** PR #1 branch `feature/build-reliability-v0_9` only; no NetKit PR #6/#7 or main edits. This milestone extends the existing Windows inbound receiver to Android, without broad storage permissions, root, or unattended writes.

**Implementation:** `flutter/lib/security/android_saf_staging.dart` provides a MethodChannel-backed `LabReceiveStaging`; `android_overlay/app/src/main/kotlin/com/example/liquid_remote_control/MainActivity.kt` implements per-file `ACTION_OPEN_DOCUMENT_TREE`, private cache staging, bounded 3072-byte chunks, native SHA-256 verification, SAF temporary document write/readback, and unique `Received-*` rename. `pairing_lab.dart` and `main.dart` route a SAS-confirmed signed `intent=file` to an explicit Android consent dialog and fresh folder picker. Both bootstrap scripts install the versioned Kotlin overlay. Failed picker or staging setup now sends `FILE_DENIED` before `FILE_READY`.

**Critical limitations:** Android DocumentsProviders do not guarantee atomic file publication. A temporary `.part` document can be visible during the final copy; if readback/rename/delete is unsupported, the transfer fails, and cleanup may fail on a hostile provider. The custom pairing protocol remains a laboratory protocol, not independently audited production security. Android↔Android file transport, permission revocation, provider interoperability and physical devices have NOT been accepted.

**Acceptance matrix (8 independent gates; code presence is not device acceptance):**

| Gate | State | Evidence or required verification |
| --- | --- | --- |
| A1 Native Android SAF adapter, bounded private cache and SHA/readback/rename logic present | PASS (source only) | `android_overlay/.../MainActivity.kt`, `flutter/lib/security/android_saf_staging.dart` |
| A2 Explicit per-file consent and picker in signed paired channel; no all-files permission | PASS (source only) | `flutter/lib/main.dart`, `flutter/lib/security/pairing_lab.dart` |
| A3 Negative-path Dart regression tests added (cancel, bad chunks, staging failure, abort) | PASS (source presence) | `flutter/test/android_saf_staging_test.dart`, `flutter/test/file_transfer_lab_test.dart` |
| A4 Flutter analyzer + Dart/Node tests on exact new head SHA | NOT TESTED (new CI not yet confirmed) | inspect GitHub Actions for the final PR #1 head; do not reuse older PASS |
| A5 Android Kotlin bridge compiles into verified debug APK | NOT TESTED (targeted CI build requested) | `.github/workflows/ci.yml` job `android-saf-milestone-build`; record APK SHA-256/artifact only after success |
| A6 Real SAF providers: local/cloud, Arabic name, zero bytes, 64 MiB, deny/revoke/crash, rename/readback failure | NOT TESTED | Xiaomi Pad 5 Android hardware logs and independent SHA-256 |
| A7 Real Android↔Windows and Android↔Android LAN transfer, offline and permission rejection | NOT TESTED | physical devices; host and receiver hashes must match |
| A8 Release readiness, independent security review, MediaProjection/control/visual/performance completeness | FAIL | major product scope remains unimplemented or unverified |

**Count at this source checkpoint:** 3 PASS (source evidence), 4 NOT TESTED, 1 FAIL. Prior [CI #40150631263](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40150631263) **FAILED** on redundant Dart import at the earlier `f4389fe` head; that import was removed. No successful CI run has yet been observed for the newer source head. Targeted Android build is justified because the new Kotlin `MainActivity` is not checked by Flutter analyzer. Do not claim APK/Windows artifacts or device acceptance until proven.


## 2026-10-25 — M12: Stop/revoke guarded file transfer (pending exact-SHA CI)
- Production: signed-file-intent Dart sender and receiver now accept a session-lifecycle guard. Check after approval, after chunk ACK, after native staging allocation/write, and immediately before file publication. PairingLab supplies its existing ticket lifecycle, so Stop invalidates a transfer without trusting a late consent/staging result.
- Regression: revoked sender cancels before FILE_END; late native staging aborts without FILE_READY; revoked slow write aborts without ACK or publish; pre-revoked session does not request consent.
- Security boundary: cooperative checks, not OS-level interruption. A native SAF commit already in progress cannot be rolled back atomically across all providers. Real-device Stop/revoke during publish and cross-device LAN remain NOT TESTED. No new package or paid API; reviewed Dart async cancellation behavior.
- Gate at commit: source patch PRESENT; Flutter analyzer/tests and Android/Windows binaries NOT TESTED on this SHA; real hardware NOT TESTED; final release FAIL. Update PR with exact-SHA CI results.

### M12 security follow-up (2026-10-25)
- `PairingLab.revoke(fingerprint)` now stops an active session with that fingerprint BEFORE removing its persisted trust pin. The Stop invalidates the lifecycle ticket, closes the active socket/listener, and prevents an in-flight transfer from silently re-pinning a revoked peer. Listener restart requires explicit user action. This is cooperative application-level revocation; native SAF commit already underway may still publish and requires device testing.
- The in-flight peer fingerprint is set only after signed hello identity verification and cleared on session exit. Exact-SHA Flutter CI required; no binary/device claim from source changes alone.

### M14 — One-shot file cancellation parity and late native commit acknowledgement (2026-10-25)
- Scope: Windows Node file sender and Flutter Android/Windows file receiver, on the existing signed-intent AES-GCM lab channel. No new dependencies, no paid APIs, no main merge.
- Production: Node sender now emits best-effort authenticated FILE_CANCEL after FILE_READY on any local failure before FILE_END, matching the Dart sender. Receiver already aborts its private staging on FILE_CANCEL. Never send cancellation after FILE_END because publication may have happened.
- Production: Dart receiver rechecks active pairing generation immediately after native commit and before FILE_OK. If revoked during an uncancellable SAF commit, the receiver suppresses success acknowledgement; a file may still have been published and cannot be assumed rolled back.
- New negative regressions: Node progress failure and invalid chunk ACK both cancel promptly; a bad final ACK after FILE_END does not send misleading cancel; Dart revocation during a delayed commit never sends FILE_OK.
- Gate on source change: code and regressions PRESENT. Exact-SHA Node/Flutter CI PENDING, Android/Windows builds NOT RUN for this protocol-only change, physical Windows↔Pad 5/phone LAN file transfer NOT TESTED, production cryptography audit NOT TESTED, final delivery FAIL.
- Review: reuses existing Node standard-library fs/crypto and Flutter crypto/file_selector dependencies already listed in LICENSE_LEDGER; no external implementation copied. Follow-up: verify CI, test real device Stop/revoke during SAF publish, observe cleanup and whether the provider publishes despite revoke.

## 2026-10-26 — M42: Bounded file-transfer channel sends (targeted device build)

- **Scope:** PR #1, branch `feature/build-reliability-v0_9`; no main or NetKit changes.
- **Functional change:** `sendLabFile` and `receiveLabFile` now apply a configurable positive `sendTimeout` (default 60 seconds) to each `FileTransferChannel.send`. Timeout bounds the caller's wait; it does **not** cancel the underlying Future or guarantee that a frame was not delivered. In particular, after `FILE_END` send is attempted, the sender no longer emits `FILE_CANCEL` on timeout because the receiver may already have received the final frame and published the file.
- **Regressions:** stalled `FILE_CHUNK` send times out and attempts best-effort cancellation; stalled `FILE_ACK` send times out and aborts private staging; stalled `FILE_END` send times out without a potentially contradictory `FILE_CANCEL`.
- **Source CI:** exact source/test SHA `414e9af40092ec304cc3202cf8f8c08e147296d7`, run [40319394869](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40319394869): **PASS** — Flutter analyzer/widget/unit tests (112 passed), Node LAN/protocol tests, and Windows capture-lifecycle tests.
- **Targeted package build:** **PASS** on exact build SHA `608eb5a73519248732ad83e24e641e35613101e0`, GitHub Actions run [40319625103](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40319625103). Flutter analyzer/widget/unit tests: **112 passed**; Node LAN/protocol suite and Windows capture-lifecycle suite: **PASS**. Android Debug APK structure/SHA verifier: **PASS**. Windows Debug bundle PE/assets/SHA verifier: **PASS**.
- **Artifacts (expire 2026-11-09):** Android artifact ID `12649240341`, ZIP SHA-256 `31e7883caf84f562e50111b5a303eaaa9bb7f6c1be5e8f952a460966e34dae8c`, APK SHA-256 `a525bf6de67a9a139ab4ca460bc9e6203ce1253e43bf650950435520c4ade647`; Windows artifact ID `12649145451`, ZIP SHA-256 `cd7fa407788ec2f23ae85ad82d102bbfaac4cd9ac0a77f7def99e1f2ce58adc9`, EXE SHA-256 `d0fc6dc9389fb2c2ff132dfe11f1bf56e2f617f10e9137a1d9f7356f81915ad6`.
- **Physical Android↔Windows transfer, interruption/revoke, and final-file SHA-256 equality:** **NOT TESTED**.
- **Boundary:** timeout alone is not transport cancellation. A caller still needs to revoke/close the active session/socket on a hard abort. Lab pairing cryptography remains experimental; no production security approval.



## M43 — Fail-closed abort for stalled encrypted file-transfer sends (2026-10-26)

**Branch:** `feature/build-reliability-v0_9`  
**Source/test head:** `ab6daa744689dec67cd484fb24c13baa8c0b1fc1`  
**CI:** [run 40324836776](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40324836776) — **PASS**.

### Functional change
- Added the optional `AbortableFileTransferChannel` contract.
- The production `_SealedChannel` now implements synchronous abort by marking the channel terminal and destroying its underlying socket.
- On a send timeout, sender/receiver code aborts an abortable transport. The sender no longer tries to send `FILE_CANCEL` over the same channel after that send has timed out; this avoids racing a still-pending write or triggering a concurrent sealed send.
- Receiver staging is still aborted on an ACK-send timeout; a timeout during `FILE_END` does not generate a contradictory cancel because the peer may already have published the file.
- Regression fixtures now assert transport abort and the absence of a cancel frame after a timed-out chunk send.

### Verification
- Flutter analyzer: **PASS — no issues found**.
- Flutter widget/unit suite: **PASS — 112 tests**.
- Node LAN/pairing/media protocol suite: **PASS — 24 passed, 0 failed, 7 skipped**.
- Windows capture lifecycle suite: **PASS**.
- An intermediate CI run [40324612070](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40324612070) failed on an unused timeout flag in the receiver helper; removed the unused flag and reran the complete suite successfully on the head above.

### Device acceptance
- Android Debug APK and full Windows Debug bundle: **REQUESTED** by this ledger commit's `[device-test-build]` marker; build results/artifact hashes pending.
- Physical Android↔Windows transfer, timeout/revoke behavior, and final-file SHA-256 equality: **NOT TESTED**.
- Screen/audio mirroring and real input control: **NOT TESTED**.
- Production crypto/security review: **NOT TESTED**; the custom pairing lab remains experimental.

No merge, no main changes, no new dependency or paid API.


### M43 targeted Android + Windows build result — 2026-10-26

- **Exact build head:** `9e1556eb171513912a5a5f6ad5df7f176fbdd041`
- **CI and both platform builds:** [run 40325451235](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40325451235) — **SUCCESS**.
- **Android artifact:** ID `12651680282`, [download from GitHub Actions](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40325451235/artifacts/12651680282), expires **2026-11-09**.
  - Artifact ZIP SHA-256: `b3f9400a9a7c9cdc84841a118f9af395e0dc6f985e79b4be829a24490fac4ea6`
  - APK size: 159,609,675 bytes.
  - APK SHA-256: `0225b82b00432d3bca145a12d810587766ef773bf8828346a4a196670eb6fe4a`
- **Windows artifact:** ID `12651551015`, [download full bundle from GitHub Actions](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40325451235/artifacts/12651551015), expires **2026-11-09**.
  - Artifact ZIP SHA-256: `d720cbfbbabd9b4668a0af0c6636586a87d15636bbf8214e200f7af805132bce`
  - `liquid_remote_control.exe` size: 1,271,296 bytes.
  - EXE SHA-256: `29d635d5d4defbc772ddd955ed921ff7756a07f10b526fb00fb240353dcd55c5`
- **Local verification:** both ZIPs passed integrity checks; extracted APK and EXE hashes matched their embedded evidence JSON. The Windows EXE is not standalone; use the complete bundle ZIP.
- **Device acceptance:** physical Android↔Windows transfer, timeout/revoke behavior and final-file SHA-256 equality remain **NOT TESTED**. These are Debug acceptance packages, not releases.

### M44 — Abortable peer-response timeouts (2026-10-26)

- **Source + regression-test commit:** `7af959ba8bd676bdda2cea36046af0dc64817914`
- **CI:** [run 40330579562](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40330579562) — Flutter source/widget tests, Node protocol tests and Windows capture-lifecycle tests **PASS**.
- Added a configurable positive `responseTimeout` (60-second default) to the Android/Windows file-transfer lab.
- A timed-out peer `receive()` now calls `abort()` when the transport implements `AbortableFileTransferChannel`; receiver failures roll back private staging and do not send `FILE_OK`.
- Added regressions for a stalled sender acknowledgement and a stalled receiver peer frame.
- **Limitation:** `Future.timeout` alone cannot cancel the pending future; production channel adapters must implement `abort()` by actually closing/revoking the underlying transport. This remains a protocol lab, not production-approved cryptography.
- **Targeted Android APK + Windows Debug bundle:** requested in the following commit solely for device acceptance of the new timeout/revoke path; not a release.
- **Physical Android↔Windows transfer and SHA-256 comparison:** **NOT TESTED** until user/device evidence is available.
- **Screen/audio mirroring, actual input control and independent production security review:** **NOT TESTED**.

No merge, no `main` changes, no new dependency, and no paid API.



## M54 — Native Android SAF filename-policy parity (2026-10-27)

- **Production change:** `SafReceivePolicy.validFileName` now normalizes the Windows device-name stem by trimming ASCII spaces/dots before its extension and rejects `CONIN$`/`CONOUT$` as well as `CON`, `PRN`, `AUX`, `NUL`, and COM/LPT 1–9 (including superscript digits). This closes a defense-in-depth gap where the Dart sender rejected aliases such as `CON .txt` but the native Kotlin SAF boundary did not.
- **Regression coverage:** added `CON .txt`, `NUL .bin`, `COM1 .log`, `AUX .cfg`, `CONIN$.txt`, `CONOUT$.txt`, `LPT3 .txt`, and console aliases with spaces before the extension; ordinary `CON-notes.txt` and `COM10.txt` remain valid.
- **Source commit:** `a4f3cd19fe31c4179a7b64cdce106d4876ce4a98`
- **Test commit:** `c3435564f9209bb730f9c27d6e2cbab1aa40bb90`
- **Workflow change:** `da63a93143db17b34d018b3c14cd7d25a6eac5b9` adds an opt-in `android-saf-policy-tests` job, triggered by `[saf-policy-test]`, which compiles/runs the native policy tests without creating an APK or Windows bundle.
- **Local test:** Kotlin/JVM compile and policy test execution **PASS** on the available JDK 17/Kotlin 2.4.21 runtime; the run printed `PASS: SAF filename parity, Unicode spoofing, single-stage and cache quotas`.
- **GitHub exact-head CI:** **NOT VERIFIED in this run**; the available workflow-run lookup exposes pull-request-triggered runs only, while this branch's current CI is push-triggered. [Remote Control workflow filtered to this branch](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/workflows/ci.yml?query=branch%3Afeature%2Fbuild-reliability-v0_9).
- **Acceptance:** native policy compile/regression locally **PASS**; GitHub exact-head job **NOT VERIFIED**; Flutter/Node CI on the final documentation head **NOT VERIFIED**; Android APK/Windows bundle and physical-device acceptance **NOT TESTED**.
- **Safety:** no merge, no `main` changes, no new dependency or paid API. The new workflow job is source-only and does not build APK/EXE. Pairing cryptography remains experimental and not production-approved.


## M56 — Bound ephemeral pairing-ledger identifiers (2026-10-27)

**Branch:** `feature/build-reliability-v0_9`; PR #1 only. This is defense-in-depth for the short-lived pairing indicator, not authorization and not production crypto approval.

- **Production commit:** `3279a8497723699577f9c86203be4b45fa2e0637`.
- **Regression-test commit:** `536ad94744413a24f947e7a7ba556d9e50d2bdfc`.
- Pair-session address identifiers are limited to 128 UTF-16 code units; fingerprint identifiers are limited to 256.
- Rejects control characters, bidi controls, invisible formatting controls, Unicode tag characters and replacement characters before allocating or evicting a session entry.
- Tests cover oversized addresses/fingerprints, bidi/newline spoofing, unchanged capacity/expiry semantics, and a valid scoped IPv6 address with a bounded fingerprint.
- **CI at documentation commit:** pending; verify the Flutter analyzer/tests on the final head before claiming PASS.
- APK/Windows bundle: intentionally not built for this in-memory policy change.
- Physical Android↔Windows pairing, clipboard, file transfer, screen/audio and input acceptance: **NOT TESTED**.
- The bespoke pairing protocol remains experimental and is not approved for production privileged control. No merge, no `main` write, no new dependency, no paid API, no secrets.


## M60 — Bound ephemeral pairing-session ledger (2026-10-27)

**Scope:** Remote Control PR #1 only; branch `feature/build-reliability-v0_9`. No main change or cross-repository dependency.

- **Production:** `PairSessionLedger` now caps configured entries at 4,096 and lease lifetime at one day, rejects negative monotonic clock readings, and clears ephemeral indicators before reporting an invalid/backwards clock.
- **Regression:** `flutter/test/pair_session_ledger_test.dart` covers over-limit capacity, overlong lifetime and negative-clock invalidation, while preserving expiry, refresh, revocation, identifier and rollback cases.
- **Source/test commits:** production `fabb904c0f007368dd313a431f7b6cac1ebc3939`; regression/current branch head `f94bda935575871ef131ee28af6ad66bf84c15d9`.
- **CI on exact head:** **NOT VERIFIED** in this run. The push workflow is configured for this feature branch, but the available connector only exposes pull-request-triggered runs and returned no run ID for the push. Do not claim a test pass from source inspection alone.
- **Acceptance:** source diff reviewed **PASS**; new tests **PRESENT / execution NOT VERIFIED**; Flutter analyzer/tests **NOT VERIFIED**; APK/Windows bundle **NOT TESTED**; physical pairing and device controls **NOT TESTED**.
- **Security boundary:** this ledger is an ephemeral UI indicator, not authorization. It does not establish cryptographic pairing, encrypt traffic, or authorize screen/input/files/clipboard. Those still require a reviewed authenticated channel and explicit consent.
- **Safety:** no new dependency, binary build, secret, paid API, merge or main change.


## 2026-10-27 — M61: Permanently invalidate pairing-session indicators after monotonic rollback

- **Scope:** PR #1 only, branch `feature/build-reliability-v0_9`; no main or NetKit source changes.
- **Production:** `PairSessionLedger` now latches itself unusable after a negative or backwards monotonic-clock observation. It clears ephemeral indicators and throws on subsequent reads/writes even after the injected clock recovers; callers must create a new ledger as part of a new pairing-session lifecycle. Calling `clear()` removes entries but cannot reset the clock-health latch.
- **Regression:** `flutter/test/pair_session_ledger_test.dart` now verifies that contains/length/remember/fingerprint lookup remain blocked after clock recovery and that revoke-triggered rollback also leaves the ledger disabled.
- **Commits:** production `6552b34ab477eaa5c2a63485ec9549d3f69b6643`; regression/head `e0a1d5a882639907027a2acc33701bd5b3083139`.
- **Exact-head CI:** [run 40454907644](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40454907644) — **SUCCESS** on the source/test head. Flutter source checks, Node protocol/media-lab suite (optional FFmpeg integrations remain skipped when tools are absent), and Windows capture-lifecycle tests passed. Android/Windows package jobs were **SKIPPED**.
- **APK/Windows bundle:** **NOT TESTED / NOT BUILT** for this in-memory session-ledger change.
- **Physical pairing, file transfer, clipboard, screen/audio mirroring and input control:** **NOT TESTED**.
- **Security boundary:** the ledger is an ephemeral indicator only, not authorization, transport authentication or production cryptography. A clock failure requires a fresh ledger/session; it does not approve the experimental pairing protocol.
- **Safety:** no new dependency, paid API, secret, build artifact, merge or main change.

## 2026-10-27 — M62: Bound one-shot file-transfer deadlines

- **Scope:** Remote Control PR #1 only, branch `feature/build-reliability-v0_9`; NetKit remains a separate repository/PR.
- **Production:** `flutter/lib/security/file_transfer_lab.dart` now caps each configurable send, response, consent and staging deadline at two minutes (defaults remain 60 seconds). Invalid/unbounded deadlines are rejected before file-channel I/O, prompting or destination staging. This prevents a caller-supplied enormous timeout from pinning a one-shot transfer indefinitely; transport abort and staging rollback behavior remain unchanged.
- **Regression:** `flutter/test/file_transfer_lab_test.dart` covers overlong sender and receiver deadlines and verifies no channel, consent or staging side effects occur before rejection.
- **Source/test head:** `5cbfc92d84bfd9e83d975ac73a2784a2edaa0144`.
- **Exact-source CI:** [run 40461918225](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40461918225) — **SUCCESS**. Flutter analyzer clean, **131 Flutter tests passed**, Node LAN/protocol/media lab tests passed, and Windows capture-lifecycle tests passed. Optional Android SAF and package-build jobs were skipped.
- **Earlier failed attempt:** [run 40461704868](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40461704868) — **FAIL** because the receiver's send/response validation still accepted overlong values. The receiver now uses the same bounded validator and the subsequent exact-source run passed.
- **Android APK/Windows bundle:** **NOT TESTED / NOT BUILT**; no package was required for this timeout-policy change. **Physical Android↔Windows pairing, transfer, clipboard, screen/audio mirroring and input acceptance:** **NOT TESTED**.
- **Security boundary:** deadlines reduce resource-pinning risk but do not make the experimental pairing cryptography production-approved. No new dependency, paid API, secret, merge or main change.


## 2026-10-27 — M63: Bound screen-preview frame assembly lifetime

- **Scope:** Remote Control PR #1 only, branch `feature/build-reliability-v0_9`; no NetKit or main changes.
- **Production:** extracted `PreviewFrameAssembler` and wired it into `PairingLab._receivePreview`. Each view-only JPEG frame remains bounded to 512 KiB; parts are bounded to 2,600 decoded bytes and 4,000 encoded characters, with strict canonical base64url, exact offsets, strictly increasing frame IDs, no overlapping frames, and JPEG start/end marker validation.
- **Absolute deadline:** a partial frame must finish within 15 seconds regardless of the 12-second per-message idle timeout. This prevents a peer from retaining a partial image indefinitely by dripping valid parts just before each idle timeout. A backwards injected monotonic reading also fails closed.
- **Regression tests:** six new `preview_frame_assembler_test.dart` cases cover complete consecutive frames, deadline expiry, backwards clock, overlapping/replayed IDs, invalid offsets/encoding/oversized parts, and incomplete/non-JPEG data.
- **Source/test head:** `fcc2f6092f28d86ccf2ca76ebc723baeb1c9a046`.
- **Exact-head CI:** [run 40468550459](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40468550459) — **SUCCESS**. Flutter analyzer and **137 Flutter tests passed**; Node LAN/protocol/media-lab tests and Windows capture-lifecycle tests passed.
- **Android APK/Windows bundle:** **NOT TESTED / NOT BUILT**; package jobs were skipped because this was a bounded frame-assembly source/test change, not a device-build request.
- **Real screen-preview streaming, throughput/FPS, audio mirroring, actual input control, file/clipboard cross-device acceptance:** **NOT TESTED**. This remains view-only preview lab functionality, not production remote-control approval.
- **Security boundary:** no new dependency or copied external implementation; existing base64/JPEG handling only. The experimental pairing cryptography is still not independently audited and must not be treated as production authorization.
- **Live Google Docs Handoff:** **SYNC FAILED** — no authorized Google Docs write/read connector was available in this run. GitHub acceptance ledger is updated; the live Drive document is not claimed updated.
- **Safety:** no paid API, secret, APK/EXE artifact, auto-merge or main change.

## 2026-10-27 — M64: sticky fail-closed monotonic clock for preview frame assembly

- **Scope:** Remote Control PR #1 only, branch `feature/build-reliability-v0_9`; no NetKit or `main` changes.
- **Production:** `PreviewFrameAssembler` now remembers the last monotonic-clock reading across frame begin/part/end operations. Any reading below the last observation, a negative injected reading, or an exception from the clock marks that assembler permanently unusable. A later clock recovery cannot restart frame assembly on the same instance. The existing 512 KiB frame / 2,600-byte part bounds, canonical base64url checks, ordered offsets/IDs, JPEG markers and 15-second absolute assembly deadline remain.
- **Regressions:** new tests roll the clock back from 110 to 105 while the frame start remains 100 (the case a start-only comparison misses), then verify recovery to 120 still cannot begin a new frame. A second test makes the injected clock throw and verifies the same sticky failure.
- **Source commit:** [93d290a026b7ffcd9bffab423aba34dbfcc14d13](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/93d290a026b7ffcd9bffab423aba34dbfcc14d13).
- **Regression commit / source-test head:** [a4f5721b3566889a74e2367613c65d5ddbb8b736](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/a4f5721b3566889a74e2367613c65d5ddbb8b736).
- **Exact-head CI:** **NOT VERIFIED** in this run. The configured [Remote Control validation/build workflow](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/workflows/ci.yml) includes a push trigger for this development branch, but the connected workflow lookup exposes only pull-request-triggered runs and returned none for this SHA. No passing run ID is claimed.
- **Android APK / Windows bundle:** **NOT TESTED / NOT BUILT**; the change is a bounded source/test fix and did not justify a package build.
- **Physical preview streaming/FPS, audio mirroring, input control, file/clipboard cross-device acceptance:** **NOT TESTED**. Experimental pairing cryptography remains unapproved for privileged production use.
- **Safety:** no new dependency, paid API, secret, artifact, auto-merge or main change.

## 2026-10-27 — M65: Bound remote preview frame identifiers

- **Scope:** PR #1 only, branch `feature/build-reliability-v0_9`; no NetKit or `main` changes.
- **Problem:** `PreviewFrameAssembler` accepted any positive Dart integer as a frame ID. A malformed or incompatible peer could send an out-of-range value and advance the completed-frame watermark so that ordinary IDs from the stream could no longer be accepted.
- **Production change:** added an explicit signed 31-bit frame-ID ceiling (`0..0x7fffffff`) before any partial-frame state is allocated. The frame byte and part-size caps, strict canonical base64url, monotonic ID ordering, JPEG markers and 15-second absolute assembly deadline remain unchanged.
- **Regression:** `flutter/test/preview_frame_assembler_test.dart` sends `0x80000000`, expects a format rejection, then successfully assembles a valid frame ID 1 on the same assembler. This verifies rejection does not mutate the frame watermark.
- **Production commit:** [adb7ef1d19b13bde14aa477d1b0661e3ce6e3259](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/adb7ef1d19b13bde14aa477d1b0661e3ce6e3259).
- **Source/test head:** [84baa4d80d2ec8463904896eb2ee142ae1b30d0c](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/84baa4d80d2ec8463904896eb2ee142ae1b30d0c).
- **CI:** **NOT VERIFIED** for this source/test head. The repository workflow has a push trigger for this branch, but the connected workflow-run lookup exposes only pull-request-triggered runs and returned no run ID for this head; the combined commit-status lookup also returned no statuses. Do not infer PASS from the test being present.
- **Flutter/Dart local execution:** **NOT TESTED** in this environment because Flutter/Dart are not installed.
- **Android APK / Windows bundle:** **NOT TESTED / NOT BUILT**; the change is a bounded preview-parser source/test fix, not a device-build request.
- **Physical preview stream/FPS, audio mirroring, real input control, file/clipboard cross-device acceptance:** **NOT TESTED**. The preview assembler remains a view-only lab component; experimental pairing cryptography is not production-approved.
- **Safety:** no new dependency, paid API, secret, artifact, auto-merge or `main` write.

## 2026-10-27 — M66: exact preview deadline and cancellable source hashing

- **Scope:** PR #1 only, branch `feature/build-reliability-v0_9`; no `main` or NetKit changes.
- **Preview production fix:** `PreviewFrameAssembler` now expires a frame at `elapsed >= 15 seconds`, not one tick after the documented absolute deadline. The regression checks the exact boundary and verifies that the expired partial frame is discarded while a new frame can still start.
- **Transfer production fix:** source hashing now consumes the picker/provider stream incrementally into the SHA-256 chunked sink with an explicit idle timer owned by the hash operation. If the provider stalls, the timeout cancels its stream subscription and fails preflight before `FILE_OFFER`; no file bytes are buffered wholesale in memory. This also repairs the existing stalled-source regression that hung in the previous CI run.
- **Commits:** preview boundary fix `b480791dde522059b0c36995fd74fed16e364a87`; exact-boundary regression and assertion correction `87f8832154ea80e79682a867f5b551514497176d`, `201ca1d4b5dbf07ef1824ca0a64c9e0be5e555c0`; cancellable hashing `f5b18331fe9d5f7d021fd51cd06eef88f8e72671`; analyzer correction `63e589a2110dbb9f8b449d1b9ce445dfa0ef3a59`.
- **Exact-head CI:** [run 40481491759](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40481491759) — **SUCCESS** on head `63e589a2110dbb9f8b449d1b9ce445dfa0ef3a59`. Flutter analyzer/widget/unit suite passed (**142 tests**); Node protocol/media-lab tests passed; Windows capture-lifecycle tests passed. Android SAF tests and Android APK/Windows bundle jobs were skipped by the workflow's opt-in policy.
- **Earlier failures retained for audit:** [run 40480845266](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40480845266) caught the exact-boundary test's mistaken closure assertion and a stalled source-hash timeout; [run 40481244537](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40481244537) caught an unnecessary null assertion. These were corrected before the passing run.
- **Build/device gate:** Android APK **NOT TESTED / NOT BUILT**; Windows EXE/bundle **NOT TESTED / NOT BUILT**; real Android↔Windows pairing, file/clipboard transfer, preview FPS, audio and input control **NOT TESTED**. This remains source-level acceptance, not device acceptance.
- **Security boundary:** the file channel remains an experimental LAN lab and is not production-approved for privileged remote control; no root, paid API, new dependency, secret, auto-merge or `main` change.

 
## 2026-10-27 — M67: Revoke receiver channel on non-timeout transfer failures

- **Scope:** PR #1 only, branch `feature/build-reliability-v0_9`; no NetKit or `main` changes.
- **Problem:** `receiveLabFile` already rolled back uncommitted staging in `finally`, and timeout helpers aborted abortable channels, but a non-timeout error from `channel.receive()`, staging writes, or commit could unwind the receiver while leaving the one-shot transport open.
- **Production fix:** the receive transaction now catches every failed transfer path, aborts the one-shot channel, and rethrows the original failure before its existing staging rollback/finalization logic. A published file is still not deleted merely because the final `FILE_OK` write fails; the channel is revoked and the committed destination is preserved.
- **Regression:** `flutter/test/file_transfer_lab_test.dart` injects a non-timeout peer read/socket-reset error after `FILE_READY` and verifies the channel is aborted, private staging is rolled back, no file is published, and no `FILE_OK` is sent.
- **Production commit:** [8cbd4f7a689b145e9241b75da191d2da6ec9f563](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/8cbd4f7a689b145e9241b75da191d2da6ec9f563).
- **Regression/test head:** [202658501b7cc9139f436ab7c6a43c4114016898](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/202658501b7cc9139f436ab7c6a43c4114016898).
- **Exact-head CI:** [run 40489065047](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40489065047) — **SUCCESS**. Flutter analyzer and **143 Flutter tests passed**; Node protocol/media-lab suite passed (31 tests reported, 24 passed and 7 optional FFmpeg-dependent tests skipped); Windows capture-process lifecycle tests passed. Android SAF policy tests and Android/Windows package jobs were skipped.
- **Android APK / Windows EXE bundle:** **NOT TESTED / NOT BUILT**; no package was needed to verify this transaction-lifecycle change.
- **Physical Android↔Windows pairing, file/clipboard transfer, preview FPS, audio mirroring and input control:** **NOT TESTED**. The pairing and file channel remain experimental lab code, not independently audited production authorization or cryptography.
- **Safety:** no new dependency, paid API, secret, artifact, auto-merge or `main` write. No root requirement was introduced.
- **Live Google Docs Handoff:** **SYNC FAILED** until an authorized Google Docs write/read connector is available; this repository ledger is not a substitute for the live Drive document.

## 2026-10-27 — M68 — Preserve transfer failure when staging cleanup also fails

- **Production changed:** incoming file reception now records the primary receive/transport failure and, if `staging.abort()` also fails, raises `FileTransferCleanupException` containing both errors while retaining the original receive stack. This avoids silently masking a socket/provider failure with cleanup failure and makes a possible leftover private staging file explicit.
- **Regression changed:** `flutter/test/file_transfer_lab_test.dart` injects a socket-reset failure plus a failing staging abort and asserts both errors are surfaced and the one-shot channel is revoked.
- **Production commit:** [f3e97928ef1e5a431aaebfcd21bbafebb785ece5](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/f3e97928ef1e5a431aaebfcd21bbafebb785ece5).
- **Regression/test head:** [f910d143d71e6af85402a5ddacadfaf60e45b013](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/f910d143d71e6af85402a5ddacadfaf60e45b013).
- **Exact-head CI:** **NOT VERIFIED**. No combined status checks or pull-request-triggered run were exposed for this push head, so there is no verifiable run ID/log for M68. Earlier M67 CI does not prove this patch.
- **Flutter analyzer/tests:** **NOT TESTED on M68 head** in this session; local Flutter/Dart toolchain execution was unavailable.
- **Android APK / Windows EXE bundle:** **NOT TESTED / NOT BUILT**; the targeted failure-path test is source-level and no device binary was needed.
- **Device file transfer, Android SAF staging, Windows destination rollback:** **NOT TESTED**.
- **Safety:** no new dependency, paid API, secret, auto-merge or `main` write. No root requirement was introduced; existing pairing remains experimental lab code pending security review.
- **Live Google Docs Handoff:** **SYNC FAILED** because no Google Docs write/read connector is available in this session; this ledger is not a substitute for the live Drive document.


## 2026-10-27 — M69: Preserve receiver timeout when transport abort itself fails

- **Scope:** Remote Control PR #1 only; branch `feature/build-reliability-v0_9`. No NetKit or `main` changes.
- **Finding:** receiver `sendFrame` and `receiveFrame` called an abortable channel's `abort()` directly from their `TimeoutException` handlers. If a platform transport threw while aborting, that cleanup exception masked the timeout that caused cleanup and obscured the actual failure.
- **Production fix:** centralized best-effort receiver channel revocation in `abortChannel()`; timeout handlers now call it and rethrow the original timeout even if abort fails. The same safe helper is available to the receive transaction's other terminal paths.
- **Regressions:** two tests inject a channel whose abort marks it closed then throws: one for a stalled receive, one for a stalled `FILE_READY` send. Both assert that the caller still sees `TimeoutException`, the one-shot channel is revoked, private staging is aborted and no `FILE_OK` is emitted.
- **Source/test head:** `a98e25f41c88e211e1a2671fc9cc490c017f83ea`.
- **Exact-head CI:** [run 40505025666](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40505025666) — **SUCCESS**. Flutter analyzer and **146 Flutter tests passed**, including both new timeout/abort regressions; Node protocol/media-lab suite passed with **7 optional FFmpeg-dependent tests skipped**; Windows capture-process lifecycle tests passed.
- **Android SAF / APK / Windows bundle:** **SKIPPED / NOT BUILT** by the workflow; this is a source-level failure-path fix, not device acceptance.
- **Device acceptance:** **NOT TESTED** — Android↔Windows file/clipboard transfer, real screen preview/FPS, audio and input control remain open.
- **Security boundary:** custom pairing/channel remains experimental lab code, not production-approved privileged authorization or cryptography. No root, new dependency, paid API, secret, artifact, auto-merge or `main` write.
- **Live Google Docs Handoff:** **SYNC FAILED**; no authorized Google Docs write/read connector was available in this session.


## 2026-10-27 — M70: Idempotent receiver channel revocation

- **Scope:** Remote Control PR #1 only; branch `feature/build-reliability-v0_9`. No NetKit or `main` changes.
- **Finding:** receiver consent-failure and explicit-denial paths bypassed the guarded abort helper and called `channel.abort()` directly. A platform abort exception could replace the original consent failure or turn an ordinary user denial into a thrown failure. Some timeout paths could also call abort more than once as control unwound.
- **Production fix:** receiver `abortChannel()` is now idempotent and marks the one-shot channel revoked before invoking platform code. All receiver terminal paths (consent failure, refusal, malformed offer, timeout and receive transaction failure) use the same best-effort helper, preserving the primary outcome when abort itself throws.
- **Regressions:** added tests for a consent callback failure with throwing abort (original `StateError` remains visible) and an explicit denial with throwing abort (returns `null` normally); both assert the channel is revoked exactly once and no staging is created.
- **Production commit:** [`3c2e552bbb4943e6bc89d520aaba900324b81aaa`](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/3c2e552bbb4943e6bc89d520aaba900324b81aaa).
- **Regression/test head:** [`9a68e119b357cf0aee40fcc35269f1381a428019`](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/9a68e119b357cf0aee40fcc35269f1381a428019).
- **Exact-head CI:** [run 40512964922](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40512964922) — **SUCCESS**. Flutter analyzer and **148 Flutter tests passed**, including the two new revocation regressions; Node LAN/protocol/media-lab tests and Windows capture-process lifecycle tests passed. Seven optional FFmpeg-dependent tests were skipped; this run does not claim real codec acceptance.
- **Android SAF policy / APK / Windows bundle:** **SKIPPED / NOT BUILT** by the workflow. No package was needed for this receiver lifecycle regression.
- **Device acceptance:** **NOT TESTED** — real Android↔Windows file/clipboard transfer, preview FPS, audio mirroring and input control remain open.
- **Security boundary:** pairing/channel cryptography remains experimental and is not production-approved for privileged remote control. No root, new dependency, paid API, secret, artifact, auto-merge or `main` write.
- **Live Google Docs Handoff:** **SYNC FAILED**; no authorized Google Docs write/read connector was available. This ledger does not replace the live Drive document.

## 2026-10-27 — M71: Fail closed when pairing clock sources fail

- **Scope:** Remote Control PR #1 only; branch `feature/build-reliability-v0_9`. No NetKit or `main` changes.
- **Finding:** monotonic rollback was already fail-closed, but an injected/platform monotonic-clock provider that threw could escape before the replay nonce guard latched its unhealthy state. In the UI-only pairing indicator ledger, the same failure could leave prior entries resident and allow the ledger to be reused after the clock source recovered.
- **Production changes:** `PairingNonceGuard` now clears replay entries and permanently disables that guard if its clock source throws. `PairSessionLedger` clears the UI indicators, latches the clock as broken, and throws a clear `StateError`; creating a fresh pairing/session lifecycle is required. The ledger remains explicitly UI-only and is not authorization.
- **Regression coverage:** added clock-source exception tests to `flutter/test/pairing_nonce_guard_test.dart` and `flutter/test/pair_session_ledger_test.dart`. Both verify entries are cleared and recovery of the injected clock does not reactivate the old guard/ledger.
- **Source commits:** [64eb8cd](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/64eb8cddef9e03e82462782f79f09eed3c687711) and [9096a8c](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/9096a8c9c37ea7850e56e3ab2924cd49e5924297).
- **Regression/test head:** [28cc242bcd017f1514ff3c08d6626a55e3388d1d](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/28cc242bcd017f1514ff3c08d6626a55e3388d1d).
- **Exact-head CI:** **NOT VERIFIED** in this run. The connector returned no combined status entries and no pull-request-triggered run record for this push head; earlier M70 CI at [40512964922](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40512964922) does not prove these new changes.
- **Flutter analyzer/tests:** **NOT TESTED on the M71 head** in this session. The changed tests are part of the normal `flutter test` suite, but no exact-head run result was available to verify.
- **APK / Windows EXE bundle:** **NOT TESTED / NOT BUILT**. This is a source-level lifecycle hardening change, not a device-package gate.
- **Physical acceptance:** **NOT TESTED** — Android↔Windows pairing, files/clipboard, screen/audio preview and input remain open.
- **Security boundary:** custom pairing remains experimental and not production-approved for privileged remote control; no root, new dependency, paid API, secret, artifact, auto-merge or `main` write.
- **Live Google Docs Handoff:** **SYNC FAILED**; no authorized Google Docs write/read connector was available. This repository ledger does not replace the live Drive document.

## 2026-10-27 — M71 verification update: clock failure handling

- **Exact-head workflow:** [40516935990](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40516935990), head `28cc242bcd017f1514ff3c08d6626a55e3388d1d`.
- **Flutter source gate:** **PASS** — analyzer reported `No issues found`; **150 tests passed**, including `clock source failure clears replay state and permanently fails closed` and `clock source failure clears indicators and permanently invalidates the ledger`.
- **Node protocol/media gate:** **PASS** — 96 protocol/LAN tests passed; H.264/media tests reported 24 passed and 7 optional FFmpeg-dependent tests skipped (not codec acceptance).
- **Windows capture lifecycle:** **PASS** — 3 tests passed, 0 failed.
- **Package/device gate:** Android SAF, APK and Windows bundle jobs were skipped; **NOT TESTED / NOT BUILT**. Physical Android↔Windows acceptance remains open.
- **Safety:** no new dependency, paid API, secret, root requirement, artifact, auto-merge or `main` write. Pairing remains experimental and is not production-approved.

## 2026-10-27 — M71 CI closure

- **Final exact-head run:** [40516935990](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40516935990) is **completed / success** for source/test head `28cc242bcd017f1514ff3c08d6626a55e3388d1d`.
- Check-run API confirms `flutter-source-checks: success`, `node-protocol-tests: success`, and `windows-capture-lifecycle: success`; Android SAF, APK and Windows debug bundle jobs were **skipped**.
- **Acceptance:** analyzer + 150 Flutter tests PASS; Node protocol/LAN 96 PASS; H.264/media 24 PASS with 7 optional FFmpeg-dependent tests skipped; Windows capture lifecycle 3 PASS. No device or package acceptance is claimed.

## 2026-10-27 — M72: Abortable file-transfer channel contract

- **Production change:** `flutter/lib/security/file_transfer_lab.dart` now requires `AbortableFileTransferChannel` before sender or receiver preflight. This is necessary because `Future.timeout` does not cancel an underlying Dart send/receive future; a non-abortable adapter could continue work after the transfer has reported failure.
- **Source commit:** `42346f01ba98cce63a29bc226c6b05bed959d191`.
- **Regression tests:** `e67f9fc67941f8b26952c9f11a165ae4bc169603` verifies sender/receiver reject non-abortable channels before reading, sending, prompting for consent, or allocating staging. The first CI attempt exposed five existing desktop-staging tests whose fake channel did not implement abort; the fixture was corrected in `bf92adeb162877316f1838d69222107fe14e00b0` to model the required abort contract.
- **Exact-head CI:** [run 40523364826](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40523364826), tested head `bf92adeb162877316f1838d69222107fe14e00b0` — **SUCCESS**.
- **PASS:** Flutter analyzer, **152 Flutter tests**, Node protocol/LAN suite (**31 total; 24 passed, 7 optional FFmpeg-dependent tests skipped**), Windows capture lifecycle. No new dependency or paid API.
- **SKIPPED / NOT TESTED:** Android SAF native policy job, APK build, Windows bundle build, physical Android↔Windows file-transfer/clipboard/screen/audio/control acceptance. This is source CI only, not device acceptance.
- **Security boundary:** channel abort is required for reliable cancellation, but it does not make the experimental pairing protocol production-approved. No root, secret, auto-merge or `main` write.
- **Live Google Docs Handoff:** SYNC FAILED — no authorized Docs write/read connector was available in this run; this repository ledger does not replace the live Drive document.

## 2026-10-27 — M74b: Canonical Base64 framing for incoming file chunks

- **Production source:** `flutter/lib/security/file_transfer_lab.dart` now round-trips each decoded chunk through Base64 and rejects it unless the wire text is canonical. This closes alternate encodings with non-zero unused padding bits while preserving the same payload bytes.
- **Regression:** `flutter/test/file_transfer_lab_test.dart` sends `AQIDBAV=`, a non-canonical alias of `AQIDBAU=` for the same five bytes. The receiver must reject it before writing any bytes, abort the one-shot channel and discard private staging.
- **Source commit:** [`ea0ec0d`](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/ea0ec0dd0ad36d7f891e0c9be0646e9fbfcd1b0a).
- **Test + exact tested head:** [`1712650`](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/17126501c5bc119d706b6098f7b4d859f962db2e).
- **Exact-head CI:** [run 40531906700](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40531906700) — **SUCCESS** on source/test head `17126501c5bc119d706b6098f7b4d859f962db2e`.
- **PASS:** Flutter analyzer; **153 Flutter tests**; Node protocol suite **31 total / 24 passed / 0 failed / 7 optional FFmpeg-dependent tests skipped**; Windows capture lifecycle tests.
- **SKIPPED / NOT TESTED:** Android SAF native policy job, APK, Windows debug bundle and physical-device acceptance. No build artifacts or SHA-256 package hashes were produced in this round.
- **Security boundary:** canonical framing reduces parser ambiguity; it does not authenticate the peer or approve the experimental lab protocol for privileged production control. No new dependency, paid API, root access, secret, merge or `main` change.
- **Live Google Docs Handoff:** **SYNC FAILED** — no authorized Google Docs write/read connector was available, so this ledger is not being represented as a substitute for the live Drive document.

## 2026-10-27 — M75: Require readable and writable SAF destination grants

- **Problem:** the native receiver requested both SAF read/write grants but accepted a picker result carrying only write permission. Publication requires writing a temporary document and reading it back to verify SHA-256, so a write-only grant was not a valid destination.
- **Fix:** added `SafReceivePolicy.hasReadWriteTreeGrant` and require both READ and WRITE flags before accepting the selected tree. Also fail closed when the native `write` or `abort` method-channel calls omit a transfer ID or a write omits chunk data.
- **Regression:** `qa/SafReceivePolicyTest.kt` covers read+write, unrelated extra flags, read-only, write-only and no-grant combinations.
- **Source commits:** [1af838f](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/1af838fc8a157d868da844dc06e180ecfd3ed660), [6b349c8](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/6b349c8acb12ba24de3f457b37c73e775d5e8602), [3e32b33](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/3e32b33da8c2a22728615e504d5c484004b4ea88).
- **PASS — exact-head CI:** [run 40542041464](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40542041464), source/test SHA `3e32b33da8c2a22728615e504d5c484004b4ea88). Native SAF policy tests, Windows capture lifecycle tests, and Flutter source/analyzer/widget tests all succeeded; **153 Flutter tests passed**. Node protocol suite: **96/96 passed, 0 failed**. Optional FFmpeg media-integration suite: **24 passed, 0 failed, 7 skipped**; skipped integration cases are not counted as passes.
- **PASS — targeted Android debug APK:** the native SAF milestone job compiled the Android overlay, ran native policy regressions, built the APK and validated its structure. Evidence JSON: `app/build-evidence/android-saf.json`. APK size: 159,618,339 bytes. APK SHA-256: `93c3eba1e55271d32707f41bcb6f8642f96ef1b8d357e3bc83d9280784f05b2a`. Artifact ZIP SHA-256: `fb919b82bd85dd563598bb1fead36e01a9712820e61fe61e431ac31dbf4c4c42`.
- **Artifact:** [Remote Android SAF milestone artifact 12751995840](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40542041464/artifacts/12751995840), expires 2026-11-03. This is a targeted test APK, not a release.
- **SKIPPED intentionally:** generic Android debug APK job and Windows bundle job; this milestone targets the Android SAF grant path only. No Windows EXE/bundle was built.
- **NOT TESTED:** install/SAF picker/readback on a physical Android device; end-to-end Android↔Windows transfer, clipboard, screen/audio mirroring or real control acceptance.
- **Security boundary:** both grants are necessary but not sufficient for production trust. No new dependency, paid API, root access, secret, auto-merge or `main` write. PR #1 remains Draft and its existing merge state was not changed.
- **Live Google Docs Handoff:** **SYNC FAILED** — no authorized Google Docs write/read connector was available in this run; this GitHub ledger is not a substitute for the live Drive document.

## 2026-10-27 — M76: Revoke one-shot receive channels on terminal failure

- **Scope:** Remote Control PR #1 only; branch `feature/build-reliability-v0_9`. No NetKit or `main` changes.
- **Finding:** the Node receiver deleted private staging after malformed offers, explicit denial, bad hashes and provider failures, but several early/error paths did not close the one-shot file-intent transport. That could leave a rejected intent channel alive after the operation had terminated.
- **Fix:** centralized best-effort channel revocation in `abortFileChannel()`, reused it for timeout/cancellation waits, and wrapped the public `receiveFileOnce` boundary so pre-staging and transfer errors revoke the channel while preserving the original exception. Malformed offers send best-effort `FILE_DENIED`; explicit denial closes after notification.
- **Regression:** `tools/lan_probe/file_transfer.test.mjs` now models socket destruction and asserts revocation after explicit denial, invalid/oversized offers, and corrupt payload/hash failure.
- **Source + regression commit:** [e90e2eabf94a7b30d8b77cebe7030c52c0fe0425](https://github.com/amroalhamedi2022-hue/Remote-Control/commit/e90e2eabf94a7b30d8b77cebe7030c52c0fe0425).
- **PASS — exact M76 source/test CI:** [run 40551515664](https://github.com/amroalhamedi2022-hue/Remote-Control/actions/runs/40551515664) completed **SUCCESS** on branch head `43af0e84cc27b39dadcd897a6ba53618f5c9aa16`, which contains the M76 source/test commit `e90e2eabf94a7b30d8b77cebe7030c52c0fe0425` plus its ledger entry. Node protocol suite: **96 passed / 0 failed**; optional media suite: **24 passed / 0 failed / 7 skipped** (FFmpeg-dependent, not codec acceptance); Flutter analyzer had no issues and **153 tests passed**; Windows capture lifecycle **3 passed / 0 failed**. Android SAF policy, APK, and Windows bundle jobs were skipped.
- **Android SAF / APK / Windows bundle:** **SKIPPED / NOT BUILT**; this is a Node receiver lifecycle fix, not device acceptance.
- **Device acceptance:** **NOT TESTED** — Android↔Windows transfer, clipboard, screen/audio mirroring and real input remain open.
- **Safety:** no new dependency, paid API, root, secret, auto-merge or `main` write. Pairing remains experimental, not production-approved privileged authorization.
- **Live Google Docs Handoff:** **SYNC FAILED** — no authorized Google Docs write/read connector was available; this repository ledger is not a substitute for the live Drive document.


## M76 CI follow-up — avoid ledger-only cancellation

- Updated `.github/workflows/ci.yml` to ignore push events where the only changed path is `docs/AUTONOMOUS_ACCEPTANCE.md`. This prevents a documentation-only acceptance update from cancelling a source/test run in progress. The workflow change itself triggers a new full validation run.
- **Workflow/source validation after this meta-change:** pending; record the new run only after it completes.
