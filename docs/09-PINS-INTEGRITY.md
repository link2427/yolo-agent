# 09 — Version pins & integrity

Everything is pinned; builds fail on hash mismatch.

## Agents & tooling

| Tool | Version | Source | Integrity |
|------|---------|--------|-----------|
| opencode | 1.18.27 | `github.com/anomalyco/opencode` release tarball | sha256 TOFU¹ `4af5494f9433f59db8c1e344198f0ee72a50c06ec009fb4a8aeab4c2d4abd702` |
| goose | 1.48.0 | `github.com/aaif-goose/goose` release tarball | sha256 TOFU¹ `3c38c790723fde4532357f35346b7190bd70d198e6be559f9ffeac4cf7c98152` |
| pi | 0.84.4 | `github.com/earendil-works/pi` release tarball | sha256 **vs official release SHA256SUMS** `c2f3c3e6a1850bd87654cc3ca8811013272397c3d042a4e2a64c43ee1b423972` |
| prime-agent | 0.9.1 | `github.com/PrimeIntellect-ai/prime-agent` release tarball | sha256 **vs official release SHA256SUMS** `573bce0cd004fc62052e9a924089941b7f39266ab71e66a94c85a1f9d35835ba` |
| aider-chat | 0.86.2 | PyPI (isolated venv `/opt/aider-venv`) | pinned exact version over TLS |
| OpenHands | 1.16.0 | pip `openhands` (uv-managed Python 3.12 venv) | exact version pin; runs `openhands web` (browser UI, no Docker socket); uv 0.12.9 |
| code-server | 4.135.0 | `github.com/coder/code-server` release tarball (standalone) | sha256 TOFU¹ `300ef4e37e469e6368a4673c6a623e1c9ba8a34f42b394fb49c431a8900bc7d1` |
| ttyd | 1.7.7 | `github.com/tsl0922/ttyd` release binary `ttyd.x86_64` | sha256 **vs official release SHA256SUMS** |
| node / npm | 22 | Docker Hub `node:22-bookworm-slim` | Linux/amd64 manifest pinned: `sha256:4d676821dff059fd00d277ee4261ef34ea712317fed0737c03941481b5760c96` |
| python | 3.11 (system) + 3.12 (OpenHands venv, uv-managed) | apt + python-build-standalone via uv | distro-managed + uv-managed |
| git / build-essential / … | Debian bookworm (12) | apt | distro-managed |

## Skills library (10 repos, 924 deduped skills, ~147 MB)

All tarballs are `https://codeload.github.com/<owner>/<repo>/tar.gz/<commit>`
(TOFU¹ of the exact commit's tarball). Licenses: MIT unless noted.

| Repo | Commit (abbrev) | License | Skills |
|------|-----------------|---------|--------|
| mattpocock/skills | `2ab9580` | MIT | 41 |
| obra/superpowers | `44c9b2d` | MIT | 14 |
| anthropics/skills | `b29e7cf` | Apache-2.0² | 14 |
| wshobson/agents | `c4b82b0` | MIT | 180 |
| microsoft/azure-skills | `ff47e4e` | MIT | 37 |
| supabase/agent-skills | `1207767` | MIT | 2 |
| prisma/skills | `808913c` | MIT | 9 |
| OthmanAdi/planning-with-files | `ad1b692` | MIT | 7 |
| affaan-m/ECC | `2665d48` | MIT | 284 |
| alirezarezvani/claude-skills | `aa8d778` | MIT | 418 |

Full commit SHAs and tarball sha256 values are in `docker/install/install-skills.sh`
and the repo `PINS.md`.

¹ **TOFU (trust on first use):** artifacts without an official checksum are
pinned from the first verified download so the shipped image is byte-stable
and tamper-evident against that snapshot.

² Anthropic's repo has no root LICENSE; its README states the non-doc skills
are Apache-2.0. The `docx/pdf/pptx/xlsx` skills are "source-available, not
open source" and are **pruned** at install, never redistributed.

## VS Code extensions (15)

Installed at build time from Open VSX; installed versions are recorded in
`/opt/yolo/EXTENSIONS-MANIFEST.txt` inside the image — audit that file before
shipping if you need to certify exact extension versions.

## Verifying historical artifacts

```bash
sha256sum -c history/v5.0/bundle-metadata/SHA256SUMS
sha256sum -c history/v6.0/bundle-metadata/SHA256SUMS
```

The large archives are not committed, so these commands are meaningful only
when run beside a recovered archive with the matching original filename.
