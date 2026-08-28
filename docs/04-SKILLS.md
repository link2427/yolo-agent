# 04 — Skills: 30 curated defaults + a 920-skill library

**v6 change:** the container now loads only **30 curated coding skills** by
default — the ~120k tokens of skill descriptions that goose injected at
session start in v5 are gone. The full **library (920 skills)** stays in the
image at `/opt/skills` (read-only, unloaded) and is also shipped as a separate
zip export.

## The 30 defaults (coding-focused)

| Group | Skills |
|-------|--------|
| Engineering workflow (superpowers) | test-driven-development, systematic-debugging, brainstorming, writing-plans, executing-plans, requesting-code-review, verification-before-completion, resolving-merge-conflicts, using-git-worktrees, subagent-driven-development |
| Engineering practices (mattpocock) | code-review, design-an-interface, request-refactor-plan |
| Frontend / web | frontend-design, webapp-testing, react-modernization, typescript-advanced-types, tailwind-design-system, javascript-testing-patterns, e2e-testing-patterns |
| Backend / languages (wshobson) | nodejs-backend-patterns, python-project-structure, async-python-patterns, api-design-principles |
| Databases (official) | supabase, supabase-postgres-best-practices |
| Agent / API infra | mcp-builder, skill-creator |
| Docs & styling | doc-coauthoring, theme-factory |

Source: `/opt/yolo/CURATED-SKILLS.txt` in the image (edit + rerun the farm
builder to change the defaults).

## The library (920 skills)

10 loved repos (MIT/Apache-2.0), pinned commits, hash-verified, deduped by
frontmatter name. Everything is always present at `/opt/skills`:

| Repo | License | Skills |
|------|---------|--------|
| alirezarezvani/claude-skills | MIT | ~415 |
| affaan-m/ECC | MIT | ~280 |
| wshobson/agents | MIT | 180 |
| mattpocock/skills | MIT | 41 |
| microsoft/azure-skills | MIT | 37 |
| obra/superpowers | MIT | 14 |
| anthropics/skills | Apache-2.0¹ | 14 |
| prisma/skills | MIT | 9 |
| OthmanAdi/planning-with-files | MIT | 7 |
| supabase/agent-skills | MIT | 2 |

¹ Anthropic's `docx/pdf/pptx/xlsx` skills are source-available and are
**not** included (pruned for licensing) — so there are no PowerPoint/Excel
skills in the library; the closest are `theme-factory` / `canvas-design`
(styling slides/docs/HTML).

## How discovery works

- Agents (opencode, pi, goose, prime-agent) auto-discover
  `~/.agents/skills/<name>/SKILL.md` — only the 30 symlinks are present by
  default, so session-start context is tiny.
- Skills load on demand; goose additionally injects names+descriptions at
  session start (30 → negligible).

## Managing skills

```bash
cat ~/.agents/SKILLS-LIBRARY.txt          # browse all 920 (name <TAB> repo)
/opt/yolo/skill-use.sh <name>             # activate one from the library
rm ~/.agents/skills/<name>                # remove one (just a symlink)
SKILL_FARM=all /opt/yolo/make-skill-farm.sh   # activate ALL 920
SKILL_FARM_FILE=/path/to/list /opt/yolo/make-skill-farm.sh  # custom set
```

The separate **`yolo-agent-6.0-skill-library.zip`** export contains the full
library (skills/ + `SKILLS-LIBRARY.txt` + README) for use on machines without
the image, or to keep the library off the image if you ever want a leaner
build.

## Caution

Skills are third-party instructions executed with full workspace access —
even loved repos can contain subtly wrong guidance. Vet before relying.
