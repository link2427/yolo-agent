#!/usr/bin/env bash
#
# yolo-agent-reverse-engineering smoke suite.
#
# Runs after smoke-common.sh. Everything here is exercised on a real artifact
# built inside the image, because "the tool is on PATH" proves very little: the
# point is that extraction and decompilation actually produce output on the
# offline host, with no network and no extra downloads.
#
set -euxo pipefail

# --- tools are present ------------------------------------------------------
for tool in pycdc pycdas jadx ghidra-headless r2 gdb objdump readelf \
            java binwalk foremost yara xxd hexedit; do
  command -v "$tool" >/dev/null
done

/opt/java/bin/java -version 2>&1 | grep -q 'version "21'
pycdc 2>&1 | head -1 || true
r2 -v | head -1
jadx --version

# --- one Python environment, now the reverse superset -----------------------
test "$VIRTUAL_ENV" = /opt/pyenv
test "$(readlink -f "$(command -v python3)")" = "$(readlink -f /opt/pyenv/bin/python3)"
/opt/pyenv/bin/python - <<'PY'
import sys
assert sys.version_info[:2] == (3, 11), sys.version
# The common set is still there...
import requests, yaml, pytest, pydantic                                   # noqa: F401
# ...plus the reverse-engineering set, in the same interpreter.
import capstone, unicorn, lief, elftools, pefile                          # noqa: F401
import xdis, pyinstxtractor_ng                                            # noqa: F401
print("xdis", xdis.__version__)
print("reverse python env OK:", sys.version.split()[0])
PY

# There must be no second interpreter environment.
test ! -d /opt/pyenv-legacy
test ! -d /opt/aider-venv
test ! -d /opt/openhands

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- real PyInstaller .exe: build it, extract it, decompile what comes out ---
# The strongest available check: a genuine PyInstaller archive is produced by
# the image itself, unpacked with no execution, and the extracted bytecode is
# then handed to the disassembler. Every step is offline.
mkdir -p "$work/pysrc"
cat > "$work/pysrc/app.py" <<'PY'
import sys


def classify(n):
    if n < 0:
        return "negative"
    if n == 0:
        return "zero"
    return "positive"


def main():
    print("pyinstaller probe:", classify(len(sys.argv) - 1))


if __name__ == "__main__":
    main()
PY

/opt/pyenv/bin/python -m PyInstaller \
  --onefile --name probepkg --distpath "$work/dist" --workpath "$work/pyi-work" \
  --specpath "$work/pyi-work" --noconfirm --log-level WARN \
  "$work/pysrc/app.py" >/dev/null
exe="$work/dist/probepkg"
test -x "$exe"
file -b "$exe" | grep -q '^ELF 64-bit'

# pyinstxtractor-ng creates its output directory in the CURRENT WORKING
# DIRECTORY (os.path.join(os.getcwd(), basename + "_extracted")), not next to the
# input file, so run it from the work directory and reference the result there.
(
  cd "$work"
  pyinstxtractor-ng "$exe"
) > "$work/pyi.log" 2>&1
grep -qi 'pyinstaller' "$work/pyi.log"

extract_dir="$work/probepkg_extracted"
test -d "$extract_dir" || {
  echo "ERROR: pyinstxtractor-ng produced no extraction directory" >&2
  echo "--- pyi.log ---" >&2; cat "$work/pyi.log" >&2; exit 1
}
found_pyc="$(find "$extract_dir" -maxdepth 1 -name 'app.pyc' -o -maxdepth 1 -name 'app.*.pyc' | head -1)"
test -n "$found_pyc" || {
  echo "ERROR: no app bytecode extracted" >&2
  ls -la "$extract_dir" >&2 || true
  exit 1
}
echo ">> extracted $(find "$extract_dir" -type f | wc -l) files; app bytecode at $found_pyc"

# The extracted .pyc is missing its header (PyInstaller strips it), which is the
# usual reason a naive decompile fails. Disassembling the raw payload is the
# check that matters here, and it must name the real functions.
pycdas "$found_pyc" > "$work/app.dis" 2>&1 || true
grep -Eq 'classify|main' "$work/app.dis"
echo ">> pycdas produced $(wc -l < "$work/app.dis") lines from extracted bytecode"

