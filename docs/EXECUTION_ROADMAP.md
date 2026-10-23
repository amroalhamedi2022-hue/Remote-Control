> **Operating model update 2026-10-23:** This roadmap is executed entirely in the CURRENT ChatGPT chat after Work performs only initial GitHub repository creation/import. See `docs/OPERATING_MODEL.md`.

# Execution Roadmap — phase-gated, no fake progress

Each gate requires evidence in `docs/STATUS_BOARD.md`, and no gate is complete solely because the code was written. main ChatGPT conversation may prepare later-phase research in parallel, but not claim those phases done until prerequisites pass.

| Gate | Priority / deliverables | Definition of acceptance |
|---|---|---|
| **M0 — Import & Audit** | PRIVATE dedicated GitHub repo; copy full v0.8 as repository root including hidden `.github`; record source hashes, README and license ledger, reproduce 31 Node tests; set restrictive CI permissions and PR discipline | Repo visibility verified PRIVATE; source tree audited; real Actions run and links; blockers classified; no edits to other repositories |
| **M1 — Real builds** | Fix Flutter bootstrap/analyze/test/Gradle; debug APK and Windows desktop debug bundle; build logs and artifact uploads | `flutter analyze` and `flutter test` passing; **real** APK and complete Windows runner exist, size/SHA-256 recorded; CI logs inspected; no claim of device verification |
| **M2 — Offline LAN connect** | Windows host/Android client discovery/manual IP; dependable pairing UX, host confirmation, revoke, reconnect handling; replace experimental authentication for production | Real Windows↔Pad 5 offline Wi-Fi/hotspot tests, consent/reject/revoke/reconnect logs; no plaintext keys; no public servers, negative security tests |
| **M3 — View only** | Windows actual live screen capture → Android display; first compatible proof then H.264 hardware path; orientation, FPS, resolution settings | Real device stream verified, black/protected screens handled honestly; measured latency, FPS, CPU/RAM, bitrate, disconnections; tested with internet blocked |
| **M4 — Windows input** | Secure mouse/keyboard and shortcuts, touch-to-mouse gestures, access control and stop button | Physically verified Windows control from Pad/phone, reject unauthorized input, UAC/secure desktop limitations documented |
| **M5 — Android host** | MediaProjection/Accessibility, optional internal audio if permitted; Android→Windows view/control within platform policy | Actual Pad/phone-host session tested with local consents and Android/HyperOS constraints; lock/reboot/foreground behavior tested, no bypass claim |
| **M6 — Android ↔ Android** | Phone↔Tablet host/controller role switching, rotation and gesture support, stability | Both directions on physical devices with explicit acceptance and limitations |
| **M7 — Integration** | Clipboard, file/folder transfer where platform allows, media/audio, permissions/settings, multi-session and reconnect; hotspot isolation troubleshooting, optional Wi-Fi Direct feasibility review | Real permissions/security/transfer integrity, clipboard privacy, crash/recovery and multi-session results documented |
| **M8 — Performance/finish** | Hardware codec negotiation H.264/HEVC when supported, adaptive bitrate, low latency, visual fidelity, power modes, regression/security/perf audit | Representative hardware/weak-network battery and latency measurements, acceptance matrix complete, signed/reproducible installable builds delivered |

## Execution order for the MAIN CHAT's first development batch (after main ChatGPT conversation GitHub import)

1. Audit v0.8 and document real defects, maintain 31/31 Node baseline or fix regressions.
2. Ensure dedicated repo exists and is private, then import the **unchanged** v0.8 source plus management documents; do not nest source one directory deeper.
3. Execute CI on commit; inspect logs and fix every Flutter/analyzer/build blocker on PR branch. Preserve `design/LIQUID_FUSION_MASTER_REFERENCE.png` SHA.
4. Produce APK and Windows runner artifacts with hashes; compare actual Flutter UI to design reference with captured screenshots where possible.
5. Report M0/M1 evidence and blockers; only then move into M2/M3. Never mark M3 done based on JPEG/H.264 synthetic FFmpeg streaming from Node labs.

## Mandatory completion criteria for each feature

`Requirements traced` + `Implementation present` + `Tests with negative paths` + `Artifact built` + `On-device behavior verified (if device-dependent)` + `Security review passed (if privileged)` + `Visual comparison (if UI)`.

No percentages based on estimates alone. Report an unmet gate as `BLOCKED` or `PARTIAL`, not complete.
