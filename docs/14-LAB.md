# 14 — Running the lab

Four things are shared by everyone: the **fleet repo** and the **skills repo**
in Gitea, and the **monitor** and the **bot**, which run once from
`compose.lab.yaml`.

## The fleet repo (`yolo/fleet`)

One Gitea repository that every container pulls on start (and on `yolo sync`),
if its token can read it. Create it in Gitea as `yolo/fleet` (or set
`YOLO_FLEET_REPO`) and give everyone read access. Layout, every file optional:

```
fleet.env                  settings for everyone (same keys as .env)
people/<name>.env          settings for one person (YOLO_PERSON=<name>)
AGENTS.md                  instructions every agent gets
people/<name>.md           instructions for one person
skills.txt                 skills enabled for everyone, one per line
people/<name>.skills.txt   skills enabled for one person
skills/<skill>/SKILL.md    team skills
packs.json                 skill packs: {"pack": ["skill", ...]}
bot/jobs.json              scheduled jobs for the bot
```

Precedence, later wins: image defaults < `fleet.env` < `people/<name>.env` <
`yolo login` secrets < the person's `.env`. The files are read by bash: quote
values with spaces. **Never put a token in the fleet repo.**

Typical uses:

```bash
# fleet.env — move everyone to a new model
VLLM_MODEL=Qwen/Qwen3.8-27B

# fleet.env — send everyone's traffic through the monitor
VLLM_BASE_URL=http://192.168.1.50:4000/v1
```

Changes reach a container on its next start, or at once with `yolo sync` in it.

## The skills repo (`yolo/skills`)

Optional. A Gitea repo (`YOLO_SKILLS_REPO`) with skill folders at the top level
or under `skills/`, and an optional `packs.json`. It is pulled next to the
fleet repo. The library each person sees is, later wins on a name clash:

1. `/opt/yolo/skills/library` in the image: house skills (`yolo-airgap`,
   `yolo-gitea`, `yolo-cpp`, `yolo-reverse`) and the Apache-licensed skills from
   `anthropics/skills` at a pinned commit.
2. The skills repo.
3. `skills/` in the fleet repo.