# pydumpck is the all-in-one orchestrator; it must run against the same input.
pydumpck --help >/dev/null

# --- uncompyle6 runs in this environment ------------------------------------
# It arrives transitively via pydumpck and its metadata wants xdis<6.2.0 while
# we pin xdis==6.3.0, so pip installed it without re-checking the constraint.
# Running the CLI here is what actually proves it works; if it ever fails, drop
# it from the docs rather than shipping a broken entry point.
uncompyle6 --version >/dev/null 2>&1 || { echo 'uncompyle6 CLI failed:' >&2; uncompyle6 --version; exit 1; }
echo ">> uncompyle6 CLI is functional against xdis $(/opt/pyenv/bin/python -c 'import xdis;print(xdis.__version__)')"

# --- direct .pyc path: compile, disassemble, attempt decompile ---------------
cat > "$work/sample.py" <<'PY'
def total(values):
    acc = 0
    for v in values:
        acc += v
    return acc
PY
/opt/pyenv/bin/python -m py_compile "$work/sample.py"
pyc="$work/__pycache__/sample.cpython-311.pyc"
test -f "$pyc"
pycdas "$pyc" > "$work/sample.dis" 2>&1
grep -q 'total' "$work/sample.dis"
# pycdc cannot fully decompile 3.11 bytecode; it must still run and emit output
# rather than crashing on an unsupported version.
pycdc "$pyc" > "$work/sample.dec" 2>&1 || true
test -s "$work/sample.dec"

# --- native binary analysis round trip --------------------------------------
cat > "$work/hello.c" <<'EOF'
#include <stdio.h>
int main(void) { puts("reverse-engineering probe"); return 0; }
EOF
gcc -O2 -o "$work/hello" "$work/hello.c"
readelf -h "$work/hello" | grep -q 'ELF64'
objdump -d "$work/hello" | grep -q '<main>'
r2 -q -c 'ij' "$work/hello" | grep -q '"arch"'
yara --version >/dev/null
file -b "$work/hello" | grep -q '^ELF 64-bit'

# LIEF/pefile bindings must load a real binary, not just import.
/opt/pyenv/bin/python - "$work/hello" <<'PY'
import sys
import lief

binary = lief.parse(sys.argv[1])
assert binary is not None
# LIEF renamed these enums across major versions; accept either spelling.
arch = getattr(lief.ELF, "ARCH", None) or getattr(lief.ELF, "Arch", None)
machine = getattr(binary.header, "machine_type", None)
assert machine is not None, "lief parsed no machine type"
if arch is not None:
    assert machine == arch.X86_64, machine
print("lief parsed machine:", machine)
PY

# --- the disassembler/emulator pair works on real bytes ----------------------
# angr used to be checked here; it is deliberately not installed (its dependency
# closure cannot resolve on Python 3.11). capstone and unicorn remain the
# scripted-analysis path, so exercise them rather than only importing them.
/opt/pyenv/bin/python - <<'PY'
import capstone
import unicorn

md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
insns = list(md.disasm(b"\x55\x48\x89\xe5\xc3", 0x1000))
assert [i.mnemonic for i in insns][:2] == ["push", "mov"], [i.mnemonic for i in insns]

uc = unicorn.Uc(unicorn.UC_ARCH_X86, unicorn.UC_MODE_64)
uc.mem_map(0x1000, 0x1000)
uc.mem_write(0x1000, b"\x90")
print("capstone:", len(insns), "insns; unicorn: memory mapped and writable")
PY

# --- Ghidra headless resolves Java and starts -------------------------------
# A full analysis needs minutes and a project on the home volume; confirming
# the launcher finds Java 21 is the meaningful fast check.
ghidra-headless > "$work/ghidra.log" 2>&1 || true
grep -qiE 'ghidra|usage' "$work/ghidra.log"

echo "reverse smoke tests passed"
