# Remote Control — canonical operating model (user-confirmed, 2026-10-23)

## This document OVERRIDES earlier Work-executor instructions

The user explicitly restricted **ChatGPT Work to a ONE-TIME GitHub setup/import task**. All software engineering, test review, architecture choices, QA, milestones, CI investigation, GitHub commits/PRs, build fixes and ongoing project administration will occur in the user's **current normal ChatGPT conversation**. Work is NOT the implementation agent.

### Role split

| Responsibility | Owner |
| --- | --- |
| Create the new, private GitHub repo; import baseline; verify plugin permission and repo settings | ChatGPT Work, ONE TIME ONLY |
| Examine and change Flutter/Android/Windows source and network stack | Main ChatGPT conversation |
| Research open source prior to implementing, review code/licenses/security | Main ChatGPT conversation |
| Create branches, commits, PRs, review Actions, remediate build failures | Main ChatGPT conversation using available GitHub tools |
| Obtain/build Android APK and Windows bundle via Actions, validate hashes/logs | Main ChatGPT conversation (GitHub Actions runner does compiling) |
| Scope, acceptance, audit, status board and decisions | Main ChatGPT conversation |
| Actual Xiaomi Pad 5/MSI Sword 15 hardware test | User-assisted only when necessary |

The private repository is the durable source of truth once initial import finishes. GitHub Actions runs can happen automatically on push; Work must not dispatch or fix them. The existing hourly scheduled GitHub watcher monitors meaningful events but does NOT cause Work to run and does not do software implementation.

### Project non-negotiables

- Independent from NetKit, IDM, AquaWord and every other repository.
- Approved visual target: `design/LIQUID_FUSION_MASTER_REFERENCE.png`; pixel/layout fidelity as close as feasible, responsive adaptations only.
- Before coding, inspect well-maintained existing solutions and technical/licensing/security/maintenance implications; prefer verified reuse over rewriting from scratch.
- Keep every user-requested requirement traced in `docs/FEATURE_MATRIX.md`; don't silently drop features.
- No claims of success without verifiable code/CI/build/device evidence. Distinguish CODED, TESTED, BUILT, VERIFIED_ON_DEVICE; `31/31` Node tests do NOT prove Flutter build or actual Android streaming.
- RustDesk/scrcpy/Sunshine+Moonlight/KDE Connect/droidVNC-NG/other sources are references to investigate legally; no assumption of license compatibility.
- No Root or daily ADB; honor Android MediaProjection, Accessibility, foreground service, unattended access and lock screen restrictions.
- LAN-only device sessions, no mandatory external service; least privilege, secure pairing, encryption, revocation and explicit consent for privileged capabilities. **The existing Node pairing lab is NOT production-grade security**.
- Ship no fabricated APK/EXE. Windows output needs full app bundle; device tests separately documented.
- Favor substantive tested implementation batches; brief reports with commits, changed files, CI runs, artifacts, blockers and next action.

### Starting technical reality (not progress fabricated by setup)

Baseline: v0.8 experimental source with 31 Node tests reported passed in its own prior environment. Flutter SDK compilation **not yet verified**; no proven real APK/Windows runner; physical device streaming/control **not verified**. Work's import must not mark M1–M8 complete.

### Required one-time Work report

`Repo URL | Owner | Private? | Default branch | Initial commit SHA | .github/workflows/ci.yml present? | ChatGPT connector can access? | Automatically triggered Actions URLs (if any) | Blockers`.

After that Work stops. Main ChatGPT continues from the imported commit.
