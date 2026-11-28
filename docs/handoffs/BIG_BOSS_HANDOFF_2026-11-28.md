# Remote Control — Big Boss handoff

Snapshot 2026-11-28. Documentation only; README/open PR metadata reviewed, not full code audit or fresh CI/device certification.

## Product and constraints
Independent LAN remote controller. Android phone/tablet first, Windows later. Locked Liquid Fusion reference. Attended pairing and consent, never bypass OS capture/input restrictions.

## Observed development checkpoint
PR #2 6099c207508784fc4ff6545ceebc281b87422330 Android A01/A02; PR #1 9282a6aab107f3d194739a81250b43e8ff9ad3ee build gate. Main v0.8 is historical.

## Authoritative plans and evidence
README.md; design/LIQUID_FUSION_MASTER_REFERENCE.png; docs/HOST_DISCOVERY_v0.8.md; PR #2 and #1.

## Execution sequence and acceptance
1. Verify Android APK build and LAN pairing on phone/tablet, session authentication, expiring permissions, disconnect. 2. Attended MediaProjection capture and decode, quality/latency; explicit user-enabled input where supported, clear stop control, no unattended access. 3. File transfer reliability and 2-device tests; then Windows host/view/control. 4. Polish original liquid design, signed releases only after device QA.

## Build and test
Node22+ FFmpeg lab: node --test tools/lan_probe/*.test.mjs tools/stream_lab/*.test.mjs tools/video_lab/*.test.mjs ; Windows test-pattern lab scripts/start_windows_h264_lab.ps1; use current Android/Flutter CI branch for APK. No public port exposure.

## Resume procedure
Read AGENTS.md if present, original plans, current default branch, open PR heads/base/ancestry, exact SHA Actions and artifacts; compare against this snapshot. Choose newest compatible cumulative implementation, never overwrite newer changes. Record completed / remaining / blocked with exact commit and test evidence. Work in substantial nonduplicate batches; build at meaningful milestones, not each change. Before publishing, check package/version/signing continuity, licenses, offline/privacy policy and real-device acceptance where applicable. Do not infer completion from PR title or CI alone.

## Private handoff boundary
Owner-only material (keys, passwords, private data, ROMs, personal documents, original restricted assets) stays outside GitHub in access-restricted owner storage. Consult the private Big Boss Drive register. No secret values or private links are included here. If missing, record blocker; do not generate replacement keys for installed apps.

## Cross-project law
A lot of work to reach our goal as perfect as possible and as masterpiece as possible at best time. Master functionality in a masterpiece app. Evidence over claims; optimize time/cost; no duplicated work.
