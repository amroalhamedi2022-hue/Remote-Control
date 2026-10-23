# v0.7 — Windows desktop H.264 live viewer lab

**What this is:** An experimental Windows-to-Windows viewing workflow. The host captures up to 10 seconds of **real Windows desktop** (or an FFmpeg-generated test pattern). Every session is separately approved on the host. A remote Node viewer decrypts packets, validates MPEG-TS framing, and sends H.264 transport stream bytes to FFplay **during** transfer (not only after saving a file). Optional output records a `.ts` clip only on explicit request. The player window is native FFplay, **not the Flutter Liquid Fusion UI**. There is **no remote input**.

**This has not been tested on an actual Windows desktop or Android device in this runtime.** CI tests simulate FFplay as a byte-consuming child process and verify the received bytes are identical to the authenticated saved stream. Visual playback and latency on physical hardware remain unverified.

## Requirements

- Two trusted PCs on the same LAN (or one PC with two consoles for a loopback lab).
- Node.js 22+ on both sides; host also needs FFmpeg with `gdigrab` for Windows screen capture; viewer needs **FFplay** (check `ffplay -version`).
- Windows firewall must permit the host's inbound Node listener on **TCP 43829** on private networks. Do NOT forward this port on the router; do not use public Internet.
- The Node lab currently writes identity private keys in local files under `~/.liquidremote-lab` (do not use sensitive content).

## Quick start

On the **host** (MSI Sword 15), in the unpacked folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_windows_h264_lab.ps1
```

For a safe test pattern rather than the actual desktop:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_windows_h264_lab.ps1 -TestPattern
```

On a **second Windows computer** (viewer), in its copy of the project:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\watch_windows_h264_lab.ps1 -HostIp 192.168.1.42 -Seconds 3
```

Replace `192.168.1.42` with the real **private LAN address** of the host. If you want to explicitly save the clip, append `-SaveAs .\received.ts` (will not overwrite existing files).

Both sides must compare the displayed 6-digit pairing codes and type `YES`. Only then the **host** must separately type `H264` for the one screen-sharing session. FFplay opens on the viewer. The test is capped to **640x360, 12 fps, 1–10 seconds** by design. These are lab restrictions, not claims about final performance.

To stop: Ctrl+C in the host terminal or close the player window. No unattended access, keyboard input or mouse injection is enabled.

## Architecture and security limits

1. `pair_agent.mjs` performs experimental authenticated key exchange (Ed25519/X25519) and AES-GCM framing. This is **custom lab cryptography**, not yet audited or cleared for personal sensitive desktop use.
2. `H264Assembler` bounds size to 10 MB, checks chunk order and 188-byte MPEG-TS markers, and authenticates message chunks. End-of-segment SHA-256 is checked *after* the live player has already seen the earlier authenticated chunks. **The SHA-256 end check cannot be treated as a pre-decode safety gate.**
3. `H264LiveViewer` spawns FFplay **without a shell**, bounds queued stdin data, and stops if the player exits. The receiver can be configured to save a file too, but no file is written without `-SaveAs` / `--output`.
4. FFplay/FFmpeg decoders are separate third-party binaries. Use trusted recent builds and do not expose the host listener outside your trusted LAN.
5. For production we should replace the lab protocol with an audited media stack (likely WebRTC DTLS-SRTP) and use native hardware decoding for Android.

## What changes next

1. Create dedicated private GitHub repository and run CI; only then can a real Android APK / Windows Flutter bundle result be verified.
2. Fix any Flutter analyzer/compilation issues surfaced by CI.
3. Add approved hardware decoder + packetized, low-latency H.264 receiver in Android and Windows Flutter UI.
4. Benchmark actual end-to-end latency, then add remotely controlled keyboard/mouse under explicit session permissions.
