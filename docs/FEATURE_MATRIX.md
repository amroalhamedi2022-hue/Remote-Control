# Feature coverage — authoritative user requirements (NOT a completion checklist yet)

| ID | User requirement | Priority | Current evidence v0.8 / necessary test |
|---|---|---|---|
| R01 | Windows → Android remote screen | P0 | Synthetic H.264/JPEG Node labs only; real physical capture+APK TBD |
| R02 | Windows → Android remote mouse/keyboard | P0 | Not implemented |
| R03 | Android → Windows remote screen/control | P1 | Android host not implemented; MediaProjection/Accessibility constraints |
| R04 | Phone ↔ Tablet bidirectional control | P1 | Not implemented; require each direction on real devices |
| R05 | Controller and Host roles on each device | P1 | Architecturally planned only |
| R06 | Same Wi-Fi / LAN entirely offline | P0 | UDP/TCP local Node protocol tested, devices pending |
| R07 | Hotspot connectivity without internet | P0 | Real hotspot/client isolation tests pending |
| R08 | Wi-Fi Direct if viable | P2 | Feasibility investigation, not promise |
| R09 | Automatic discovery & manual IP | P0 | Code/lab tests present, Flutter device test pending |
| R10 | Secure one-time pairing and revoke | P0 | Lab protocol only; must replace for privileged production use |
| R11 | High quality direct screen / rotations/fullscreen | P0 | Lab code only; device UI/codec tests pending |
| R12 | Multi-touch / gestures where permitted | P1 | Not implemented; Android API and Accessibility limitations |
| R13 | Audio if permitted | P2 | Not implemented; playback capture permissions vary |
| R14 | Shared Clipboard respecting Android privacy | P1 | UI mock only, no live sync |
| R15 | File/folder transfer and drag/drop where feasible | P1 | UI mock only; add integrity, progress, cancellation, permission flows |
| R16 | Keyboard shortcuts, volume/media | P1 | Not implemented; OS permission limitations |
| R17 | Multiple simultaneous devices/sessions | P2 | UI prototype only |
| R18 | Automatic reconnect to paired devices | P1 | Not verified; respect user consent / new MediaProjection grant |
| R19 | Unattended access only within OS policies | P2 | No Android silent capture/lock bypass; Windows opt-in controlled scenario only |
| R20 | Hardware H.264/H.265, adaptive bitrate/FPS/resolution | P1 | Lab FFmpeg H.264 synthetic transport only; no production native codec |
| R21 | Low-latency mode and weak-network adaptation | P1 | No physical timing measurements |
| R22 | Liquid Fusion visual reference across all screens | P0 | Reference locked; prototype coded but Flutter never compiled/real-screenshot compared |
| R23 | Dark/Light, customizable theme, performance-safe effects | P1 | Prototype state; Android/Windows verification pending |
| R24 | Root-free/ADB-free daily operation | P0 | Mandatory constraint; no bypass of security policy |
| R25 | Personal offline privacy/permission separation | P0 | Must implement verified encrypted authenticated production transport |
| R26 | GitHub private, Work execution, admin review here | P0 | Work to create repo; this document governs |

None of the above requirements may be silently removed. Distinguish lab/test evidence vs product readiness. Update evidence links by issue and commit for each acceptance.
