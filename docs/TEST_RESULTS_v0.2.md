# Verified test report — Liquid Fusion LAN v0.2
Date: 2026-10-18

## Actually executed in build environment

Command:

```bash
node --test tools/lan_probe/agent.test.mjs
```

Result:

```text
TAP version 13
# Subtest: parser rejects malformed, forged names and oversized packets
ok 1
# Subtest: actual UDP manual-IP discovery + TCP probe exchange over loopback
ok 2
1..2
# tests 2
# pass 2
# fail 0
```

- The integration test starts a live Node UDP broadcast/discovery agent and TCP health endpoint on ephemeral loopback ports, sends a UDP DISCOVER message, reads ANNOUNCE with expected TCP port, and exchanges TCP PING/PONG.
- The test also sends an unauthorized command to the TCP socket and confirms it is rejected without response.
- `node --check` succeeds for protocol and fixture scripts.
- A lightweight Dart lexical bracket check passed for all 4 Dart source files. **This is NOT a Dart analyzer or compiler test.**

## Not tested / explicitly blocked

- `flutter analyze`, Android APK build, Windows EXE build — Flutter SDK not installed.
- Android permissions/background broadcasts/HyperOS behavior — no physical device in tool environment.
- LAN traffic between physical devices, firewall, hotspot, mDNS — not tested.
- Authentication/pairing, encryption, video/screen capture, mouse/keyboard, audio, file transfer, clipboard — not yet implemented.

## Next acceptance gate

1. Run `scripts/bootstrap_flutter.ps1` on Windows with Flutter SDK and correct build toolchains.
2. Fix actual Flutter analyzer/compiler errors, if any, and take screenshot comparisons to locked image.
3. Run Windows agent + tablet Flutter over the same offline Wi-Fi, then reverse direction.
4. Add secure pairing and identity pinning only after real discovery works.
