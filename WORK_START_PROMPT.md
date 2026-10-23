# Work task — GitHub setup ONLY (one-time handoff)

I authorize you to create **one new private GitHub repository** under my connected account `amroalhamedi2022-hue` named `remote-control-liquid-fusion`, and import the attached `Remote_Control_GitHub_Only_Setup_Seed_v0.8.zip` as its initial source.

## Your assignment is strictly infrastructure setup, NOT software development

1. Read `docs/OPERATING_MODEL.md` and `docs/GITHUB_SETUP.md` before taking action. Verify the owner/login. Create `amroalhamedi2022-hue/remote-control-liquid-fusion` with visibility **Private**. If already created by an authorized party, verify ownership, visibility, and existing contents first; do not delete or overwrite unrelated history.
2. Import the **contents** of the ZIP at the repository root, not in an extra nested directory. Include dotfiles and `.github/workflows/ci.yml`, all source files, tests, administrative docs, design reference, and assets. Do not exclude/alter any project files other than excluding any discovered secrets or build caches, which you must report rather than push.
3. Make one import commit on `main` (or the new repository's default branch), with an honest descriptive message `chore: import Remote Control Liquid Fusion v0.8 baseline and admin docs`. Verify that the source tree contains `flutter/`, `tools/`, `scripts/`, `.github/`, `docs/`, `design/`, and `README.md`. Confirm the reference image's checksum against the uploaded archive.
4. Check GitHub settings: visibility **Private**; GitHub Actions enabled/visible for the repository, where allowed. Do not launch a workflow manually, troubleshoot build failures, write code, modify CI, open implementation PRs or change the scope. The initial push might automatically trigger an existing Actions workflow: record its URL only and leave any failures to the main Chat conversation.
5. Ensure the connected ChatGPT GitHub plugin has access to this private repository. If that requires my action, tell me to go to GitHub connection settings → Configure → Repository access → select `remote-control-liquid-fusion` → Save; do not guess that access is already granted.
6. Report exactly: repository URL, owner, confirmed visibility, default branch, initial commit SHA, presence of `.github/workflows/ci.yml`, whether my ChatGPT GitHub connection can read it, any Actions run URL (if automatically triggered), and blockers.
7. **STOP** after reporting. Do not begin M0/M1/M2–M8 development; do not implement code, build APK/Windows, diagnose Flutter, make code changes, run extra labs, or work on any other repositories. All technical implementation, builds, bug fixes, acceptance and ongoing management occur in the existing NORMAL ChatGPT conversation via GitHub.

The canonical Liquid Fusion design (`design/LIQUID_FUSION_MASTER_REFERENCE.png`) must be left unchanged. The repo must never be made public as a workaround. Never expose or upload keys, credentials or sensitive user-machine data. Do not use Codex.
