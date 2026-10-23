> Historical onboarding notes. Superseded: repository is now PUBLIC at https://github.com/amroalhamedi2022-hue/Remote-Control, managed from this chat. Do not create a second repository.

# GitHub creation/import guide — Work setup ONLY

**Target**: account `amroalhamedi2022-hue`, name `remote-control-liquid-fusion`, PRIVATE, default branch `main` where possible. Must not modify any other repositories. No public fallback.

1. In Work's Cloud Browser, authenticate to the intended GitHub account and create a private repository (unless an empty correctly-owned target already exists). If manual user interaction is needed, request only that step. Never handle credentials in a chat response or file.
2. Unpack the provided ZIP and import its **contents directly at repo root**: `.github/`, `.gitignore`, `README.md`, `flutter/`, `tools/`, `scripts/`, `docs/`, `design/`, `preview/`, `qa/`, and root Work setup prompt. Do not add an extra containing folder. Do not invent `.git` commit history that is not present.
3. Import unmodified code and design. Commit with an honest initial-import message. Record commit SHA. No development, lint fixes, scaffold updates, dependency upgrades or workflow edits: those belong to the main ChatGPT conversation.
4. Confirm owner, PRIVATE visibility, main/default branch, file paths, and `.github/workflows/ci.yml`; verify design image SHA-256 against the uploaded archive. Actions may start automatically when pushed; record URL if present but do NOT dispatch/retry/fix workflows.
5. Confirm the ChatGPT GitHub connector can read this private repo. If it cannot, ask the user to enable it under GitHub connection settings → Configure → Repository access → `remote-control-liquid-fusion` → Save. A private repo being accessible in the browser does not automatically imply it is visible through the ChatGPT connector.
6. Report all evidence and STOP. Do not implement M0–M8, create feature branches, code, open PRs, run builds, or work in other project repositories.

This setup-only rule **supersedes older docs referencing Work as an executor**. See `docs/OPERATING_MODEL.md`.
