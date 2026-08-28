# Changelog

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
