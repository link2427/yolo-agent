# Changelog

## 1.1.0 - 2026-08-30

- Added the official DeepSeek Harness (`dsh`) developer preview, pinned through
  a committed pnpm lockfile and verified during the image build.
- Added persistent headless and browser workflows; Harness state lives in the
  existing agent-home volume and `DEEPSEEK_API_KEY` stays runtime-only.
- Added an opt-in Compose browser service on host-loopback port 3080 without
  patching DeepSeek Harness's upstream loopback-only safety policy.
- Added image smoke tests for the Harness CLI and runtime environment.
- Compressed offline bundles and added automatic multipart fallback for
  GitHub's 2 GiB release-asset limit.

## 1.0.0 - 2026-08-28

- Renamed the project from `yolo-dev` to `yolo-agent`.
- Split the image into independently cached toolchain, skills, and web-IDE stages.
- Added `headless` and `full` runtime profiles plus matching smoke-test stages.
- Added Docker Bake, Compose, and GitHub Actions build/release workflows.
- Added downloadable full and headless offline ZIP bundles for disc transfer.
- Pinned the Linux/amd64 Node base image by digest.
- Separated host launchers, runtime rootfs, security policy, and image installers.
- Preserved the exact recovered 6.0 source as `archive-yolo-dev-6.0-recovered`.
- Preserved the surviving 5.0 documents and build metadata as a partial snapshot.

## Imported yolo-dev 6.0 source - 2026-08-18

Exact source tree recovered from the `lavender-lark-43` Longhorn backup.
This is the first complete source state available in Git history.

## Imported yolo-dev 5.0 evidence

Only exported documentation, a build log, manifest, and archive checksum
survived. See `history/v5.0/README.md`; no complete source tree is claimed.
