# 02 — Quickstart

## Which container do you want?

| You are… | Use | Compose file |
|---|---|---|
| writing general code | `yolo-agent` | `compose.yaml` |
| building C or C++ (including 64-bit Windows binaries) | `yolo-agent-cpp` | `compose.cpp.yaml` |
| decompiling `.exe` files or analysing binaries | `yolo-agent-reverse-engineering` | `compose.reverse.yaml` |

The three flavors use **separate home volumes and separate env files**. Setting
up the base flavor does not configure the C++ one.

## Building (on a networked machine)

```bash
# Everything: build all three images and run their smoke suites.
docker buildx bake

# The three shippable images, no smoke suite.
docker buildx bake images

# One image.
docker buildx bake base
docker buildx bake cpp
docker buildx bake reverse

# Directly, if you are not using bake.
docker build --target runtime -t yolo-agent:2.0.0 .
docker build --target runtime -f Dockerfile.cpp     -t yolo-agent-cpp:2.0.0 .
docker build --target runtime -f Dockerfile.reverse -t yolo-agent-reverse-engineering:2.0.0 .
```

`docker buildx bake` with no arguments builds the `test` target of each image.
Those targets are the real gate: they assert on the agent versions, check that
the removed agents are absent, compile an ELF64 **and** a PE32+ binary, extract
a real PyInstaller archive, and start code-server, ttyd, and the DeepSeek
Harness UI. A pin drift fails the build here instead of on the offline host.

Every download happens during this build. After it finishes, nothing in these
images reaches the network again.

## Installing offline

Each release attaches one ZIP per image:

```
yolo-agent-base-2.0.0-offline.zip
yolo-agent-cpp-2.0.0-offline.zip
yolo-agent-reverse-engineering-2.0.0-offline.zip
```

On the air-gapped host:

```bash
# 1. Unzip and verify the image archive.
unzip yolo-agent-base-2.0.0-offline.zip
cd yolo-agent-base-2.0.0-offline
sha256sum -c SHA256SUMS          # Windows: see LOAD-OFFLINE.txt
#    (also verify the ZIP itself against the .zip.sha256 sidecar)

# 2. Load the image.
docker load --input yolo-agent-base_2.0.0.docker.tar

# 3. Configure and run.
cp config/base.env.example config/base.env
$EDITOR config/base.env
docker compose up -d
```

If a ZIP exceeded GitHub's 2 GiB asset limit it ships as numbered
`.part-NN` files with a `REASSEMBLE.txt`; download every part plus both
checksum files and follow those instructions first.

`LOAD-OFFLINE.txt` inside each bundle repeats these steps with the exact
filenames for that image and both Linux and PowerShell variants.

## Configure the model endpoint

Every agent needs an OpenAI-compatible endpoint on your LAN. Edit the flavor's
env file:

```bash
VLLM_BASE_URL=http://192.168.1.50:8000/v1
VLLM_MODEL=Qwen/Qwen3.8-27B
VLLM_CONTEXT=262144
VLLM_REASONING_EFFORT=xhigh
VLLM_API_KEY=local
```

Check the endpoint answers before you blame the container:

```bash
curl "$VLLM_BASE_URL/models"
```

Full details, including the LM Studio alternative, are in
[09-MODEL-ENDPOINT.md](09-MODEL-ENDPOINT.md).

## Running

### Interactive shell

```bash
# Compose (project directory = current directory).
docker compose run --rm agent

# Or the launchers.
./bin/run.sh                     # base
CONTAINER=cpp ./bin/run.sh       # C/C++
CONTAINER=reverse ./bin/run.sh   # reverse engineering
```

`bin/run.sh` mounts the **current working directory** at `/workspace`, so `cd`
into your project first. Set `YOLO_WORKSPACE` to override.

### Persistent browser stack

```bash
./bin/run-server.sh                       # base: IDE + terminal
docker compose up -d                      # base: + DeepSeek Harness
docker compose -f compose.cpp.yaml up -d
```

| Surface | URL |
|---|---|
| VS Code (code-server) | `http://<host>:8080` |
| Terminal (ttyd + tmux) | `http://<host>:7681` |
| DeepSeek Harness | `http://<host>:3080` |

All three bind `0.0.0.0` and code-server has **no password**. Put them on a
trusted network or set `YOLO_BIND_ADDRESS=127.0.0.1` and use an SSH tunnel. See
[07-WEB-IDE.md](07-WEB-IDE.md) and [10-SECURITY.md](10-SECURITY.md).

Windows hosts use `bin\run.ps1` and `bin\run-server.ps1`; both accept
`-Container base|cpp|reverse`.

## First five minutes inside the container

```bash
# Is the endpoint configured for the agents?
jq -e '.provider.vllm' ~/.config/opencode/opencode.json

# The agents.
opencode           # then /models
pi                 # then /effort
dsh web            # browser UI, already relayed by the compose service

# The single Python environment.
python3 --version          # 3.11.x
pip list | head

# What is available, per flavor.
cat /opt/PYTHON-MANIFEST.txt
cat /opt/yolo/EXTENSIONS-MANIFEST.txt
```

## Exporting your own bundle

```bash
./scripts/package-offline.sh 2.0.0 \
  base:yolo-agent:2.0.0 \
  cpp:yolo-agent-cpp:2.0.0 \
  reverse:yolo-agent-reverse-engineering:2.0.0 \
  -- dist
```

Each `name:tag` produces its own ZIP, with the compose file, the matching
seccomp profile, the env template, the launchers, the docs, and checksums. The
script splits a bundle automatically if it would exceed GitHub's 2 GiB asset
limit.

## Next

- [03-AGENTS.md](03-AGENTS.md) — agent configuration and persistence
- [13-COMMAND-REFERENCE.md](13-COMMAND-REFERENCE.md) — the short version of everything above
- [12-TROUBLESHOOTING.md](12-TROUBLESHOOTING.md) — when something does not work