Nothing is visible to an agent until enabled: `YOLO_DEFAULT_SKILLS` (image
default `yolo-airgap yolo-gitea skill-creator`), plus `skills.txt`, plus
`people/<name>.skills.txt`, plus what the person enables with
`yolo skills enable`, minus what they disable. See
[03-AGENTS.md](03-AGENTS.md#skills).

## Setting up the lab services

On one machine on the lab network:

```bash
./yolo-agent-3.0.0/install.sh lab
cd ~/yolo/lab
nano .env          # BOT_GITEA_TOKEN, BOT_PUBLIC_URL, BOT_WEBHOOK_SECRET
docker compose up -d
```

Both services use the core image and have no login.

## The monitor (port 4000)

One process (`/opt/yolo/lab/gateway.py`, standard library only) that does two
jobs:

**Proxy.** `http://<lab-host>:4000/v1/*` forwards to SEC09 (`UPSTREAM_URL`,
default `http://192.168.1.101:8000`): OpenAI and Anthropic APIs, streaming
included. For each request it records the person, the agent, the model, tokens,
time to first token, duration and status. The person comes from the
`X-Yolo-Person` header or the `yolo-<person>` API key the agents send; the agent
from the User-Agent. Point containers at it with `VLLM_BASE_URL` (in `fleet.env`
for everyone).

**Model aliases.** `/data/aliases.json` in the monitor's volume maps names to
real model ids, for example `{"default": "Qwen/Qwen3.8-27B"}`. Requests for an
alias are rewritten, and aliases are listed in `/v1/models`. Edit it with:

```bash
docker compose exec monitor sh -c 'cat > /data/aliases.json' < aliases.json
```

**Dashboard.** `http://<lab-host>:4000/` shows:

- status, served model, time range (15 minutes to 30 days), light/dark theme;
- generation tokens per second, requests running and waiting, KV cache use,
  time to first token (p50, p95) and inter-token latency;
- charts of throughput, latency and load over the range, with server up/down
  and model changes marked;
- usage by person and by agent, a 24-hour activity strip;
- GPU cards, when the GPU exporter is set up;
- a request explorer with search.

It scrapes vLLM's `/metrics` every 5 seconds (`SCRAPE_SECONDS`), so the load
charts cover everyone, including traffic that does not go through the proxy;
the per-person numbers cover proxied traffic only.

**Storage.** One SQLite file in the `monitor` volume (`/data/yolo-lab.db`). Raw
samples are kept 3 days; one-minute rollups and the request log 180 days.

**GPU exporter.** On SEC09, with Python 3 and `nvidia-smi`:

```bash
python3 gpu-exporter.py --port 9400      # from the kit's tools/ folder
```

then `GPU_URL=http://192.168.1.101:9400` in the lab `.env` and
`docker compose up -d`.

## The bot (port 9000)

An always-on agent with its own Gitea account. It:

- **reviews pull requests** when they are opened, reopened or updated
  (`BOT_REVIEW_ON`). Drafts are skipped, and so is any PR with `[skip review]`
  in its title. The review is posted as a Gitea review comment: summary,
  numbered problems with file and line, and what it built or ran.
- **answers mentions.** A comment containing `@yolo` (`BOT_MENTION`) on an issue
  or pull request is a request: the bot checks out the repository (the PR branch
  for a pull request), does what was asked, and replies. For code changes on a
  PR from the same repository it commits and pushes to that branch; elsewhere it
  pushes a `yolo/<date>` branch. It never force-pushes.
- **runs scheduled jobs** from the fleet repo's `bot/jobs.json`.

Each job runs a headless agent (`BOT_AGENT`: `opencode`, `claude` or `qwen`) in
a fresh checkout under `/tmp/bot`, one at a time, for at most `BOT_TIMEOUT`
seconds (default 1800). `http://<lab-host>:9000/` lists recent jobs and their
results.

### Setting it up

1. In Gitea, create a user for the bot (for example `yolo`). Give it write
   access to the repositories it should work on.
2. As that user, make a token with repository and issue read/write and user
   read. Put it in the lab `.env` as `BOT_GITEA_TOKEN`.
3. Set `BOT_PUBLIC_URL` to how Gitea reaches the bot, e.g.
   `http://192.168.1.50:9000`, and `BOT_WEBHOOK_SECRET` to any random string.
4. `docker compose up -d`, then install the webhook for a repository or a whole
   organization:

   ```bash
   docker compose exec bot yolo bot hook team/project
   docker compose exec bot yolo bot hook org:team
   ```

   If Gitea refuses to deliver to a LAN address, add the bot host to Gitea's
   `[webhook] ALLOWED_HOST_LIST`.

To review one pull request by hand: `docker compose exec bot yolo bot run
team/project 12`.

The bot's model traffic goes through the monitor (`BOT_VLLM_BASE_URL`, default
`http://monitor:4000/v1`) and shows up there as person `bot`.

### `bot/jobs.json`

```json
[
  {
    "name": "weekly-deps",
    "cron": "0 7 * * 1",
    "repo": "team/project",
    "prompt": "List TODO and FIXME comments added in the last week and summarize them.",
    "issue": 42,
    "enabled": true
  }
]
```

| Field | |
|---|---|
| `name` | label; used in the issue title |
| `cron` | minute hour day-of-month month day-of-week, in the bot's local time; `*`, lists, ranges and `/step` work |
| `repo` | `owner/repo` |
| `prompt` | what to do |
| `issue` | optional: post the result as a comment on this issue; without it the bot opens a new issue |
| `enabled` | optional, default `true` |

The bot reads the file every minute. After pushing a change to the fleet repo,
run `docker compose exec bot yolo sync` (or restart the bot) so it pulls it.
