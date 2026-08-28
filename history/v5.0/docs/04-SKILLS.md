# 04 — Skills library

**924 skills** preloaded, all from real, well-loved open-source collections
(no hand-rolled skills). Read-only at `/opt/skills`; exposed to agents as
symlinks in `~/.agents/skills/`.

## What's installed

| Repo | License | Unique skills |
|------|---------|---------------|
| mattpocock/skills | MIT | 41 |
| obra/superpowers | MIT | 14 |
| anthropics/skills | Apache-2.0¹ | 14 |
| wshobson/agents | MIT | 180 |
| microsoft/azure-skills | MIT | 37 |
| supabase/agent-skills | MIT | 2 |
| prisma/skills | MIT | 9 |
| OthmanAdi/planning-with-files | MIT | 7 |
| affaan-m/ECC | MIT | 284 |
| alirezarezvani/claude-skills | MIT | 418 |

¹ Anthropic's `docx/pdf/pptx/xlsx` skills are "source-available, not open
source" and were pruned — not redistributed. Also excluded for licensing:
`hesreallyhim/awesome-claude-code` (CC BY-NC-ND) and `vercel-labs/agent-skills`
(no license). Every repo is pinned to an exact commit and hash-verified at
build (see 09).

## How discovery works

- All skill-capable agents (opencode, pi, goose, prime-agent) auto-discover
  `~/.agents/skills/<name>/SKILL.md` — the agentskills.io standard.
- The farm is a set of symlinks into the read-only `/opt/skills` tree, deduped
  by frontmatter `name:` (most-loved repo wins on collision).
- Skills load **on demand**: full SKILL.md is read only when the agent decides
  a task matches; goose additionally injects names+descriptions at session
  start.

## Managing skills

```bash
ls ~/.agents/skills | wc -l            # 924
ls ~/.agents/skills | head             # browse
rm ~/.agents/skills/<name>             # remove one (just a symlink)
/opt/yolo/make-skill-farm.sh           # rebuild the farm (idempotent)
```

To add your own skill: create `~/.agents/skills/<name>/SKILL.md` with
`name:` + `description:` frontmatter (or drop a SKILL.md dir in a project's
`.agents/skills/`).

## Caution

Skills are third-party instructions that the agent executes with full
workspace access. Even loved repos can contain subtly wrong or unsafe
guidance — vet a skill before relying on it.
