# 06 — Reverse engineering

`yolo-agent-reverse-engineering` is the base image plus a decompilation and
binary-analysis toolchain. It exists because these tools parse **hostile input**
by design, and that deserves its own container rather than sharing one with your
normal development work.

## What is installed

| Tool | Entry point | Purpose |
|---|---|---|
| `pyinstxtractor-ng` | `pyinstxtractor-ng <exe>` | Unpack a PyInstaller `.exe` **without executing it** |
| `pycdc` | `pycdc <file.pyc>` | Decompiler for Python bytecode, built from source (C++) |
| `pycdas` | `pycdas <file.pyc>` | Disassembler matching `pycdc`, works on any bytecode version |
| `uncompyle6` | `uncompyle6 <file.pyc>` | Python decompiler (3.7–3.8 bytecode) |
| `pydumpck` | `pydumpck <file>` | All-in-one orchestrator: dispatches by input type |
| `xdis` | Python module | Bytecode disassembly library, version-aware |
| `jadx` | `jadx <file.apk|.dex>` | DEX/APK to Java source (CLI only, no GUI) |
| `Ghidra` | `ghidra-headless <project> <name>` | NSA's decompiler for native binaries |
| `radare2` | `r2 <file>` | Native binary analysis and disassembly |
| `gdb`, `binutils-multiarch`, `elfutils` | — | Native debugging and object inspection |
| `binwalk`, `foremost`, `yara` | — | Carving, embedded-file extraction, signature scanning |
| Python bindings | `import capstone, unicorn, lief, pefile, elftools, xdis` | Disassembly, emulation, format parsing |

Java: **Temurin JDK 21** at `/opt/java`, with `JAVA_HOME` already set. Ghidra 12
requires Java 21, and Debian 12 ships only OpenJDK 17 — which is why the JDK is
a pinned tarball rather than an apt package.

All of this shares the **single** Python 3.11 environment at `/opt/pyenv`. The
reverse packages are layered onto the same venv the base image uses; there is no
second environment. See [04-PYTHON.md](04-PYTHON.md).

## Workflow: a PyInstaller `.exe`

This is the most common case — a Python program frozen into a Windows
executable.

```bash
cd /workspace
ls suspicious.exe

# 1. Confirm what it is. A PyInstaller binary contains the marker "MEI" and a
#    recognizable overlay; the bootloader section also gives a hint.
file suspicious.exe
grep -abo 'MEI' suspicious.exe | head -3
strings -n 8 suspicious.exe | grep -i -m5 pyinstaller

# 2. Unpack. This does NOT run the program -- it reads and extracts.
pyinstxtractor-ng suspicious.exe
# -> creates suspicious.exe_extracted/
```

The extraction directory contains the Python modules the program bundled, plus
`PYZ-00.pyz_extracted/` with the archive's contents. Entry points are usually
`<script>.pyc` at the top level.

```bash
cd suspicious.exe_extracted
ls

# 3. Disassemble. The extracted .pyc files have had their header (the magic
#    number and timestamp) stripped by PyInstaller, which is why naive
#    decompilers fail on them. pycdas reads the raw payload regardless.
pycdas main.pyc > main.dis
less main.dis

# 4. Decompile, if the bytecode version is within reach.
pycdc main.pyc > main.py 2> main.err
head -50 main.py
cat main.err      # pycdc reports what it could not handle
```

`pydumpck` automates steps 2–4 and picks a decompiler based on the detected
bytecode version:

```bash
pydumpck suspicious.exe
```

### Which decompiler handles which bytecode version

| Python version | `uncompyle6` | `pycdc` | `pycdas` |
|---|---|---|---|
| 2.x | no | partial | yes |
| 3.6 | no | yes | yes |
| 3.7 – 3.8 | **yes** | yes | yes |
| 3.9 – 3.10 | no | partial | yes |
| 3.11 – 3.13 | **no** | partial (runs, incomplete output) | yes |

Read that table as: **disassembly always works, decompilation often does not.**
For modern bytecode, plan on reading `pycdas` output rather than expecting clean
Python source. Constant folding, control-flow structuring, and match statements
all degrade badly above 3.8, and no free tool does 3.11+ well.

### angr is not installed

angr would give you symbolic execution, but it cannot be installed here: its
dependency closure needs `mulpyplexer` (no wheel, and no release compatible
with Python 3.11 at all) and an sdist-only `arpy`. Rather than build source
packages into an air-gapped image, it was dropped. `capstone` and `unicorn`
still cover disassembly and emulation, and nothing else depends on angr.

### The honest gaps

**`decompyle3` is not installed, and cannot be.** It declares `xdis<6.3`,
while `pyinstxtractor-ng` requires `xdis==6.3.0` exactly. pip treats transitive
constraints as hard, so it refuses the install rather than downgrading silently.

**`uncompyle6` hits the same ceiling** (it declares `xdis<6.3,>=6.1.0`), and it
arrives through `pydumpck`. Since neither can be resolved normally, `pydumpck`
and `uncompyle6` are installed with `--no-deps` from
`docker/requirements-reverse-nodeps.txt`, and their dependencies are pinned
explicitly in `requirements-reverse.txt` instead. Nothing is unpinned; only the
resolution edge is skipped. `uncompyle6` running against `xdis 6.3.0` is
guarded by the smoke suite, which runs its CLI at build time — metadata alone
would not tell you whether it works.

