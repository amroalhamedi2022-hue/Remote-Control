# Experimental pairing lab — v0.3

## Exact scope / real result

The `tools/lan_probe/` executable now has two **separate** interfaces:

- `agent.mjs` — UDP discovery on 43827 + *unauthenticated reachability-only* TCP PING on 43828. It never accepts input commands, clipboard data, files or screen frames.
- `pair_agent.mjs` — experimental, mutually approved cryptographic exchange on TCP 43829. After both people explicitly type `YES` when comparing the six-digit code on both screens, it can exchange only **encrypted** PING/PONG messages. No remote-device privileges.

The Flutter interface from v0.2 is **not yet connected to this experimental handshake**. Never call this a finished Android pairing feature.

## How to test on two machines (requires Node.js 22+, local network)

On the Windows PC acting as temporary host:

```powershell
node tools/lan_probe/pair_agent.mjs --listen
```

On the other device **if Node is installed there**, or in another terminal on Windows using `127.0.0.1` for loopback:

```powershell
node tools/lan_probe/pair_agent.mjs --connect=192.168.1.10
# same-machine alternative:
node tools/lan_probe/pair_agent.mjs --connect=127.0.0.1
```

On both consoles compare the **six-digit SAS code** out-of-band. ONLY if identical, type exactly `YES` on each machine. If codes differ, **cancel**. The receiving host must explicitly approve. Successful results print `PAIR_OK`; the initiating device prints `SECURE_PONG` after an encrypted request/response.

Additional CLI:

```powershell
node tools/lan_probe/pair_agent.mjs --list
node tools/lan_probe/pair_agent.mjs --revoke=<exact-peer-fingerprint-or-unambiguous-prefix>
node --test tools/lan_probe/*.test.mjs
```

On Windows firewall, allow Node **only on your private LAN** if testing across devices; never forward TCP 43829 or open it to the Internet. It has no local host authorization other than confirmation and is an experimental fixture.

## Security model — laboratory only

1. Ed25519 keys identify the two participants; each signs an X25519 ephemeral public-key handshake with session nonces. The responder signature binds the initiator's hello. Signatures are verified.
2. Both calculate a short authentication string (SAS) from the shared key and transcript. Human code comparison is **necessary** to detect an active network impersonator. The app never uses a remotely supplied SAS as proof.
3. Both MUST provide independent, local approval. The encrypted `CONFIRM` exchange gates trust-store writes.
4. Ephemeral X25519 provides fresh per-session key exchange; directional HKDF-SHA-256 keys protect AES-256-GCM records. A deterministic *direction + increasing sequence number* nonce prevents nonce reuse under the same ephemeral session key. In-order counters reject replayed envelopes.
5. Peer public identities are pinned by SHA-256 fingerprint into a local trust file. Recognized identities are displayed as recognized, but this test agent **still requires an explicit YES on every session**.

### Critical limitations before production

- The handshake is a **custom lab exercise and has not been independently security audited**. It must NOT be used as the production device-access layer. Favor standard WebRTC **DTLS/SRTP** with confirmed peer fingerprints or an established Noise framework. Do not copy experimental crypto unchanged to Flutter.
- The Node fixture stores its identity's **private key unencrypted** in `~/.liquidremote-lab/identity.json` (mode 0600 when supported), **not** Windows DPAPI / Android Keystore. This is for testing only. Don't deploy it to untrusted/shared machines or use the keys for production.
- No unauthenticated input commands are permitted, but the standalone discovery TCP PING is intentionally public. Discovery broadcasts are untrusted and must never grant authorization.
- Not yet tested between actual Xiaomi Pad 5, phone, and Windows 11. The automated tests use real localhost sockets, not a physical Wi-Fi network.
- No unattended access, no playback video/audio, no file transfer, no application clipboard in this version.
- This lab intentionally asks user approval on every session; production remembered trust and unattended access policies will be separate, strictly controlled options.

## Cross-platform production integration gate

1. `flutter analyze` and native builds on Windows + Android must pass. SDK was absent in authoring environment.
2. Define native secure-key storage: Android Keystore; Windows DPAPI/CNG-backed secrets; support revocation/rotation.
3. WebRTC/DTLS peer certificate fingerprints must be bound to a peer identity after out-of-band SAS confirmation. LAN addresses and discovery names are never identity signals.
4. Verify Windows firewall prompts, Android LAN/background restrictions and MediaProjection per-session consent.
5. Verify pairing over normal Wi-Fi and hotspot; detect network isolation; encrypted session must **not** proceed on TLS/DTLS identity change without approval.
6. Require permission separation (`view`, `control`, `clipboard`, `files`, `audio`) and audit logging before exposing privileged actions.
