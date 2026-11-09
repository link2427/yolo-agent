"""Point the Kilo Code chat panel in VS Code at the lab model.

Kilo Code 7 runs a bundled `kilo` CLI (an opencode fork) and reads the same
config format as opencode from ~/.config/kilo/kilo.json. configure writes
opencode's config first, so Kilo gets a copy of it, plus the VS Code settings
that pick the model in the panel (merged into code-server's user settings
through ~/.yolo/vscode-extra.json by configure_code_server).
"""

from __future__ import annotations

import json
import os
from pathlib import Path


def seed(home: Path, default: dict, base: str, key: str) -> None:
    oc = home / ".config/opencode/opencode.json"
    cfg = json.loads(oc.read_text()) if oc.is_file() else {}
    cfg.pop("$schema", None)
    kdir = home / ".config/kilo"
    kdir.mkdir(parents=True, exist_ok=True)
    tmp = kdir / ".kilo.json.tmp"
    tmp.write_text(json.dumps(cfg, indent=2) + "\n")
    os.chmod(tmp, 0o600)
    tmp.replace(kdir / "kilo.json")
    extra = {
        "kilo-code.new.model.providerID": "vllm",
        "kilo-code.new.model.modelID": default["id"],
        "kilo-code.new.autoApprove.enabled": True,
        "kilo-code.new.experimental.browserAutomation": False,
        "kilo-code.new.browserAutomation.enabled": False,
    }
    y = home / ".yolo"
    y.mkdir(parents=True, exist_ok=True)
    (y / "vscode-extra.json").write_text(json.dumps(extra, indent=2) + "\n")