`pycdc`/`pycdas` remain the version-agnostic fallback for bytecode the
Python-side decompilers cannot read.

**`pycdc` cannot fully decompile Python 3.11+ bytecode.** It runs and emits
partial output rather than crashing, and `pycdas` gives you complete
disassembly. Use them together.

**No Wine.** You cannot run a Windows `.exe` in this container, only analyse it
statically. Dynamic analysis needs the Windows host.

## Workflow: a native `.exe` or ELF

```bash
cd /workspace

# 1. Identify the format.
file target.exe
readelf -h target.elf        # ELF only
python3 -c "
import pefile
pe = pefile.PE('target.exe')
print(pe.FILE_HEADER.Machine, [e.dll for e in getattr(pe,'DIRECTORY_ENTRY_IMPORT',[])][:10])
"

# 2. Quick look with radare2.
r2 -q -c 'ij' target.exe          # JSON header: arch, bits, endianness
r2 -q -c 'aaa; afl' target.exe    # analyse, then list functions
r2 -q -c 'aaa; s main; pdf' target.exe

# 3. Strings and embedded content.
strings -n 6 target.exe | less
binwalk target.exe
foremost -i target.exe -o /workspace/carved
```

### Ghidra headless

Ghidra produces by far the best native decompilation. It runs without a GUI:

```bash
mkdir -p /workspace/ghidra-proj

ghidra-headless /workspace/ghidra-proj MyProject \
  -import /workspace/target.exe \
  -postScript DecompileFunction.java 2>/dev/null || true

# The simplest useful invocation: import and run the auto-analyzer, then export
# the decompiled C for every function to a directory.
ghidra-headless /workspace/ghidra-proj MyProject \
  -import /workspace/target.exe \
  -scriptPath /opt/ghidra/Ghidra/Features/Decompiler/ghidra_scripts \
  -postScript DecompileHeadless.java /workspace/decompiled
```

Notes that save time:

- A full analysis of a large binary takes minutes and a lot of RAM. The compose
  file defaults to 12 GB; raise `JAVA_OPTS=-Xmx8g` in `config/reverse.env` if
  Ghidra runs out of heap.
- Ghidra's project state defaults to `$HOME/.ghidra`, inside the persistent home
  volume. Set `GHIDRA_USER_DIR=/workspace/.ghidra` to keep it with your project
  instead — useful when the binaries are large.
- Ghidra refuses to write into a non-writable directory. `/workspace` and the
  home volume are the writable paths.
- `ghidra-headless` is a symlink to `/opt/ghidra/support/analyzeHeadless`.

### Java / Android

```bash
jadx -d /workspace/out app.apk          # DEX -> Java source
jadx --deobf -d /workspace/out app.apk  # with deobfuscation
jadx -d /workspace/out classes.dex      # a bare DEX file
```

`jadx-gui` needs a display and is not exposed; this is the CLI only.

## Workflow: scripted analysis in Python

When you want to automate rather than poke at one file, the bindings are all in
the one environment:

```python
# Disassemble a code region with capstone.
import capstone
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
for insn in md.disasm(b"\x55\x48\x89\xe5\xc3", 0x1000):
    print(f"{insn.address:#x}: {insn.mnemonic} {insn.op_str}")

# Parse an executable format with LIEF.
import lief
binary = lief.parse("/workspace/target.elf")
print(binary.header.machine_type, len(binary.sections))

# Emulate a function with unicorn.
import unicorn
uc = unicorn.Uc(unicorn.UC_ARCH_X86, unicorn.UC_MODE_64)

```

the last release with a CPython 3.11 wheel. See
[11-PINS-INTEGRITY.md](11-PINS-INTEGRITY.md).

## The seccomp difference

This image uses `config/seccomp-toolchain.json`, which — unlike the base
profile — allows `ptrace`, `process_vm_readv`, and `process_vm_writev`. That is
required for `gdb` to attach and for debugger-driven unpacking of binaries that
refuse to run otherwise. All privileged syscalls remain denied. See
[10-SECURITY.md](10-SECURITY.md).

## Security warning

Everything in this image is designed to parse input an attacker controlled.
`pycdc`, `jadx`, `Ghidra`, and `radare2` have all had memory-safety bugs, and a
crafted file can exploit one. That is not a hypothetical: it is the normal risk
of the discipline.

What contains it here: the tools run as uid 10001, with no Linux capabilities,
no internet route, and only `/workspace` and the home volume writable. A
successful exploit gets your workspace and session state, not your Windows host.
Treat files you did not create as untrusted, and prefer this image over the base
image for anything you did not write yourself.

## Verifying the toolchain yourself

The image smoke suite (`docker/tests/smoke-reverse.sh`, run by
`docker buildx bake reverse-test`) builds a **real** PyInstaller onefile archive
inside the image, extracts it with `pyinstxtractor-ng`, disassembles the
extracted bytecode with `pycdas`, round-trips a compiled `.pyc`, parses an ELF
with LIEF, and starts Ghidra's launcher to confirm it resolves Java 21.

A quick manual check:

```bash
printf 'def f(n):\n    return n * 2\n' > /tmp/s.py
python3 -m py_compile /tmp/s.py
pycdas /tmp/__pycache__/s.cpython-311.pyc | head -20
```
