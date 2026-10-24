# Remote Control — Liquid Fusion v0.8 (Discoverable Windows Host Lab)

**Public GitHub:** https://github.com/amroalhamedi2022-hue/Remote-Control

Independent personal LAN remote-control project targeting **Xiaomi Pad 5 (Android/HyperOS), Android phone and Windows 11**. This source bundle is separate from NetKit. The locked design reference is `design/LIQUID_FUSION_MASTER_REFERENCE.png` (unchanged).

## GitHub source and builds

The complete v0.8 source and locked design were migrated to the public `Remote-Control` repository on 2026-10-23, by the owner's request. **Development and monitoring are done in this chat**, not handed off to Work or Codex.

The v0.9 build reliability PR adds `scripts/verify_build_artifact.py`, negative/positive structure tests and JSON SHA-256 evidence for real Android/Windows build outputs. Check `docs/STATUS_BOARD.md` for stage gates: Node lab tests alone do not prove a functioning remote-control application.

## New in v0.8

**A single experimental Windows pairing/H.264 host announces itself automatically** on UDP 43827 and supports harmless TCP reachability `PING` on port 43828. The actual pairing/view-only lab remains on TCP 43829 and still requires local code verification on both ends and an additional one-session host approval before capture. The Flutter discovery widget uses the same wire protocol. This eliminates the previous need to run a second discovery agent alongside the viewing host.

New `tools/lan_probe/host_presence.mjs` includes bounds checking, isolated probes and cleanup; three new tests verify actual UDP/TCP interoperability, unauthorized-command rejection, and the integrated host process. **31/31 total Node tests passed.** See `docs/HOST_DISCOVERY_v0.8.md` and `qa/NODE_TESTS_v0.8.tap`.

### What actually works vs. what is unverified

- **Tested in this runtime:** UDP discover/announce, TCP PING, Node lab encrypted pairing, JPEG and H.264 view-only transport with synthetic FFmpeg media, viewer handoff to a simulated FFplay sink, and fake-Flutter scaffolding contract.
- **Code prepared but NOT compiled:** Flutter UI, Android/Windows native project bootstrap, encrypted-pairing Dart implementation and MJPEG preview client.
- **Not yet delivered:** APK, Windows EXE, real capture on the user's MSI, Android H.264 decode, interactive mouse/keyboard control, low-latency remote desktop, Android hosting, and any unattended access. **Nothing here should be treated as a production secure remote controller.**

## Run tests (Node 22+, FFmpeg)

```sh
node --test tools/lan_probe/*.test.mjs tools/stream_lab/*.test.mjs tools/video_lab/*.test.mjs
```

## Test Windows host in view-only lab

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_windows_h264_lab.ps1 -TestPattern
```

Expect `PAIR_AGENT_READY 43829` and `DISCOVERY_READY UDP=43827 TCP=43828`. Compare 6-digit pairing codes before typing YES, and only type H264 on Windows when you explicitly want to share a screen or test pattern. For Windows viewer commands see `scripts/watch_windows_h264_lab.ps1`. To capture actual desktop remove `-TestPattern` (untested on physical Windows here). Node identity private key is plain text in this lab; do not expose ports to public internet or display sensitive information during trials.

### Optional Flutter view-only JPEG test (when a Flutter APK exists)

The Flutter v0.8 preview client still uses **MJPEG**, not H.264. To enable the matching view-only command on the Windows agent, deliberately add `-EnableFlutterJpegView`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_windows_h264_lab.ps1 -TestPattern -EnableFlutterJpegView
```

The receiving Flutter app requests `STREAM_START`. The Windows host must type **SHARE** before images are sent. The H.264 Windows viewer separately uses `H264_START` with host approval **H264**. Mixing the two without this explicit switch cannot work, so the UI should never claim H.264 Android playback yet. This interaction is currently **code-only and unverified on a real Android device**.

## How to obtain first debug APK and Windows bundle

**Flutter and Android SDK could not be installed in this execution environment:** no toolchains present; direct downloads failed because DNS/network access was blocked. The bundled `.github/workflows/ci.yml` therefore has **NOT been executed**; it is set up to attempt genuine builds in a **new, dedicated private GitHub repository** when code is uploaded there. Do not place this project in the existing NetKit or download-manager repository.

1. Create a new *private* GitHub repository for this project, then upload **the contents of this ZIP as the repository root** (the `.github/` directory must be included). This may be done in ChatGPT Work's browser or a local Git client.
2. Open **GitHub → Actions → Remote Control - validation and build**. Trigger *Run workflow*, or push a commit.
3. The **android-debug-apk** job generates a Flutter Android scaffold, runs `flutter pub get`, `flutter analyze`, `flutter test`, then invokes the **real** `flutter build apk --debug`. If it succeeds, obtain the APK from **Artifacts** as `liquid-fusion-v0_8-debug-apk`.
4. The **windows-debug-bundle** job attempts the native Windows Flutter build and uploads the whole debug runner directory. Verify both jobs: code has **never actually been compiled** in this runtime and build fixes may still be required.

Alternatively, on a Windows machine with Flutter + Android SDK installed, run `scripts/bootstrap_flutter.ps1` and then `cd app; flutter build apk --debug` (or `flutter build windows --debug`). Linux SDK path: `scripts/bootstrap_flutter.sh`. Never claim a successful build until an APK/EXE output is present and inspected.

## Security and limits

Discovery is untrusted. The pairing mechanism is a custom *laboratory* implementation, and the Node sample stores private keys as local plaintext files; replace both with reviewed production-grade transport and platform secure storage before granting input, clipboard or file access. There is no Root/ADB daily use in the plan; Android unattended screen capture limitations remain unchanged. References: `docs/ARCHITECTURE_ADR_001.md`, `docs/H264_ENCRYPTED_LAB_v0.6.md`, `docs/WINDOWS_LIVE_VIEWER_v0.7.md`, `docs/LICENSE_LEDGER.md`.

## Administration and GitHub execution (updated 2026-10-23)

The owner's existing repository is **public** and the normal ChatGPT conversation now handles all GitHub development, commits, pull requests, CI investigation and milestone management. Any prior instructions to create a separate private repo or delegate coding to Work are superseded. See `docs/STATUS_BOARD.md` and `docs/ADMIN_RULES.md`.
