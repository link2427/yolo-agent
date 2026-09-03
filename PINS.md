# Version pins & integrity

Everything is pinned; builds fail on hash mismatch.

## Agents & toolchain

| Tool | Version | Source | Integrity |
|------|---------|--------|-----------|
| opencode | 1.18.27 | `github.com/anomalyco/opencode` release tarball | sha256 TOFU¹ `4af5494f…bd702` |
| goose | 1.48.0 | `github.com/aaif-goose/goose` release tarball | sha256 TOFU¹ `3c38c790…98152` |
| pi | 0.84.4 | `github.com/earendil-works/pi` release tarball | sha256 **vs official release SHA256SUMS** `c2f3c3e6…23972` |
| prime-agent | 0.9.1 | `github.com/PrimeIntellect-ai/prime-agent` release tarball `prime-agent-0.9.1.tgz` | sha256 **vs official release SHA256SUMS** `573bce0c…835ba`; kernel runtime verified at build |
| DeepSeek Harness (`dsh`) | 0.1.1-rc.2 | npm `@deepseek-ai/dsh` | exact top-level version plus complete transitive integrity lock in `docker/install/deepseek-harness/pnpm-lock.yaml`; pnpm 11.7.0; CLI/config boot verified at build; wrapper passes upstream's required `node --expose-internals` workaround for the rc.2 HMR loader bug; upstream marks this a developer preview |
| OpenHands | 1.16.0 | pip `openhands` (uv-managed Python 3.12 venv) | exact version pin; runs `openhands web` (browser UI, no Docker socket); uv 0.12.9 (sha256 `ec7a99cd…a1460`) |
| code-server | 4.135.0 | `github.com/coder/code-server` standalone release tarball | sha256 TOFU¹ `300ef4e3…bc7d1` |
| ttyd | 1.7.7 | `github.com/tsl0922/ttyd` release binary `ttyd.x86_64` | sha256 **vs official release SHA256SUMS** (verified at build) |
| VS Code extension pack | 15 extensions | Open VSX, installed at build time | versions recorded in `/opt/yolo/EXTENSIONS-MANIFEST.txt` in the image (audit before shipping) |
| aider-chat | 0.86.2 | PyPI (isolated venv) | pinned exact version over TLS |
| node | 22 (bookworm-slim) | Docker Hub `node:22-bookworm-slim` | Linux/amd64 manifest pinned: `sha256:4d676821…0c96` |
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
`docker/install/install-skills.sh` (skills).
