# Remote Control handoff — v0.3

Use this file first (supersedes WORK_HANDOFF_v0.2.md; that remains for historical reference).

- **UI visual source of truth:** `design/LIQUID_FUSION_MASTER_REFERENCE.png` exactly; not merely a style inspiration.
- Windows desktop 3-zone dashboard and phone/tablet responsive layouts are implemented in the prototype and must remain visually faithful.
- Native Flutter source in `flutter/lib` has v0.2 **discovery only**; pairing is NOT wired in there.
- `tools/lan_probe` has independently runnable Node network and experimental pairing fixtures; no remote access capabilities.
- Run `node --test tools/lan_probe/*.test.mjs` for integration QA; 9 expected passes.
- Before shipping: migrate to audited DTLS / Noise, use Keystore/DPAPI, set authorization scopes, and test Windows/Android builds.
- Work preference: ChatGPT + Work; avoid Codex. GitHub Private code, Drive large assets; project separate from NetKit.
