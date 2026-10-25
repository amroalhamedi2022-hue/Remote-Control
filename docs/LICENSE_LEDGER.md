# Preliminary third-party component ledger

This prototype includes **none** of the following third-party native engines or source code. These are candidates/reference projects only. Review original LICENSE, transitive dependencies, patents and distribution obligations before integration.

| Project | General license note | Proposed usage |
| --- | --- | --- |
| Flutter | BSD-3-Clause framework (check Dart packages separately) | UI toolkit |
| cryptography ^2.9.0 | Apache-2.0 | **Added v0.4:** Dart Ed25519/X25519/HKDF/AES-GCM protocol lab |
| flutter_secure_storage ^11.2.0 | BSD-3-Clause | **Added v0.4:** encrypted identity/trust storage |
| libdatachannel | MPL-2.0 since v0.18 (check bundled dependencies) | Candidate P2P/WebRTC media/data transport |
| webrtc-rs | MIT/Apache-2.0 repository (verify chosen components and versions) | Alternative candidate |
| RustDesk | AGPL-3.0 | Reference only, no copied code |
| Sunshine | GPL-3.0 | Capture/encoding latency benchmark reference, no copied code |
| Moonlight | GPL licensed variants by repository | Viewer quality benchmark, no copied code |
| scrcpy | Apache-2.0 | Android display/input research only; its adb-based privilege route is not an Android app permission replacement |
| droidVNC-NG | GPL-2.0 | Android host/accessibility limits reference only |
| LocalSend | Apache-2.0 | Local file transfer UX/flow reference only |
| KDE Connect | GPL-family, varies by component | Clipboard/files reference only |
| MeshCentral | Apache-2.0 | Device-agent patterns reference only |

No claim is made here that a GPL-derived product can be shipped without obligations. Use in a private repository does not automatically remove distribution or network-service duties under licenses.

## v0.5: FFmpeg diagnostic screen capture
The preview lab **executes an external `ffmpeg` command** provided by the user/system; this ZIP does **not** bundle FFmpeg libraries or binaries. FFmpeg binaries can be LGPL or GPL depending on how they were compiled. If later bundling redistributable binaries, inspect the exact binary configuration and comply with FFmpeg's relevant license/attribution obligations; do not assume all builds are LGPL. `gdigrab` is supported as a Windows screen capture device in official FFmpeg documentation.

## v0.6: H.264 video lab
`tools/video_lab/h264_transport.mjs` invokes an **external user-provided** FFmpeg executable to encode H.264 into MPEG-TS. The ZIP includes **no** FFmpeg executable or codecs. Lab tests used external FFmpeg's `libx264` encoder in the local container; a `h264_nvenc` CLI option exists but was NOT hardware-tested. FFmpeg binary licensing depends on its actual build; `libx264` and bundled redistributable codecs may introduce GPL or other obligations. H.264 patent/licensing review will be needed before product distribution. No third-party RustDesk, Sunshine or Moonlight engine code was copied.

## 2026-10-24 — Android→Windows selected-file milestone
- `file_selector ^1.1.0`: Flutter-team maintained BSD-3-Clause plugin; Android native picker (SAF) and Windows supported. Source/license: https://pub.dev/packages/file_selector and https://pub.dev/packages/file_selector/license. This version is a direct dependency; preserve license notices when distributing.
- `crypto ^3.0.7`: Dart-team BSD-3-Clause streaming SHA-256. Source/license: https://pub.dev/packages/crypto. Used for file integrity, NOT for session authentication (existing `cryptography` AEAD handles that).
- Node receiver reuses existing `tools/lan_probe/file_transfer.mjs` without adding native dependencies. No proprietary or paid API.
- Production security acceptance remains BLOCKED: bespoke SAS/AEAD handshake has not received independent review; Android SAF provider behavior, Windows receiver and permission lifecycle need physical-device tests.
