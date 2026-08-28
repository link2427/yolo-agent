# 09 — Version pins & integrity

Everything is pinned; builds fail on hash mismatch.

## Agents & tooling

| Tool | Version | Source | Integrity |
|------|---------|--------|-----------|
| opencode | 1.18.13 | `github.com/anomalyco/opencode` release tarball | sha256 TOFU¹ `8d500b20fed2d26e537e221895b1a575476571b4f0089bb29fb13eeb8eb9e937` |
| goose | 1.45.0 | `github.com/aaif-goose/goose` release tarball | sha256 TOFU¹ `e0db638ac437ca0a60b0c1622f45322608d228d1a285214c3bf48fd9763346a5` |
| pi | 0.83.0 | `github.com/earendil-works/pi` release tarball | sha256 **vs official release SHA256SUMS** `b0625eb623197b0afe20c870d21ef2f34481f1504e5777df3f698a66c7636f5f` |
| prime-agent | 0.7.1 | `github.com/PrimeIntellect-ai/prime-agent` release tarball | sha256 **vs official release SHA256SUMS** `d68612c83239caafab72cc76c55ac572bfd07a059ea8fbd2a3ddbe1f2b55dcdb` |
| aider-chat | 0.86.2 | PyPI (isolated venv `/opt/aider-venv`) | pinned exact version over TLS |
| code-server | 4.117.0 | `github.com/coder/code-server` release tarball (standalone) | sha256 TOFU¹ `5616650cc65a82046eb7ab24b794da6632a3292d07df06908800d75544962391` |
| ttyd | 1.7.7 | `github.com/tsl0922/ttyd` release binary `ttyd.x86_64` | sha256 **vs official release SHA256SUMS** |
| node / npm | 22 | Docker Hub `node:22-bookworm-slim` | image tag pinned |
| python / git / build-essential / … | Debian bookworm (12) | apt | distro-managed |

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

Full commit SHAs and tarball sha256 values are in `scripts/install-skills.sh`
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

## Verifying the artifact

```bash
sha256sum -c SHA256SUMS          # in the exported bundle
# expected for v5.0:
# 3ad5d7f8bce19c983244ea8adbdfb7d76baa4bb2a24bf35a5f807f81d56e8d99  yolo-dev_5.0.docker.tar
```
