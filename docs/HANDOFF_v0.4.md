# Liquid Fusion Remote Control — v0.4 Handoff

## Approved design (unchanged)
`design/LIQUID_FUSION_MASTER_REFERENCE.png` is the canonical visual reference.

## Implemented now
- Flutter UI: original liquid/glass layout, dark/light responsive devices/remote preview pages.
- Flutter LAN discovery via UDP port 43827, TCP reachability probe 43828.
- **NEW Flutter experimental pairing**: `flutter/lib/security/pairing_lab.dart`, running TCP on 43829; signed Ed25519 identity (stored as encrypted seed using `flutter_secure_storage`), ephemeral X25519, mutually compared 6-digit SAS, authenticated AES-256-GCM encrypted PING/PONG, remembered peer public-key fingerprints, manual IP pairing and revocation in Settings.
- Existing Node interoperability test agent (`tools/lan_probe/pair_agent.mjs`) speaks the same *experimental v1 wire format*.
- UI shows `Paired · encrypted test passed` only after authenticated PING/PONG. Does not enable screen, input or files.

## Test status, important distinction
- Node UDP/TCP and secure-pairing integration suite: **9/9 passing in container** (`node --test tools/lan_probe/*.test.mjs`).
- Flutter code was inspected but **not compiled**: no Flutter/Dart SDK available in the task environment. Cross-language Dart↔Node pairing and real Android/Windows behavior remain **unverified**. The Dart/Node interoperability is an engineering hypothesis until a device test passes.
- Do **not** call v0.4 a working Android APK, tested interoperable pair, or production-secure system.

## Security caveats / release blockers
- Custom handshake exists solely for the lab. Replace with audited Noise / WebRTC DTLS and bind authorization scopes to authenticated device identity before any remote access.
- `flutter_secure_storage` encrypts data at rest; this lab still extracts the Ed25519 seed into app memory. Plan non-exportable OS-backed signing keys when viable.
- Discovery names/IP are unauthenticated. Only verified fingerprints are identities. Paired status in UI is **this-session encrypted test**, not unattended access.
- Permission scopes (view screen, input, files, clipboard) are **NOT** implemented. Never grant them based on plain UDP discovery or cached names.
- Do not automatically accept pairing; both sides explicitly compare code and approve.
- Avoid network expose beyond LAN; Windows Firewall and Android OS may prompt/limit. Android foreground/background restrictions still apply.

## Windows handoff (Flutter installed)
1. Extract ZIP to local writable path.
2. Run `powershell -ExecutionPolicy Bypass -File .\\scripts\\bootstrap_flutter.ps1` from project directory.
3. `cd app; flutter analyze; flutter run -d windows` (SDK/Visual Studio Windows desktop tools and ATL must be installed).
4. On a second device, run the Flutter app, select discovered peer, press `Pair securely`; or use Manual IP → Pair IP.
5. Both show SAS; compare and approve on each. Look for **Encrypted PING succeeded**. This is only a connectivity proof.
6. Or on Windows run `node tools/lan_probe/pair_agent.mjs --listen` and have Flutter use Manual IP → Pair IP; compare code to Node terminal, type `YES` on Node if matching.
7. Click Settings → Revoke to discard trust record. If pairing is interrupted, retry manually.

## Next priorities
1. **Validate Flutter compilation and two-device pair interoperability.** Fix any Dart/Node serialization and plugin issues found.
2. Establish reviewed DTLS/WebRTC peer session with strong identity binding; implement permission-scoped RPC.
3. Add Windows desktop capture + H.264 hardware encode and Android decode/render.
4. Implement authenticated input events only after explicit authorization and a prominent stop control.
5. Android MediaProjection+Accessibility Host, media, file/clipboard, offline stability, performance, packaging.

Do not touch NetKit. Store private code on project-only GitHub repo when created; big assets on Drive. Work mode may be used for longer implementation/QA stages.

## CI
`.github/workflows/ci.yml` provides Windows Flutter analyze/bootstrap and Node tests when pushed to a GitHub repository. This workflow has NOT run in this task environment. Dependencies must be fetched once when preparing build machines; runtime connection needs no Internet.
