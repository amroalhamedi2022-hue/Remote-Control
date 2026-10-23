# Remote Control — Liquid Fusion / Design Lock v1.0

Status: APPROVED BY USER — 2026-10-18.

## The non-negotiable visual reference

`LIQUID_FUSION_MASTER_REFERENCE.png` is the PRIMARY and AUTHORITATIVE visual reference for the app. The actual product should look as close as practically possible to this generated visual, **not merely be loosely inspired by it**. No redesign, minimalist substitution, alternative iconography/layout, or broad changes to theme without explicit approval.

Reference art: 1536 x 1024 composite concept board. It includes the main desktop dashboard (top center), Android phone device dashboard (top right), connected-device and QR pairing surfaces, remote session viewer, file transfer, shared clipboard, alternate desktop light mode, tablet landscape controller, Android phone session controller, theme customization. Reference art contains illustrative device previews and fake performance figures; these must be replaced by real data in the actual app.

## Signature visual identity

- Name: Remote Control. Visual direction: **Liquid Fusion** — dark Liquid Aurora foundation + Aqua Glass readability/translucent cards + occasional Nebula Flow pink/coral highlight.
- Deep midnight navy background with violet/blue liquid ambient gradient, cyan and magenta glowing edges, glass cards, round corners, sparse translucent bubble accents.
- Dark mode as screenshot primary. Carefully designed light Aqua Glass variant. Maintain color semantics and hierarchy across both.
- Preserve **same visual layout and relative visual density** as screenshot while scaling responsively. In particular, no plain white Flutter Material default scaffold.
- Liquid fluid gradient effects remain behind controls; do not overlay distracting moving effects on the transmitted screen.
- Accent palette (starting approximations to match reference, to refine against image): #0B1127 / #121B3E background, #256BFA electric blue, #29D8E8 aqua, #8A62F7 violet, #ED57AD pink, #FF819E coral. Actual screenshot colors take priority over these suggested tokens.
- Smooth animations for selected tab transitions, connection states, small bubble movement; performance-aware motion reduction. Provide reduce-motion and battery-saving options.
- App logo: use the overlapping blue/cyan/violet connected-screen mark appearing in the master reference, recreated as editable vector art (not a crop of the screenshot).

## Desktop Windows layout (top center of reference)

- 3-zone composition: slim left navigation; wide content area for devices and live remote-screen preview; narrow right-side contextual remote-control actions, all inside dark rounded glass window.
- Sidebar order/icons: Devices; Remote Control; File Transfer; Shared Clipboard; Multi-Device; Settings. Persistent bottom connection/device status element.
- Top bar: small app logo/name, device search, LAN/offline status, theme/settings/window controls.
- Device row: 3 cards for Xiaomi Pad 5, Android Phone, MSI Sword 15 plus Add Device/manual IP entry, with small visual thumbnail and Online status.
- Live remote screen viewport must dominate the visual center; the preview in the screenshot is Windows wallpaper and taskbar — replace with LIVE video when connected.
- Session panel: device name, Connected indicator, useful metrics, screen-related tools on left of viewport and large Disconnect/Touch/Mouse/Keyboard controls to right. Quality, Resolution, FPS controls in contextual panel.
- Visual screen/frame remains sharp; no blur shader over actual video frames.

## Android phone layout (top right and lower phone reference)

- Devices home screen: compact title/header, segmented Devices/Favorites, glass device cards, bottom navigation (Devices, Control, Files, Clipboard, Settings).
- Remote session screen: full-screen native video with compact top connection strip; translucent bottom remote-control toolbar including Touch, Mouse, Keyboard, Files/More. Auto-hide toolbar in immersive mode, reveal on gesture/tap.
- Phones are vertically oriented by default; preserve readability and tappable targets. Rotation support for remote session.

## Tablet Xiaomi Pad 5 layout (bottom center reference)

