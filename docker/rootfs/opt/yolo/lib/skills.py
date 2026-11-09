"""yolo skills — one skill library for every agent, nothing loaded by default.

  yolo skills                       list (★ = enabled for you)
  yolo skills search <text>
  yolo skills show <name>
  yolo skills enable <name|pack:NAME>... [--project]
  yolo skills disable <name|pack:NAME>...
  yolo skills packs
  yolo skills apply                 relink (runs on every container start)

Library, later sources win on a name clash:
  /opt/yolo/skills/library          baked into the image
  ~/.yolo/skills-repo               Gitea repo yolo/skills (YOLO_SKILLS_REPO)
  ~/.yolo/fleet/skills              the fleet repo's skills/ folder

Enabled for you = YOLO_DEFAULT_SKILLS + fleet skills.txt + fleet
people/<person>.skills.txt + your own enables − your own disables.

Only enabled skills are linked into the folders agents read
(~/.claude/skills, ~/.agents/skills, ~/.qwen/skills, ~/.pi/agent/skills,
~/.config/opencode/skills), so an agent only ever sees those. `--project`
copies the skill into the repo instead (.agents/skills and .claude/skills), so
it is committed and shared with everyone who works on that repo.
"""

from __future__ import annotations

import json
import os
import shutil
import sys
from pathlib import Path

HOME = Path(os.environ.get("HOME") or "/home/agent")
Y = HOME / ".yolo"
STATE = Y / "skills"
ENABLED_DIR = STATE / "enabled"
USER_FILE = STATE / "user.json"
SOURCES = [Path("/opt/yolo/skills/library"), Y / "skills-repo", Y / "skills-repo/skills", Y / "fleet/skills"]
PACKS_FILES = [Path("/opt/yolo/skills/packs.json"), Y / "skills-repo/packs.json", Y / "fleet/packs.json"]
AGENT_DIRS = [HOME / ".claude/skills", HOME / ".agents/skills", HOME / ".qwen/skills",
              HOME / ".pi/agent/skills", HOME / ".config/opencode/skills"]


def library() -> dict[str, Path]:
    found: dict[str, Path] = {}
    for src in SOURCES:
        if not src.is_dir():
            continue
        for d in sorted(src.iterdir()):
            if d.is_dir() and (d / "SKILL.md").is_file():
                found[d.name] = d
    return found


def describe(path: Path) -> str:
    """The description from SKILL.md front matter, including YAML block scalars
    (description: > / |- followed by indented lines)."""
    try:
        lines = (path / "SKILL.md").read_text(errors="replace").splitlines()[:40]
    except OSError:
        return ""
    for i, line in enumerate(lines):
        if not line.startswith("description:"):
            continue
        val = line.split(":", 1)[1].strip()
        if val in (">", "|", ">-", "|-", ">+", "|+"):
            body = []
            for nxt in lines[i + 1:]:
                if nxt and not nxt[0].isspace():
                    break
                body.append(nxt.strip())
            val = " ".join(x for x in body if x)
        return val.strip().strip('"').strip("'")
    return ""


def packs() -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for f in PACKS_FILES:
        try:
            out.update({k: list(v) for k, v in json.loads(f.read_text()).items()})
        except (OSError, ValueError):
            pass
    return out


def read_list(path: Path) -> list[str]:
    try:
        return [w for line in path.read_text().splitlines()
                for w in line.split("#", 1)[0].split() if w]
    except OSError:
        return []


def user() -> dict:
    try:
        data = json.loads(USER_FILE.read_text())
        return {"enabled": list(data.get("enabled", [])), "disabled": list(data.get("disabled", []))}
    except (OSError, ValueError):
        return {"enabled": [], "disabled": []}


def save_user(u: dict) -> None:
    STATE.mkdir(parents=True, exist_ok=True)
    USER_FILE.write_text(json.dumps(u, indent=2) + "\n")


def expand(names: list[str]) -> list[str]:
    pk = packs()
    out: list[str] = []
    for n in names:
        items = pk.get(n[5:], []) if n.startswith("pack:") else [n]
        for i in items:
            if i not in out:
                out.append(i)
    return out


def effective() -> list[str]:
    person = os.environ.get("YOLO_PERSON", "")
    wanted = (os.environ.get("YOLO_DEFAULT_SKILLS", "").split()
              + read_list(Y / "fleet/skills.txt")
              + (read_list(Y / f"fleet/people/{person}.skills.txt") if person else []))
    u = user()
    wanted = expand(wanted + u["enabled"])
    off = set(expand(u["disabled"]))
    lib = library()
    return [n for n in wanted if n not in off and n in lib]


