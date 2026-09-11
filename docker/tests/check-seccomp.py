#!/usr/bin/env python3
"""Assert the image's seccomp profile permits the toolchain syscalls.

yolo-agent-cpp and yolo-agent-reverse-engineering ship seccomp-toolchain.json,
which is config/seccomp-base.json minus ptrace, process_vm_readv and
process_vm_writev. Those three must be ABSENT from the deny list, or gdb cannot
attach and gcc's LTO breaks. Their presence means the wrong profile was baked
into the image, so this is a build-gate check rather than a warning.
"""

import json
import sys

PROFILE = sys.argv[1] if len(sys.argv) > 1 else "/opt/yolo/seccomp.json"
REQUIRED_ALLOWED = ("ptrace", "process_vm_readv", "process_vm_writev")

try:
    with open(PROFILE, encoding="utf-8") as fh:
        profile = json.load(fh)
except OSError as exc:
    print(f"ERROR: cannot read seccomp profile {PROFILE}: {exc}", file=sys.stderr)
    sys.exit(1)

denied = {
    name
    for block in profile.get("syscalls", [])
    for name in (block.get("names") or [])
}
wrongly_denied = sorted(set(REQUIRED_ALLOWED) & denied)

if wrongly_denied:
    print(
        "ERROR: the toolchain seccomp profile still denies "
        + ", ".join(wrongly_denied)
        + f" ({PROFILE})",
        file=sys.stderr,
    )
    sys.exit(1)

print(">> seccomp allows ptrace, so gdb can attach")
