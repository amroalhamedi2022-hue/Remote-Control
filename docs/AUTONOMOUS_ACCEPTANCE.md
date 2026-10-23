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
