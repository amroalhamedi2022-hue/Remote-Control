# UI prototype QA and next checkpoints

## Passed (HTML proof only)

- 1440x1000 desktop: three-zone navigation/content/session composition, 4 sample cards and session control rail.
- 1060x780 tablet: compact sidebar and responsive two-column devices.
- 390x844 Android-shaped viewport: Devices tab separated from Control tab; nav fixed at bottom; no horizontal overflow.
- Demo device selection changes selected card and session title.
- Dark/light toggle and navigation between Settings and Devices work.
- 0 JavaScript page errors during sampled headless checks.
- No actual network traffic is initiated by the UI code. The UI contains no fetch/WebSocket/RTC connect code.

## Not yet verified

- Flutter compilation and real device rendering.
- Pixel fidelity of Flutter versus `design/LIQUID_FUSION_MASTER_REFERENCE.png`.
- Dark/light visual QA beyond the HTML smoke test.
- Text scaling, touch target accessibility, i18n, animation performance, GPU render budget.
- Real mDNS/manual IP discovery, secure pairing, transport, video or input on any device.

## Next exact steps, in order

1. Generate Flutter Android+Windows scaffolds, copy Flutter UI source, `flutter pub get`, `flutter analyze`; fix any static/build errors.
2. Capture Flutter screenshots at target resolutions; compare with approved source; refine 3-zone layout, translucency, shapes and visual densities.
3. Add UI tests: selected device, navigation, theme, remote controls disabled/demo and no fake online state.
4. Define Rust-native interface `discover / pair / connect / requestConsent / stream / input / clipboard / files / stop`; no native engine yet.
5. Proof of LAN pairing without cloud on two real devices before streaming.
6. Benchmark Windows -> Android H.264 capture/stream/decode and set measured performance goals.

## Repo recommendation

Create a NEW separate private repository named `remote-control-local`. Do not mix with personal-download-manager or NetKit. Put `design/` and `docs/` alongside `flutter/` and future `core-rust/`, `platform-android/`, `platform-windows/`. Do not commit anything resembling actual private keys, personal access tokens, local auth codes or private device dumps.


## v0.2 additions, 2026-10-18

- Created `flutter/lib/network/lan_discovery.dart` to discover peers with UDP and probe their presence with TCP. Dart compilation **not yet verified**.
- Node fixture (`tools/lan_probe`) verifies protocol behavior with real loopback sockets; see the test output.
- Next gates: Flutter SDK analyzer/build, actual Android↔Windows LAN discovery, private firewall profile, secure pairing protocol review, and only then view/control.
