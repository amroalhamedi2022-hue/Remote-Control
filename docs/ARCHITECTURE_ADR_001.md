# ADR-001 — Native Stream Engine + Shared UI (PROPOSED, NOT LOCKED)
Date: 2026-10-18
Status: Provisional; pending native latency and license tests.

## Decision

- Shared visual shell: Flutter (Android + Windows), with Liquid Fusion tokens and adaptations in each form factor.
- Shared trusted session/identity/discovery component: Rust library in a later milestone. Do not build crypto or networking from scratch for production.
- Android host native integration: Kotlin, MediaProjection with explicit OS consent and foreground service as required, AccessibilityService for permitted gesture dispatch, MediaCodec for hardware codecs, and screen-content/audio restrictions enforced by Android.
- Windows host native integration: Windows Graphics Capture or Desktop Duplication depending on capture target, native hardware encoder (Media Foundation/NVENC when available), standard Windows input APIs within security limits.
- Video client: native hardware-decoded surface/texture attached to Flutter UI. Do not repaint full video frames in Dart or apply blur/shaders over video.
- LAN transport candidate: libdatachannel's WebRTC DataChannel + SRTP media with **local signaling**, no cloud STUN/TURN dependency, no external rendezvous. Benchmark before final adoption. Evaluate direct TLS-based transport only if measurable advantages exist and the attack surface is managed.

## Why not fork RustDesk as default?

RustDesk demonstrates a strong cross-platform approach but is AGPL-3.0. A full fork would couple the app to its architecture and create compliance requirements on distribution/network use. Reviewing design and algorithmic concepts is fine; if copying code is ever considered, perform a legal/engineering review first.

## Offline candidate connection flow

1. Host advertises temporary mDNS/DNS-SD presence, or controller adds Host's local IP.
2. Short-lived local signaling exchange (server runs on one of the personal devices only) negotiates transport and device identities.
3. First pairing: both users confirm a comparison code or scan an authenticated out-of-band QR. Store long-term public device identities in encrypted OS-provided key storage. QR in prototype is NOT scannable.
4. Every subsequent session verifies peer identity and ephemeral session key; do not authorize merely from IP/MAC or untrusted mDNS name.
5. Permissions are separate for view, remote input, clipboard and file transfer. Host sees session state and can revoke at any time.
6. Connection refusal and limited permissions are honest statuses, not silently bypassed.

## Threat model and security invariants

- LAN peers may be malicious; discovery is untrusted until identity check.
- Use well-reviewed standard crypto via well-maintained libraries, including replay protection, forward secrecy, authenticated channel binding. No homegrown encryption.
- Protect against QR spoofing, replayed pairing codes, fake device advertisements, unauthorized clipboard/file exfiltration and stale trusted devices.
- Keep keys in Android Keystore / OS credential protection on Windows; never sync keys through Drive, commit them to GitHub, or log secrets.
- State visibly when someone views/controls a device. Support immediate stop, revoke trust, optional session confirmation, session timeout and local audit log.
- Require explicit opt-in before clipboard transfer or unattended host on Windows; avoid unattended Android promises because MediaProjection prompts and lockscreen conditions vary.
- Handle password/PIN and Windows secure desktop as protected areas, not bypassable app features.

## Performance gates for a later native proof

1. Host Windows -> Android viewer. First produce live H.264 720p30 with hardware decode; test 1080p60 and HEVC after stability.
2. Measure glass-to-glass video latency AND input-to-photon latency separately, with actual logged clocks.
3. Simulate 5%, 10% packet loss, jitter and 2–20 Mbps throughput; benchmark adaptation quality.
4. Low latency policy: favor frame freshness over queue length; no large buffering; cap encoder rate; send input with bounded priority.
5. Record battery/GPU/CPU/heat on Xiaomi Pad 5 and phone, then apply reduced UI effects.

## Pending engineering decisions

- Which mature WebRTC binding/native client gives the best Android decoder pipeline?
- Are H.264 patent/redistribution terms or shipping binary codec licenses relevant to packaged builds?
- mDNS permissions/discovery behavior under precise HyperOS version, Android API level and hotspot isolation.
- Windows service vs per-user agent, host after login and UAC secure desktop strategy.
- Verification of Flutter UI implementation against the approved screenshot before building plugin bridges.

## Primary references

- https://docs.flutter.dev/platform-integration/desktop
- https://docs.flutter.dev/ui/adaptive-responsive
- https://github.com/paullouisageneau/libdatachannel
- https://github.com/webrtc-rs/webrtc
- https://github.com/rustdesk/rustdesk
- https://developer.android.com/media/grow/media-projection
- https://developer.android.com/about/versions/15/changes/foreground-service-types
