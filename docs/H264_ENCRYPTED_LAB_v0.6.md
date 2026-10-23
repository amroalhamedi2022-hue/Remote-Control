# v0.6 — Encrypted H.264 video transport laboratory

## Proof of work (exact scope)

A user-approved Windows host can invoke local FFmpeg, encode a **short** 1–10 second **H.264** clip inside MPEG-TS, and send encrypted, ordered chunks to a separate Node.js CLI viewer. The viewer writes the clip **only when explicitly given** an output `.ts` path. A `ffprobe`/`ffmpeg` decoder test verifies the received bytes represent actual decodable H.264. Connection and codec processing use local LAN sockets only (no Internet or relay required after dependencies are installed).

**This is NOT the Android Flutter viewer's video codec:** Flutter still uses the earlier low-FPS MJPEG view-only code. H.264 streaming, hardware decode, RTP/WebRTC, audio and remote input are not integrated into Flutter. Tests use generated FFmpeg test pattern and loopback sockets, NOT a Windows desktop, Xiaomi Pad 5 or phone. The existing Node pairing protocol is experimental and unaudited, with plaintext local lab key files. Not safe for sensitive screen sharing or internet exposure.

## Test steps between Windows computers (or for local loopback)

Prerequisites: Node.js 22+ and FFmpeg+FFprobe installed on both machines, access to TCP port 43829 on a private LAN, **physical agreement by owners of both peers**. Do **not** forward this port to the Internet. Host must run interactively, not as unattended service.

**Host Windows terminal:**

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start_windows_h264_lab.ps1
```

For source testing without recording any real desktop, use `-TestPattern`.

For an *optional* compatible NVIDIA build with NVENC exposed, use `-Encoder h264_nvenc` (untested, may fail; automatic hardware fallback is **not** implemented). Defaults to software `libx264`, which was used in local tests.

**Viewer terminal:**

```powershell
node tools/lan_probe/pair_agent.mjs --connect=192.168.1.42 --view-h264 --max-seconds=3 --output=received.ts
```

The viewer and host must each independently inspect and approve the same six-digit verification code (`YES`). Then **the host alone** types `H264` to approve sharing just this session. On the viewer, `received.ts` is written without replacing an existing file, and an incomplete file is deleted upon failure. It may contain private screen content: keep it local and delete it when no longer needed.

To play locally using FFmpeg tools:

```powershell
ffplay -autoexit received.ts
ffprobe -v error -show_entries stream=codec_name,width,height -of default=noprint_wrappers=1 received.ts
```

For the legacy low-FPS Flutter client, use `scripts/start_windows_preview_lab.ps1` and the existing `View IP (lab)` button, **not** this H.264 mode.

## Implementation and boundaries

- `tools/video_lab/h264_transport.mjs`: allowlisted FFmpeg capture/encoder arguments, 188-byte MPEG-TS packet sync validation, stream max 10 MiB, 2400-byte encrypted chunk bounds, sequential offsets and SHA-256 end verification.
- `tools/lan_probe/pair_agent.mjs`: `--share-h264` opt-in, separate `H264` console approval, `--view-h264` explicit path. `--share-h264` does *not* implicitly enable legacy MJPEG.
- `tools/video_lab/*.test.mjs`: data tampering, invalid codec, bounds/offsets, encrypted TCP test pattern, FFprobe decode, independent Node command-line host/viewer smoke, denial after pairing.
- `scripts/bootstrap_flutter.sh` and `.ps1`: Android minSdk=23 for secure storage and native Flutter scaffolding. CI jobs attempt actual Android debug APK and Windows debug builds; no builds were run in the current container.
- `design/LIQUID_FUSION_MASTER_REFERENCE.png`: still canonical and unmodified; UI styling remains locked.

## Known engineering debt

1. Replace custom lab pairing and JSON chunk transport with audited authenticated WebRTC (DTLS/SRTP, certificate/identity binding). Avoid unnecessary MPEG-TS storage for production interactive playback.
2. Build Flutter, fix analyzer/compiler issues using CI logs, and verify Dart↔Node MJPEG interoperability on two actual devices. Until then, do not claim Android functionality works.
3. Add native H.264 decoder and low-latency renderer on Android (MediaCodec), then integrate capture via Windows native APIs and hardware encoding; benchmark bitrate/latency, dropped frames, battery and CPU.
4. Remote input is disallowed until the transport is authenticated, permissions are scope-limited, and explicit Windows host consent is implemented. Android host will require MediaProjection and Accessibility with OS limitations.
5. Node lab identity material persists as unencrypted JSON files. **Never ship it as an unattended access system.**
6. FFmpeg is not redistributed in the repository. `libx264` builds may carry GPL obligations and H.264 patents may apply to future distribution. Inspect exact FFmpeg executable license before packaging.
