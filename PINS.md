# Version pins & integrity (v2)

Everything is pinned; builds fail on hash mismatch.

## Agents & toolchain

| Tool | Version | Source | Integrity |
|------|---------|--------|-----------|
| opencode | 1.18.13 | `github.com/anomalyco/opencode` release tarball | sha256 TOFU¹ `8d500b20fed2d26e537e221895b1a575476571b4f0089bb29fb13eeb8eb9e937` |
| goose | 1.45.0 | `github.com/aaif-goose/goose` release tarball | sha256 TOFU¹ `e0db638ac437ca0a60b0c1622f45322608d228d1a285214c3bf48fd9763346a5` |
| pi | 0.83.0 | `github.com/earendil-works/pi` release tarball | sha256 **vs official release SHA256SUMS** `b0625eb623197b0afe20c870d21ef2f34481f1504e5777df3f698a66c7636f5f` |
| prime-agent | 0.7.2 | `github.com/PrimeIntellect-ai/prime-agent` release tarball `prime-agent-0.7.2.tgz` | sha256 **vs official release SHA256SUMS** `bc5471f2a626d727b88a45eb745fff93b10c554a3c4fc5912f25d8c64b987f5e`; install patched with npm overrides for the Aug-2026 AWS SDK registry breakage (`@aws-sdk/eventstream-handler-node`→3.972.9, `@aws-sdk/types`→3.974.2 — referenced patch versions 3.972.32/3.974.3 were never published); kernel runtime verified at build |
| code-server | 4.117.0 | npm `code-server@4.117.0` (global) | pinned exact version over TLS |
| ttyd | 1.7.7 | `github.com/tsl0922/ttyd` release binary `ttyd.x86_64` | sha256 **vs official release SHA256SUMS** (verified at build) |
| VS Code extension pack | 15 extensions | Open VSX, installed at build time | versions recorded in `/opt/yolo/EXTENSIONS-MANIFEST.txt` in the image (audit before shipping) |
| aider-chat | 0.86.2 | PyPI (isolated venv) | pinned exact version over TLS |
| node | 22 (bookworm-slim) | Docker Hub `node:22-bookworm-slim` | image tag pinned |
| python / git / build-essential / … | Debian bookworm (12) | apt | distro-managed |

## Skills library (10 repos, 920 deduped skills after v6 name normalization, ~147 MB on disk)

All tarballs are `https://codeload.github.com/<owner>/<repo>/tar.gz/<commit>`
(TOFU¹ hash of the exact commit's tarball, recorded 2026-08-04). Licenses:
MIT unless noted.

| Repo (dir name) | Commit | Tarball sha256 | License | Skills |
|-----------------|--------|----------------|---------|--------|
| mattpocock/skills (`mattpocock-skills`) | `2ab958093e83e0ec752e6c1c5932da465bf23e0c` | `80e06b58…8dd202` | MIT | 41 |
| obra/superpowers (`obra-superpowers`) | `44c9b2d6e889982ac18c27d05a19fefe335194e1` | `412d9888…ca0c14` | MIT | 14 |
| anthropics/skills (`anthropics-skills`) | `b29e7cf65e5cb78a5ac33d582270551bc74a14eb` | `c3832f49…74d474c` | Apache-2.0² | 14 (docx/pdf/pptx/xlsx pruned³) |
| wshobson/agents (`wshobson-agents`) | `c4b82b0ad771190355eb8e204b1329732a18449a` | `ada3f8e1…504a2bb3` | MIT | 180 |
| microsoft/azure-skills (`microsoft-azure-skills`) | `ff47e4e6caad94ac07b7778658bd3603ae376ffa` | `e1e03d6e…7dbdbf` | MIT | 37 unique |
| supabase/agent-skills (`supabase-agent-skills`) | `1207767388a0ffb55f21fb4e6988fee96942431d` | `0bc734b1…79e055a` | MIT | 2 |
| prisma/skills (`prisma-skills`) | `808913c1dac11dc425631c2454f7fcb2d5ade5ca` | `e47af844…61d721c` | MIT | 9 |
| OthmanAdi/planning-with-files (`planning-with-files`) | `ad1b6927e88359764a4f33720a46ae04e55ab120` | `32786564…f47b47` | MIT | 7 unique |
| affaan-m/ECC (`affaan-ECC`) | `2665d48ae604b585d0bafb69c3a8e8dca9a15be5` | `c7f4e414…9221124` | MIT | 284 unique |
| alirezarezvani/claude-skills (`alireza-claude-skills`) | `aa8d778811a557a2c28ccadda4cf3d0bd028a4cc` | `ac8bdd2d…dadab77` | MIT | 418 unique |

Selection rationale: star counts + real install counts from skills.sh
(Vercel Labs' registry). Excluded for licensing: `hesreallyhim/awesome-
claude-code` (CC BY-NC-ND), `vercel-labs/agent-skills` (no license).

¹ **TOFU (trust on first use):** for artifacts without an official checksum,
the hash was captured from the first verified download and is pinned so the
shipped image is byte-stable and tamper-evident against that snapshot.
² Anthropic's repo has no root LICENSE; its README states the non-doc skills
are Apache-2.0. ³ `skills/docx|pdf|pptx|xlsx` are "source-available, not open
source" — pruned at install, never redistributed.

To roll new versions/pins, override the build args (agents) or edit
`scripts/install-skills.sh` (skills).
