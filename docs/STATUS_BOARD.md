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