- Landscape split screen with left compact navigation/device panel, large stream viewport, top toolbar, floating/pinned bottom control dock. Prioritize remote screen area over decorative space.
- Portrait fallback should be adaptive rather than stretching desktop mockup.

## Supporting screens (mid and bottom regions)

- Connection screen: list of discoverable local devices, IP addresses where appropriate, pairing QR, explicit connection/permission state.
- File Transfer: Send/Receive tab, dropzone, real transfer progress (color follows theme), cancel/pause where supported; files and drag/drop should not depend on the screenshot's decorative mock data.
- Shared Clipboard: per-device tiles, copy action, consent/privacy indicator. Respect Android clipboard restrictions.
- Themes panel: Dark / Light / Auto, palette thumbnails, Glassmorphism, Fluid Animations, Colorful Accents, Reduce Motion toggles.

## Fidelity rules and technical realities

- The attached concept illustration is **not** executable code; match its actual visual style in Flutter UI and vector/shader assets, without using the screenshot as one giant app background.
- Actual device icons, status, pairing codes, remote-screen imagery, FPS, resolution, latencies, throughput and progress must be live or honestly marked as demo data in early prototypes.
- Bubble and liquid animations in navigation and chrome must not hamper hardware video decoding, network transport, CPU/GPU throughput, battery or touch latency. When remote control is active, pause background animation where needed.
- Every actionable control must be wired to the real app state by release; never ship fake controls.
- Platform behavior must respect Android MediaProjection consent and Accessibility permissions, Windows desktop/UAC boundaries, and LAN permission prompts.
- Offline local only as the default operation. Device discovery, pairing and sessions must never require third-party servers. Fail clearly when hotspot client isolation prevents peer-to-peer communication.
- Accessibility, touch injection and pairing must be conspicuous and user-controlled; do not silently bypass system security.

## Visual acceptance checks before feature completion

1. Side-by-side compare at 1920×1080 Windows, tablet landscape and phone portrait against their corresponding image regions.
2. Check layout: sidebar, device cards, thumbnail size, live video frame proportion, right session controls, bottom dock, QR and file transfer layouts.
3. Check aesthetic: glass card transparency, border glows, color gradients, bubble density, icon weight, fonts and spacing.
4. Check genuine responsiveness in narrow windows, phone landscape, Android display size/font scaling, light/dark themes.
5. Check fidelity and responsiveness on modest devices with gradients and animated bubbles enabled/disabled, with video in progress.
6. Any deviation from reference (except accessibility, usability, performance, genuine device data, necessary responsive adaptations) requires user review.

## Technical architecture decisions (provisional, not yet all validated)

- UI: Flutter desktop + Android with platform textures/native rendering for video as needed.
- Core: Rust modular local transport/security/discovery and session logic; Android Kotlin MediaProjection/Accessibility/MediaCodec; Windows native capture and hardware encoding.
- Start the system implementation with secure paired LAN discovery + Windows host to Android client. Test whether WebRTC/libdatachannel or another LAN-native transport is better in real use before freezing codec/network decisions.
- License review needed for all reused code. RustDesk AGPL-3.0 / Sunshine GPL dependencies are research reference unless compliance implications deliberately accepted. Prefer suitably licensed, well-supported components; no copying designs/assets from other applications.
- Keep code private on a new GitHub repository, separate from NetKit and other projects. Do not publish secret pairing keys or user device identifiers. Google Drive for large non-source assets as needed.

## Next milestones

1. Architecture decision record, licensing ledger, security threat model, scope of prototype.
2. Flutter desktop/Android layout proof of concept with screenshot side-by-side QA; NO remote streaming implied at this stage.
3. Device discovery and trusted pairing over offline LAN.
4. Windows capture / hardware encode -> Android native decode and remote input proof.
5. Android host with explicit user consent and Accessibility UI, then bidirectional tablet/phone use.
6. Clipboard, transfer, audio, multi-device features and hardware/performance refinements.
