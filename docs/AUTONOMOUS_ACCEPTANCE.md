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
