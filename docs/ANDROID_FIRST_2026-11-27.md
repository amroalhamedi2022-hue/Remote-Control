# Android-first delivery — A01/A02 diagnostic starting batch
Base: 9282a6aab107f3d194739a81250b43e8ff9ad3ee (PR #1). Preserve Windows and all prior source; no main merge.

- Fix stale file routing gate that rejected Android despite the existing attended SAF receiver. Android/Windows allowlist is not trust; existing signed intent, pairing and receiver consent remain unchanged.
- Add a non-exported native local screen-capture diagnostic, launched from Settings on Android. Explicit OS consent, foreground service, callback registered before display creation, stop notification, 20-second limit. Frames are acquired and immediately closed; no frame data saved or transmitted. No Accessibility permission or remote input.
- Both scaffold scripts register the components and permissions. Regression tests check routing and Linux scaffold contract.
- Status at commit: SOURCE IMPLEMENTED; CI, native compilation, device acceptance NOT VERIFIED. Diagnostic is not Android remote viewing; rotation/full-display mapping, encoder/decoder, authenticated media transport and control remain open.
- Next: compile and physically run the diagnostic, choose vetted authenticated session transport, implement attended hardware codec stream, receiver, then separate opt-in input controls. Never enable remote capture/input via the experimental pairing protocol without security acceptance. No new paid service or dependencies.

## A02 — AVC encoder batch and toolchain recovery
**Flag: Best Functionality in a Masterpiece App.**
Run 46063142935 failed because rolling Flutter stable changed from 3.47.8 (last verified run 40749663386) to 3.50.1, producing three fatal analyzer deprecation infos for material.dart. Node protocol and Windows lifecycle passed; Flutter tests and native packaging were not reached. Pin 3.47.8 for reproducibility without weakening analyzer gates; upgrade separately.
- Replace raw-frame diagnostic with a native surface-input H.264 encoder. Prefer hardware where Android reports it, negotiate supported aligned dimensions, bound output drain, report real codec/frame/keyframe/byte counters, dispose buffers immediately. No media transmission, saving, or input permission.
- Stop on orientation change, user stop, OS callback, failure or 20s timeout. No claim of seamless rotation yet.
- Pure sizing test covers phone/tablet aspect, alignment, no upscale and invalid input. CI triggers a single Android-only native compile on explicit [m34-platform-compile] push. Existing Windows build remains skipped.
- Source only until CI/native device evidence exists. Next critical path: authenticated LAN session, video transport/decoder and consent-gated input; no repeated diagnostic polishing unless it blocks this path.
