# Baseline verification — 2026-10-23

- Source input: `Remote_Control_Work_Transfer_Kit_v0.8.zip`, 67 entries including `START_HERE_WORK.md`; project tree nested under `Remote_Control_Liquid_Fusion_v0.8/`.
- GitHub upload state at audit time: repository **not confirmed to exist or be available**; no CI run proof.
- Test command (run from source tree root):

  ```bash
  node --test tools/lan_probe/*.test.mjs tools/stream_lab/*.test.mjs tools/video_lab/*.test.mjs
  ```

- Environment: Node v22.16.0, Linux runner, FFmpeg present.
- Test result: **31 passed / 0 failed / 0 skipped**, exit status 0, around 5.57 seconds.
- Original unmodified reference SHA-256: `5e0770c3c716ae7489a09c1942080d9c1f06c984d72d7eeffd9211c91fa6ca7c`
- Real Flutter analyzer, APK and Windows builds: **not executed in this audit**, no artifact.
- Real MSI/Pad 5 test: **not performed**.

Reference: see original `qa/NODE_TESTS_v0.8.tap` for historical suite log. This admin audit reproduced the suite independently; the test output may be provided separately in handoff package.
