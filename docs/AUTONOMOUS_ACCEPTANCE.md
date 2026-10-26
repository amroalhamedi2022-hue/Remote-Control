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
