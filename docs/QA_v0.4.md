# QA v0.4 — 2026-10-18

### Confirmed passing
- Existing Node tests include discovery validation, loopback UDP discovery / TCP PING, mutual SAS consent, signed identity verification, encrypt/decrypt PING, rejection on refusal/tampering/replay, persistent fingerprint trust, and integration agent state checks.
- Executed in container with Node v22: 9/9 passed.

### New code completed, unverified (no Dart/Flutter SDK)
- Flutter `PairingLab` with X25519 + Ed25519 + AES-GCM interoperable protocol implementation.
- Flutter pairing approval dialogs for incoming and outgoing sessions.
- App listener on 43829, outgoing manual IP or discovered device, secure persistence, trusted identity revocation UI.

### Necessary manual QA on actual Android and Windows before declaring success
- `flutter pub get`, `flutter analyze`, `flutter test`, and desktop/Android builds.
- Pair Android↔Windows on same Wi-Fi, hotspot, without Internet, then manually by IPv4.
- Confirm two displays show exact same 6-digit code, approval is required on both; mismatched/refused gets no trust.
- Verify fingerprint persists after app restart; verify trust revocation.
- Verify Flutter client with Node server: Node terminal asks YES while Flutter dialog shows same SAS. Re-test Node client against Flutter server.
- Close app / lock Android and ensure no accidental unattended access is assumed.

**No screen/control/files/clipboard are enabled by this lab.**
