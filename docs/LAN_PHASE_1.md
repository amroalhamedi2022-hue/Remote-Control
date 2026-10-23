# LAN Phase 1 — Real discovery and connectivity probe (v0.2)

## Implemented

- Android/Windows Flutter `LanDiscovery` binds a UDP discovery socket on port 43827.
- Announces presence every 5 seconds; responds to DISCOVER with ANNOUNCE.
- Shows discovered peers as the device cards of the approved Liquid Fusion design.
- Device cards that have **not** been discovered remain labeled design placeholders.
- Supports entering IPv4 manually with optional UDP port; no external server.
- Listens on TCP 43828 for a **PING/PONG** connectivity probe only.
- Discards invalid JSON or wrong protocol, caps datagrams to 1200 bytes, ignores self-ID.
- Expires stale devices after 20 seconds.
- Closes listeners when the app is disposed.
- Includes a zero-dependency Node.js protocol fixture + integration tests.

## NOT implemented

The LAN messages are **UNAUTHENTICATED**. Seeing an address never grants trust or control. Pairing, encryption, certificate pinning, screen/video/audio, input, clipboard and file transfer remain **NOT implemented**. An active LAN probe is not a remote control session. The Node fixture never receives commands, file contents or credentials.

The ID is an ephemeral startup random identifier, **not** a persistent device identity. Do not treat it as a trust anchor. Secure long-lived identity will be introduced only with proper authenticated key exchange and OS key storage in a future phase.

No STUN, TURN, cloud or Internet connection is used by this component. Broadcast on Wi-Fi/hotspot may fail because of AP/client isolation, firewall, battery settings, Android OEM restrictions and multiple network adapters. Manual IP sends a direct unicast DISCOVER to the target UDP port.

## Protocol (provisional, versioned)

Datagram (UTF-8 JSON, <=1200 bytes):

```json
{"protocol":"liquid-remote.discovery.v1","kind":"DISCOVER","id":"0123456789abcdef0123456789abcdef","name":"Win-Laptop","platform":"Windows","tcpPort":43828}
```

`kind`: DISCOVER or ANNOUNCE. UDP 43827 by default. Respond directly to requester's sender address and UDP source port. Field `address` is never trusted from JSON; use source IP only. TCP health endpoint responds to `PING\n` with `PONG\n`, and rejects other messages. Ping timing is **TCP round-trip only**, not video or input latency.

## Offline test on one Windows device (requires Node.js 20+)

Terminal 1:

```powershell
node tools/lan_probe/agent.mjs --serve
```

Terminal 2:

```powershell
node tools/lan_probe/agent.mjs --probe=127.0.0.1
node tools/lan_probe/agent.mjs --ping=127.0.0.1
node --test tools/lan_probe/agent.test.mjs
```

## Cross-device LAN test

1. Connect laptop and Android tablet to the same Wi-Fi/hotspot (no Internet required).
2. On Windows, run `node tools/lan_probe/agent.mjs --serve`. Allow **Private network** UDP 43827 and TCP 43828 in Windows Firewall if asked; do not expose the ports to the public Internet.
3. Run the Flutter app on Android. The laptop should appear in the main Devices cards. If it does not, tap Add Device and enter the laptop's LAN IP (e.g. `192.168.1.7`).
4. Tap the discovered laptop card. A TCP probe result appears. No remote desktop or pairing occurs.
5. Next: run the native Flutter Windows build and repeat from Android -> Windows and Windows -> Android. Do not run Node and Flutter on the *same host* with the default ports simultaneously.

## Security and reliability notes

- Unknown discovered device names/platform strings are **untrusted**, visual labels only.
- Bind listeners to local device ports for lab use; use OS firewall network profiles to restrict access to private networks. Don't forward ports or expose to WAN.
- UDP broadcast can be blocked; manual IPv4 is a required fallback. This is a basic broadcast service, **not** mDNS.
- A same-host test has been run using the Node fixture; Flutter SDK compilation and physical Android/Windows end-to-end testing have **not** been run in this environment.
- Before allowing any privileged operation, implement a reviewed authenticated pairing protocol with key confirmation and encrypted transport; security must not rely on a 6-digit PIN alone.
