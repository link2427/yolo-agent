# 02 — Quickstart

Five steps from disc to running agents.

## 1. Load the image (destination Docker host)

```bash
# copy the whole bundle directory onto the disc, then:
sha256sum -c SHA256SUMS            # verify integrity
docker load --input yolo-dev_5.0.docker.tar
docker image inspect yolo-dev:5.0  # confirm the tag
```

## 2. Create the launcher directory

The bundle's `run-yolo.sh`, `run-yolo-server.sh`, `seccomp-yolo.json` and
`yolo.env.example` should live next to each other on the host (keep them
together — the launchers reference `seccomp-yolo.json` and `yolo.env` by
relative path).

```bash
mkdir ~/yolo && cd ~/yolo
# copy run-yolo.sh, run-yolo-server.sh, seccomp-yolo.json, yolo.env.example here
chmod +x run-yolo.sh run-yolo-server.sh
cp yolo.env.example yolo.env
```

## 3. Configure `yolo.env`

Minimum (vLLM):

```bash
VLLM_BASE_URL=http://192.168.1.50:8000/v1   # your vLLM server
VLLM_MODEL=Qwen/Qwen3-Coder-30B-AWQ         # a model id it serves
```

Optional: Gitea git push (see 06), LM Studio instead of vLLM (see 07), auth
keys (`VLLM_API_KEY`, `OPENAI_API_KEY`).

## 4a. Run interactively (terminal)

```bash
cd ~/yolo
./run-yolo.sh                # shell as uid 10001, cwd mounted as /workspace
```

On first shell, agents auto-configure from `yolo.env` (endpoint + git), then:

```bash
opencode                  # /models to pick the model
pi --model vllm/<model>
prime-agent
goose
aider
```

## 4b. Run as a server (browser access)

```bash
./run-yolo-server.sh       # detached; code-server :8080, ttyd+tmux :7681
docker logs -f yolo-server
```

Then open `http://<host>:8080` (VS Code) or `http://<host>:7681` (terminal).

## 5. Stop

```bash
docker stop yolo-server          # server mode
# interactive mode exits when you exit the shell (--rm auto-cleans)
```

## Notes

- The `yolo-home-v5` named volume holds `/home/agent` (configs, skills farm,
  git credentials, agent sessions) and persists across container restarts.
- Your working directory is mounted read-write as `/workspace` — that's the
  only host path the container can touch.
- First launch of a fresh volume copies the baked home content (configs,
  skills, prime-agent kernel) into it; allow a few seconds.
