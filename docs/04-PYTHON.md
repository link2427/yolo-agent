# 04 — Python

Every yolo-agent image ships exactly **one** Python environment:

```
interpreter   /opt/pyenv/bin/python3      Python 3.11
on PATH       /opt/pyenv/bin is FIRST
env var       VIRTUAL_ENV=/opt/pyenv
```

There is no second interpreter, no conda, no per-agent virtualenv, and no
`uv`-managed Python. `python3`, `python`, `pip`, and `pip3` all resolve into
`/opt/pyenv`.

```bash
python3 --version        # 3.11.x
which python3            # /opt/pyenv/bin/python3
python3 -c 'import sys; print(sys.prefix)'
```

The system interpreter at `/usr/bin/python3` is the same Debian bookworm 3.11
build; `/opt/pyenv` is a venv on top of it. That is why the project can promise
one interpreter version everywhere without shipping a second Python.

## Why 3.11 specifically

Debian 12 (bookworm) ships Python 3.11 as its system interpreter, so targeting
3.11 costs nothing: no pyenv, no compiled interpreter, no download. It is also
the last version that the decompilation ecosystem supports broadly, which
matters for the reverse-engineering image.

Several popular packages have since moved to requiring 3.12 or newer. Those are
pinned to their last 3.11-compatible release on purpose — see
[11-PINS-INTEGRITY.md](11-PINS-INTEGRITY.md) for the list and the reasoning.

## What is installed

The base set comes from `docker/requirements-common.txt` and is present in all
three images (~45 packages, all installed from wheels — nothing compiles from
source at build time):

| Group | Packages |
|---|---|
| HTTP / APIs | `requests`, `httpx`, `urllib3`, `certifi`, `websockets` |
| CLI / terminal | `click`, `typer`, `rich`, `pygments`, `colorama`, `tabulate`, `tqdm`, `questionary`, `prompt-toolkit` |
| data / config | `pydantic`, `pyyaml`, `tomli`, `tomli-w`, `json5`, `python-dotenv`, `packaging`, `python-dateutil`, `arrow`, `jsonschema` |
| numerics | `numpy` |
| parsing | `lxml`, `beautifulsoup4`, `html5lib`, `markdown-it-py` |
| files / system | `gitpython`, `pathspec`, `filelock`, `platformdirs`, `psutil`, `watchdog`, `tenacity`, `structlog` |
| testing | `pytest`, `pytest-cov`, `hypothesis` |
| lint / format | `ruff`, `black`, `isort`, `flake8` |
| shell | `ipython` |

The exact resolved set is recorded inside the image:

```bash
cat /opt/PYTHON-MANIFEST.txt
```

## The reverse-engineering image adds to the same environment

`yolo-agent-reverse-engineering` does **not** create a second venv. It installs
`docker/requirements-reverse.txt` on top of the shared environment, so
`/opt/pyenv` ends up containing both sets:

```
requests, pydantic, pytest, ...        from requirements-common.txt
+ pyinstxtractor-ng, xdis, pydumpck   from requirements-reverse.txt
+ capstone, unicorn, angr, lief, pefile, pyelftools
```

`docker/requirements-reverse.txt` documents one deliberate omission
(`uncompyle6`, which conflicts with `pyinstxtractor-ng` over the exact `xdis`
version). The details are in
[06-REVERSE-ENGINEERING.md](06-REVERSE-ENGINEERING.md).

## Using it

```bash
# Run a script.
python3 script.py

# Use a package from a shell one-liner.
python3 -c 'import httpx, rich; print(httpx.__version__)'

# Check what is installed.
pip list

# Start an interactive shell with autocompletion.
ipython
```

### The air-gap warning

**`pip install` cannot reach the internet on the offline host.** The index is
unavailable, so any install fails. The environment as shipped is the
environment you get.

If you need a package that is not in the image:

1. Add the exact pin to `docker/requirements-common.txt` (or
   `docker/requirements-reverse.txt`, for the reverse image).
2. Confirm a CPython 3.11 linux/amd64 wheel exists:
   `pip download --only-binary=:all: --python-version 3.11 -d /tmp/x <pkg>==<ver>`
3. Rebuild and re-export the image on a networked machine.

The build enforces `--only-binary=:all:`, so a pin with no wheel fails the
build rather than silently trying to compile.

Because `/opt` is read-only inside the running container, `pip install` at
runtime writes into the venv only if `/opt/pyenv` is writable — it is not. Use
`pip install --target` into `/workspace` or `/home/agent` if you genuinely need
an ad-hoc package at runtime:

```bash
pip install --target /workspace/.pylibs <package>
PYTHONPATH=/workspace/.pylibs python3 script.py
```

This is a workaround, not a supported workflow: the package is not pinned and
not reproducible. Prefer rebuilding the image.

## Writing code for this environment

- Target **Python 3.11** — do not use 3.12+ syntax such as PEP 695 `type`
  statements or `itertools.batched` assumptions.
- Prefer the packages already installed over adding new dependencies; the
  standard library covers most of what an agent needs.
- `ruff` and `black` are available for formatting and linting:
  `ruff check .`, `black --check .`
- `pytest` is the test runner; `pytest -q` works with no configuration.

## Isolation

The Python environment is inside the container, so installing, breaking, or
deleting packages cannot affect the host. Removing and recreating the
container's home volume resets any per-user Python state:

```bash
docker volume rm yolo-agent-base-home-v1
```
