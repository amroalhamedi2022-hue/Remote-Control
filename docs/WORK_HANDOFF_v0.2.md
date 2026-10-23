# Work handoff — Remote Control / Liquid Fusion v0.2

## Immutable decisions

- This is a separate application from NetKit.
- The approved `design/LIQUID_FUSION_MASTER_REFERENCE.png` is the specific visual target. Minimize unnecessary departures from its three-zone Windows layout and responsive Android layouts.
- Phone ↔ Tablet ↔ Windows. All hosts/controllers. Offline LAN, no external relay required.
- Do not claim complete Android unattended screen capture without consent; follow MediaProjection + Accessibility system limitations.
- No root or ADB in ordinary daily operation.
- GitHub Private for app source; Google Drive for larger project assets if useful. No current repository created here.

## v0.1 summary

Visual preview, Flutter source draft, design lock, comparison docs. No live network.

## v0.2 changes

- `flutter/lib/network/lan_discovery.dart`: versioned UDP discovery and TCP reachability.
- `flutter/lib/models/app_state.dart`: LAN state forwarded into UI.
- `flutter/lib/main.dart`: real peers replace sample device cards when discovered; manual IP now emits a UDP unicast probe; tap a peer runs TCP RTT (unpaired only).
- `tools/lan_probe/*.mjs`: Node local agent and tests; true socket-based tests pass on loopback.
- `scripts/bootstrap_flutter.ps1`: generate Android and Windows project scaffolding, add Android INTERNET/ACCESS_NETWORK_STATE to main manifest, analyze.

## Red lines

- Local peer announcements are untrusted, and node IDs are temporary. Never use IP, a sample QR or 6-digit code alone as authority. Introduce encrypted pairing and persistent pinned identity before remote input/files/clipboard.
- Current session viewport and QR are visual placeholders, even if live peer discovery is available.
- Do not reuse the Node fixture as a production host without security architecture review; it is a health-check agent only.
- Never call a TCP PING roundtrip a streaming input-to-photon measurement.

## Immediate next run

Run Flutter bootstrap/analyzer, then build Windows + Android. Record actual compiler feedback. Test physical same-Wi-Fi UDP announcement and direct-IP fallback both ways. Lock down private firewall profile. Move next to secure pairing, and only after that to Windows host H.264 streaming.
