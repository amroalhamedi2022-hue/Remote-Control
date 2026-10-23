# v0.5 — Encrypted MJPEG Screen Preview Lab

## Goal
Show the first **view-only diagnostic screen image** received over an authenticated and encrypted LAN session. It is not the production renderer/encoder. The approved Liquid Fusion image remains unchanged.

## Completed in source
1. **Capture:** Windows CLI host invokes FFmpeg `gdigrab` (default desktop capture), scales to 640 width, encodes MJPEG at 4 fps. Optional `--test-pattern` uses FFmpeg `lavfi` instead and needs no screen access.
2. **Explicit consent:** Ed25519/X25519 SAS approval on **both** peers, then a distinct host-side `SHARE` approval when the viewer requests view-only access. Host must start with `--share-screen`; default pairing agent does not share screen.
3. **Encrypted framing:** up to 512 KiB/frame, ordered chunks of 2600 bytes are wrapped in the lab AES-256-GCM session. Frame boundary/sequence checks; frame drop on queue pressure. TCP connection; no Internet/relay/server dependency.
4. **Flutter client code:** `PairingLab.preview` + `PrototypeState.previewIp` render `Image.memory` when frame data arrives; `Disconnect` cancels the session. Manual IP → `View IP (lab)` works even if UDP discovery is unavailable.
5. **Node CLI preview:** `node tools/lan_probe/pair_agent.mjs --connect=HOST_IP --view-screen --max-frames=2 --output=frame.jpg`; write requires explicit output path, will NOT overwrite existing file.

## How to test (two devices)
**Windows host** (requires Node and FFmpeg on PATH):
```
powershell -ExecutionPolicy Bypass -File scripts/start_windows_preview_lab.ps1
```
Optional safe synthetic test source:
```
powershell -ExecutionPolicy Bypass -File scripts/start_windows_preview_lab.ps1 -TestPattern
```

**Android Flutter client** after app build (not yet tested):
- Connect both devices to same Wi-Fi / hotspot; no Internet necessary once dependencies installed.
- Open app -> Add device by IP -> enter Windows host IPv4 -> `View IP (lab)`.
- Compare the six-digit SAS and approve on each device. Then type `SHARE` on Windows only for the requested screen-sharing session.
- Screen should show slow JPEG image frames with a `VIEW-ONLY LAB` watermark. To stop use `Disconnect` or Ctrl+C on host.
- Host Windows Firewall should allow inbound TCP port **43829** only on **Private LAN networks**. Don't forward/route this port to the Internet.

**Node-to-Node verification** (already executed in container):
```
node --test tools/lan_probe/*.test.mjs tools/stream_lab/*.test.mjs
```
Uses FFmpeg test pattern and ephemeral 127.0.0.1 sockets. Does NOT verify real Windows screen capture or Dart↔Node interoperability.

## Important limitations
- MJPEG+small encrypted JSON chunks are **inefficient**; image quality/FPS are intentionally limited. Not a low-latency production streaming path. Move to WebRTC/DTLS/SRTP and hardware H.264 later.
- The bespoke security protocol is unaudited and **not production ready**. Node private identity material is stored as local plaintext fixture; do not distribute as a secure remote desktop product.
- No remote input, Android host, unattended access, clipboard, audio or files. No bypass of Android permission prompts.
- Flutter SDK and Windows+Android native platform toolchains are absent from this build environment, so Flutter has NOT been compiled or run. A small Flutter UI test is included for CI but not executed here. `flutter_secure_storage` Windows may require C++ ATL in Visual Studio. See https://pub.dev/packages/flutter_secure_storage
- AndroidManifest local-network permissions and OS-level background behavior require real-device testing. This preview requires active local consent; it does not start capture in the background.

## Next priorities
1. Run Flutter analyzer/build via GitHub Actions on a new private project repository, then on actual devices; resolve any Dart↔Node mismatch.
2. Replace experiment with reviewed DTLS/WebRTC identity-bound transport and H.264 native decode/encode.
3. Only after that, add scoped, user-approved remote input APIs on Windows and AccessibilityService on Android.
