# 02 — Quickstart

## Offline/disc installation

Download the `yolo-agent-<version>-offline.zip` asset from the GitHub release,
copy it to the disc, unzip it on the destination, and follow
`LOAD-OFFLINE.txt`. The bundle includes the Docker image, its checksum,
launchers, runtime configuration, and these docs. No registry connection is
needed after the image is loaded.

## 1. Configure runtime values

```bash
cp config/yolo.env.example config/yolo.env
```

At minimum, set VLLM_BASE_URL and VLLM_MODEL, or configure the alternative
endpoint variables described in [07-MODEL-ENDPOINT.md](07-MODEL-ENDPOINT.md).
Real keys belong only in config/yolo.env; Git ignores that file.

## 2. Build and validate

```bash
docker buildx bake          # build + smoke test
docker buildx bake images   # build only
```

To use a published image, set YOLO_IMAGE to a GHCR tag.

## 3. Start a shell

```bash
docker compose run --rm agent
# or: ./bin/run.sh
```

The current directory is /workspace; agent state persists in the named home
volume even though the interactive container is removed at exit.

## 4. Start the browser services

```bash
docker compose up -d
docker compose logs -f server
```

Defaults (bound to the internal network, i.e. 0.0.0.0):

- code-server: http://<host>:8080
- ttyd/tmux: http://<host>:7681
- OpenHands: http://<host>:3000
- DeepSeek Harness: http://<host>:3080

## 5. Stop without deleting state

```bash
docker compose down
```

Do not add --volumes unless you intentionally want to delete the persisted
agent home.
