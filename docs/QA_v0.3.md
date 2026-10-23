# QA record v0.3

Date: 2026-10-18

Command:

```sh
node --test tools/lan_probe/*.test.mjs
```

Test environment: container Linux / Node.js v22.16.0, actual IPv4 UDP/TCP loopback sockets.

Tests (9) passed:

1. Reject malformed discovery payloads, invalid addresses, invalid peer names, oversize discovery payloads.
2. UDP manual-IP discovery and TCP reachability, reject unauthorized command on 43828.
3. Two CLI pairing processes with local consent, matching displayed SAS, persisted peer fingerprints, encrypted PING/PONG.
4. Mutual verified key exchange and bidirectional AES-GCM message exchange.
5. Local rejection prevents trust and session initiation.
6. Modified signed server hello rejected.
7. Manipulated ciphertext rejected by AES-GCM authentication.
8. Replayed encrypted frame rejected by monotonic sequence check.
9. Previously pinned public identity recognized in a new independently agreed session.

Unverified: Flutter build / analyzer, Win11 / Android hardware tests, local Wi-Fi between physical devices, safety review/audit of crypto design, MediaProjection/Accessibility work, frame capture/stream/input latency.

**This success does not certify application-level security or functional remote control.**
