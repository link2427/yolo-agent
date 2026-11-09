---
name: yolo-airgap
description: Rules for working inside the air-gapped yolo-agent lab container. Use before installing packages, downloading anything, or when a command fails with a network error.
---

# Working in the air-gapped lab

This container has **no internet access**. Only the lab network is reachable:

| Service | Address |
| --- | --- |
| Model server (vLLM, SEC09) | `http://192.168.1.101:8000/v1` |
| Gitea (git, issues, pull requests) | `http://192.168.1.27:3000` |

## Rules

1. Never try to download from the internet: `pip install`, `npm install`,
   `apt-get`, `curl https://...`, `go get`, `cargo add` and similar will fail or
   hang. Do not retry them.
2. Use what is already installed. Check first:
   - Python packages: `pip list` (one environment at `/opt/pyenv`)
   - Node: `node --version`, global tools: `ls /opt/agents/npm/lib/node_modules`
   - Compilers and tools: `yolo tools`
3. If a task truly needs a package that is not installed, stop and tell the
   user the exact package name and version. Someone has to add it to the next
   image build.
4. Prefer the standard library and the tools that exist over adding
   dependencies.
5. Code, notes and results go in `/workspace`. That folder is the person's
   shared folder; everything else in the container is replaced on upgrade
   except the home directory.

## Getting work out

- Commit and push to Gitea (see the `yolo-gitea` skill).
- Or leave files in `/workspace`, which the person can download from the
  Files page or from VS Code.
