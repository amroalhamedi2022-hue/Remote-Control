# Android-first delivery — A01/A02 diagnostic starting batch
Base: 9282a6aab107f3d194739a81250b43e8ff9ad3ee (PR #1). Preserve Windows and all prior source; no main merge.

- Fix stale file routing gate that rejected Android despite the existing attended SAF receiver. Android/Windows allowlist is not trust; existing signed intent, pairing and receiver consent remain unchanged.
- Add a non-exported native local screen-capture diagnostic, launched from Settings on Android. Explicit OS consent, foreground service, callback registered before display creation, stop notification, 20-second limit. Frames are acquired and immediately closed; no frame data saved or transmitted. No Accessibility permission or remote input.
- Both scaffold scripts register the components and permissions. Regression tests check routing and Linux scaffold contract.
- Status at commit: SOURCE IMPLEMENTED; CI, native compilation, device acceptance NOT VERIFIED. Diagnostic is not Android remote viewing; rotation/full-display mapping, encoder/decoder, authenticated media transport and control remain open.
- Next: compile and physically run the diagnostic, choose vetted authenticated session transport, implement attended hardware codec stream, receiver, then separate opt-in input controls. Never enable remote capture/input via the experimental pairing protocol without security acceptance. No new paid service or dependencies.