def _ours(link: Path) -> bool:
    try:
        target = os.readlink(link)
    except OSError:
        return False
    return target.startswith(str(ENABLED_DIR)) or any(target.startswith(str(s)) for s in SOURCES)


def apply(quiet: bool = False) -> list[str]:
    lib = library()
    names = effective()
    ENABLED_DIR.mkdir(parents=True, exist_ok=True)
    for entry in ENABLED_DIR.iterdir():
        if entry.is_symlink() and entry.name not in names:
            entry.unlink()
    for n in names:
        link = ENABLED_DIR / n
        if link.is_symlink() and os.readlink(link) == str(lib[n]):
            continue
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(lib[n])
    for d in AGENT_DIRS:
        d.parent.mkdir(parents=True, exist_ok=True)
        if d.is_symlink():
            if os.readlink(d) != str(ENABLED_DIR):
                d.unlink()
                d.symlink_to(ENABLED_DIR)
        elif d.is_dir():
            # The person keeps their own skills here: link ours in beside them.
            for entry in d.iterdir():
                if entry.is_symlink() and _ours(entry) and entry.name not in names:
                    entry.unlink()
            for n in names:
                if not (d / n).exists():
                    (d / n).symlink_to(ENABLED_DIR / n)
        else:
            d.symlink_to(ENABLED_DIR)
    (STATE / "enabled.json").write_text(json.dumps(names) + "\n")
    if not quiet:
        print("enabled: " + (", ".join(names) if names else "none"))
    return names


def cmd_list(filter_text: str = "") -> None:
    lib, on = library(), set(effective())
    rows = []
    for name, path in sorted(lib.items()):
        desc = describe(path)
        if filter_text and filter_text.lower() not in (name + " " + desc).lower():
            continue
        src = "image" if str(path).startswith("/opt") else ("fleet" if "fleet" in str(path) else "gitea")
        rows.append((("★" if name in on else " "), name, src, desc))
    if not rows:
        print("no skills match" if filter_text else "the library is empty")
        return
    w = max(len(r[1]) for r in rows)
    for star, name, src, desc in rows:
        print(f"{star} {name:<{w}}  {src:<5}  {desc[:100]}")
    print(f"\n★ = enabled for you ({len(on)}). yolo skills enable <name> | yolo skills packs")


def cmd_project(names: list[str]) -> int:
    lib = library()
    root = Path.cwd()
    for n in expand(names):
        if n not in lib:
            print(f"unknown skill: {n}", file=sys.stderr)
            return 1
        dest = root / ".agents/skills" / n
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(lib[n], dest, symlinks=True)
        claude = root / ".claude/skills" / n
        claude.parent.mkdir(parents=True, exist_ok=True)
        if claude.is_symlink() or claude.exists():
            if claude.is_dir() and not claude.is_symlink():
                shutil.rmtree(claude)
            else:
                claude.unlink()
        claude.symlink_to(Path("../../.agents/skills") / n)
        print(f"added {n} to {root}/.agents/skills (commit it to share with the repo)")
    return 0


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("list", "ls"):
        cmd_list()
        return 0
    cmd, rest = argv[0], argv[1:]
    quiet = "--quiet" in rest
    rest = [a for a in rest if a != "--quiet"]
    if cmd == "apply":
        apply(quiet)
    elif cmd == "search":
        cmd_list(" ".join(rest))
    elif cmd == "show":
        lib = library()
        if not rest or rest[0] not in lib:
            print("usage: yolo skills show <name>", file=sys.stderr)
            return 1
        print((lib[rest[0]] / "SKILL.md").read_text())
    elif cmd == "packs":
        for name, items in sorted(packs().items()):
            print(f"pack:{name:<10} {' '.join(items)}")
    elif cmd in ("enable", "disable"):
        if not rest:
            print(f"usage: yolo skills {cmd} <name|pack:NAME>...", file=sys.stderr)
            return 1
        if cmd == "enable" and "--project" in rest:
            return cmd_project([a for a in rest if a != "--project"])
        lib, u = library(), user()
        for n in rest:
            if not n.startswith("pack:") and n not in lib:
                print(f"unknown skill: {n} (yolo skills search ...)", file=sys.stderr)
                return 1
            add, remove = ("enabled", "disabled") if cmd == "enable" else ("disabled", "enabled")
            if n in u[remove]:
                u[remove].remove(n)
            if n not in u[add]:
                u[add].append(n)
        save_user(u)
        apply()
    else:
        print(__doc__.split("\n\n")[1])
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
