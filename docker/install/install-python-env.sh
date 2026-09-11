#!/usr/bin/env bash
#
# Build the single Python 3.11 environment that every yolo-agent image ships.
#
#   /opt/pyenv        the venv (bin/python, bin/pip, and the console scripts)
#
# The system interpreter is Debian bookworm's python3 = 3.11, so there is no
# pyenv/pyenv-style interpreter download and no second Python anywhere in the
# image. One interpreter, one venv, many packages.
#
# Usage:
#   install-python-env.sh <requirements-file> [<requirements-file> ...]
#
# The venv is created on the first file and extended by each later file, so the
# reverse image passes both requirements-common.txt and requirements-reverse.txt
# and still ends up with exactly one environment.
#
set -euo pipefail

VENV="${VENV:-/opt/pyenv}"
PIP_INDEX="${PIP_INDEX:-https://pypi.org/simple}"

[[ $# -ge 1 ]] || { echo "usage: $0 <requirements-file> [...]" >&2; exit 1; }
for f in "$@"; do
  [[ -f "$f" ]] || { echo "ERROR: requirements file not found: $f" >&2; exit 1; }
done

if [[ ! -x "$VENV/bin/python" ]]; then
  echo ">> creating venv at $VENV ($(python3 --version))"
  python3 -m venv "$VENV"
fi

# Keep pip current enough to understand modern manylinux tags, but never
# upgrade the interpreter away from the system 3.11.
"$VENV/bin/python" -m pip install --no-cache-dir --disable-pip-version-check \
  --index-url "$PIP_INDEX" --upgrade "pip==26.2.1"

for f in "$@"; do
  echo ">> installing $f"
  # --only-binary=:all: is deliberate: it fails the build instead of silently
  # compiling from source, which is how we catch a pin that has no cp311 wheel
  # before the offline host ever sees it.
  #
  # A file named *-sdist.txt is the explicit exception: those packages have no
  # wheel at all, so they are installed in a second pass without the flag. Keep
  # such files tiny and justified -- see docker/requirements-reverse-sdist.txt.
  case "$(basename "$f")" in
    *-sdist.txt)
      echo "   (source-built pass: --only-binary NOT applied)"
      "$VENV/bin/python" -m pip install --no-cache-dir --disable-pip-version-check \
        --index-url "$PIP_INDEX" \
        -r "$f"
      ;;
    *)
      "$VENV/bin/python" -m pip install --no-cache-dir --disable-pip-version-check \
        --index-url "$PIP_INDEX" --only-binary=:all: \
        -r "$f"
      ;;
  esac
done

echo ">> python-env: $(find "$VENV/lib" -maxdepth 2 -name 'site-packages' | head -1)"
"$VENV/bin/python" --version
"$VENV/bin/python" -m pip list --format=freeze | wc -l | xargs echo ">> packages installed:"

# Record the resolved set for PINS.md / audit.
"$VENV/bin/python" -m pip list --format=freeze > /opt/PYTHON-MANIFEST.txt
