# v0.8 — Single Windows host automatically discoverable by Android/Windows Flutter UI

The experimental Node pairing host now opens these **separate** listeners by default when started with `--listen`:

| Service | Transport | Port | Security and function |
|---|---|---|---|
| Device discovery | UDP | 43827 | Unauthenticated local-only announcements; never a source of trust |
| TCP reachability | TCP | 43828 | Responds solely to `PING` with `PONG` (diagnostic, no privileges) |
| Interactive pairing & optional view-only stream | TCP | 43829 | User confirmation on both sides, and a fresh host consent per screen view |

## Windows host test

To let a **future Flutter app** request view-only JPEG frames, append `-EnableFlutterJpegView` when starting the PowerShell host. Flutter sends `STREAM_START`, whereas the Windows-only H.264 viewer sends `H264_START`; they are different protocols. A JPEG preview still requires entering `SHARE` on the host and cannot control keyboard or mouse.


```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_windows_h264_lab.ps1 -TestPattern
```

Wait for **PAIR_AGENT_READY** and **DISCOVERY_READY** messages. For actual desktop test remove `-TestPattern`; this does **not** silently approve video—an explicit `H264` approval on Windows is still required per session. Never forward ports to the internet. On the same private Wi-Fi/hotspot, an Android or Windows Flutter UI instance should detect the host via UDP broadcast. **This has not been validated with a built Flutter app on devices yet.** If multicast/broadcast is blocked by Wi-Fi isolation, use manual IP pairing instead.

Do not run `tools/lan_probe/agent.mjs --serve` at the same time as this host on the same computer, because both would compete for UDP 43827 / TCP 43828. Suppress discovery deliberately with `node tools/lan_probe/pair_agent.mjs --listen --no-discovery` (manual IP pairing still functions). Custom discovery/probe ports (`--discovery-port`, `--probe-port`) are intended only for laboratory tests; Flutter production UI expects defaults.

### Validation executed in v0.8

- Node server accepted a real UDP DISCOVER and replied with the Flutter wire-compatible ANNOUNCE.
- A real TCP client received PONG only for the PING command. A non-PING action got no response.
- Spawned full pairing host process: verified `DISCOVERY_READY` and successful UDP and TCP probes.
- Exhaustive combined Node lab suite: 31/31 tests passed. **No Flutter runtime, Android app or Windows desktop capture was verified**.

### Outstanding security limitations

- LAN advertisements and IP addresses are untrusted; identity is bound only by the locally confirmed pairing code. The custom cryptographic handshake is still a laboratory protocol pending replacement with a standardized, reviewed transport.
- Node lab identity private key is written to user-local storage as plaintext; no unattended mode, remote input, or privileged access may rely on it.
- Windows firewall must allow localhost/LAN on the private network; broadcast restrictions vary with routers and OEM devices.
