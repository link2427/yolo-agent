---
name: yolo-reverse
description: Analyse and decompile binaries in the yolo full container (PyInstaller executables, .pyc, APK/DEX, native ELF/PE) with pyinstxtractor-ng, pycdc, jadx, Ghidra headless and radare2. Use for reverse-engineering and malware-triage style work.
---

# Reverse engineering here (full tier)

Never execute the sample. Every tool below reads files; none needs to run them.

| Input | Start with |
| --- | --- |
| PyInstaller `.exe` | `pyinstxtractor-ng file.exe`, then `pycdc` on the `.pyc` files |
| `.pyc` | `pycdc file.pyc` (decompile), `pycdas file.pyc` (disassemble); `uncompyle6` for 3.7–3.8 |
| APK / DEX | `jadx -d out/ app.apk` |
| native ELF / PE | `r2 -A file` or `ghidra-headless` (below) |
| anything | `pydumpck file` dispatches by type; `file`, `strings -n 8`, `binwalk -e` |

## Ghidra headless

```bash
mkdir -p /tmp/gh
ghidra-headless /tmp/gh proj -import sample.bin -postScript DecompileAll.java out/ -deleteProject
# or analyse only:
ghidra-headless /tmp/gh proj -import sample.bin -overwrite
```

## Python bindings

`import capstone, unicorn, lief, pefile, elftools, xdis` — one environment,
`/opt/pyenv`.

## Rules

- Work on copies inside `/workspace/<case>/`; keep the original untouched and
  record its `sha256sum`.
- Write findings to `/workspace/<case>/NOTES.md` as you go.
- `pip install` is impossible here (air gap). Use what is installed.
