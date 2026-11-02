# Plan: bump opencode and pi, add pi sub-agents

Status: **proposed, not built.** Written 2026-11-02 against `v2.0.0` (`060eab5`).

Companion to `REVAMP.md`. That document changes the container contract; this one
changes what runs inside it. They can ship independently.

---

## 1. Targets

| Agent | Pinned today | Target | Released |
| --- | --- | --- | --- |
| opencode | 1.18.30 | **1.19.5** | 2026-10-28 |
| pi | 0.85.1 | **1.5.0** | 2026-11-02 |
| DeepSeek Harness (`dsh`) | 0.1.5-rc.1 | **removed** | — |

Both bumps keep the existing download URL shape, so `install-agents.sh` needs
only the version constants changed:

```
https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz   # 76.0 MiB
https://github.com/earendil-works/pi/releases/download/v${PI_VERSION}/pi-linux-x64.tar.gz                # 56.1 MiB
https://github.com/earendil-works/pi/releases/download/v${PI_VERSION}/SHA256SUMS
```

Verified present in both target releases.

Note that opencode `1.19.5` also publishes `-baseline` and `-musl` variants. The
existing choice (`opencode-linux-x64`) remains correct for the Debian glibc base.

---

## 2. Risk: pi is a major version bump released today

0.85.1 to 1.5.0 crosses a major boundary, and 1.5.0 was published 2026-11-02,
the same day this was written. Two consequences:

- Treat it as a **new** agent, not a patch. It must go through the smoke suite
  before any burn.
- If 1.5.0 misbehaves, the fallback is the last 1.x release before it (1.4.0),
  not 0.85.1; the config surface changed shape at 1.0.

### 2.1 Breaking change in 1.5.0

Tool argument validation moved to `@earendil-works/pi-schema`. TypeBox features
outside JSON Schema (`Type.Refine()`, `Type.BigInt()`, `Type.Undefined()`,
codecs, `Format.Set()`) no longer apply to tool arguments. Plain JSON Schema
tools, including MCP tools, now get the same coercion as TypeBox tools.

Exposure here is **low**: the image ships no pi extensions or custom tools, so
nothing defines TypeBox schemas. This matters only once sub-agents or other
extensions are added, which is exactly what section 4 proposes.

### 2.2 Config compatibility: verified unchanged

The five settings keys currently written to `~/.pi/agent/settings.json` all
still exist in 1.x `settings.md`:

`enableInstallTelemetry`, `defaultProjectTrust`, `defaultProvider`,
`defaultModel`, `defaultThinkingLevel`.

The `compat` keys written to `models.json` also still exist in 1.x
`models-configuration.md`:

| Key | 1.x status |
| --- | --- |
| `authHeader` | documented, boolean |
| `supportsDeveloperRole` | documented |
| `supportsReasoningEffort` | documented |
| `thinkingFormat` | documented, `qwen-chat-template` still a valid value |

So `configure-agents.sh` needs no change for the bump. One improvement worth
considering: 1.x adds `"qwen"` as a `thinkingFormat` value (top-level
`enable_thinking`) distinct from `"qwen-chat-template"`
(`chat_template_kwargs.enable_thinking`). For a Qwen3.8 model on vLLM the
top-level form may be the more direct route. Current value works; this is an
optimisation, not a fix.

---

## 3. PINS.md changes required

| Row | Change |
| --- | --- |
| opencode 1.18.30 | to 1.19.5, sha256 TOFU `5500724685…699d17` re-recorded |
| pi 0.85.1 | to 1.5.0, sha256 verified against the release `SHA256SUMS` |
| DeepSeek Harness | row **deleted** |

opencode publishes no checksums for its release tarballs, so the TOFU pattern
continues. pi publishes `SHA256SUMS` in the release, and the build already
prefers that over the pinned hash, so the pi row stays verifiable.

Deleting the `dsh` row also removes the reason `install-node.sh` is duplicated
into every Dockerfile stage as a comment explains it exists so corepack/npm are
available *before* the runtime stage for the harness install. If nothing else
needs npm at that point, that duplication and its comment both go. Verify before
removing; Node is still needed at runtime for pi.

---

## 4. pi sub-agents

**pi does not ship sub-agents.** From the README, verbatim:

> Pi ships with powerful defaults but skips features like sub-agents and plan
> mode. Ask Pi to build what you want, or install a package that does it your
> way.

So this is a build task, not a version bump. Two routes:

### Route A: published extension `pi-subagents`

| Property | Value |
| --- | --- |
| Package | `pi-subagents` |
| Version | 0.84.0 |
| Description | "Pi extension for single-agent delegation and scripted multi-agent workflows" |
| Source | `github.com/nicobailon/pi-subagents` |
| Peer deps | `@earendil-works/pi-ai >= 1.2.0`, `@earendil-works/pi-coding-agent *` |
| Transitive deps | `jiti 2.7.0`, `yaml 2.8.3`, `acorn 8.18.0`, `undici 8.12.3`, `@js-temporal/polyfill 0.5.1` |

**Version trap:** the package is numbered 0.84.0, which looks like it pairs with
pi 0.84.x, but that is a coincidence. The real constraint is the peer dep
`pi-ai >= 1.2.0`, which **1.5.0 satisfies**. Do not "downgrade pi to match the
extension number"; that would be backwards.

Risk: third-party package, single maintainer, five transitive dependencies. It is
the same trust shape the `dsh` install already had, and the same mitigation
applies: exact version plus a complete transitive integrity lock.

### Route B: write our own extension

pi documents the extension surface with a `subagent/` example under
`registerTool` and `exec`, described as "Spawn sub-agents". An in-repo extension
would be smaller, fully auditable, and pinned by commit rather than by npm.

Cost: we maintain it. Benefit: no third-party dependency in the supply chain, and
it can be written specifically for vLLM-only operation.

### Recommendation

**Route A for the first pass**, because it is a pinned artifact with a lockfile
rather than code we have to own, and the smoke suite can validate it in the same
way it validated `dsh`. Switch to Route B only if 0.84.0 proves incompatible or
unmaintained.

Either route must be vendored at build time: npm is unreachable on the target
network. The `dsh` removal frees the exact mechanism needed, an exact top-level
version plus a complete transitive `integrity:` lock, so reuse that pattern
rather than inventing a new one.

### 4.1 Interaction with T3

T3 launches pi and owns its process lifecycle. It rejects launch arguments that
change pi's execution mode or select a session. A sub-agent extension is
in-process, so it is invisible to T3 and needs no T3 configuration. Worth
confirming in a smoke test that delegate calls still spawn correctly when pi is
not attached to a TTY, since T3 runs it headless.

### 4.2 Interaction with the air gap

Sub-agents multiply model requests. On a single vLLM endpoint serving
`qwen3.8-27b`, parallel delegation can saturate the endpoint and slow every other
user's requests. If three containers each fan out, the endpoint becomes the
bottleneck before the CPU or RAM does. Consider a concurrency cap per container,
and check vLLM's `--max-num-seqs` before enabling fan-out for everyone.

---

## 5. Test plan

The existing smoke suite (`docker/tests/smoke-common.sh`) is the gate, run as the
image's `test` target. Both bumps must extend it, because a major pi version and
a new extension are exactly what unit-level checks miss.

Add to the smoke suite:

1. `opencode --version` is 1.19.5 and the binary runs.
2. `pi --version` is 1.5.0 and the binary runs.
3. `pi` loads `settings.json` and `models.json` without warning, against a stub
   OpenAI-compatible endpoint.
4. The configured model appears in pi's model list.
5. With the sub-agent extension installed, the extension loads and its tool is
   registered (`pi` extension listing or equivalent).
6. A delegated sub-agent task completes against the stub endpoint.
7. `dsh` is absent, and no script references it.
8. The T3 entrypoint path configures agents and git with no `.bashrc` in play
   (see `REVAMP.md` section 5).
9. SVG handling: feed a small SVG to the agent against the stub endpoint and
   assert the failure mode. If it still reports a missing rasterizer, assert
   `rsvg-convert` is present and produces a non-empty PNG (section 7).

A stub endpoint is required because CI has no vLLM. A small Python server that
answers `/v1/models` and a fixed `/v1/chat/completions` is enough, and it also
lets tests assert that reasoning-effort and thinking-format parameters are sent
in the shape pi expects.

---

## 7. Multi-modal gap: SVG cannot be seen (2.0.0 issue, unverified in 1.5.0)

Reported against 2.0.0: Qwen cannot see SVG output. The failure mentions a
missing **rasterizer**, which means something in the stack did try to convert
the SVG into an image before sending it, and found no tool to do it.

### 7.1 Why a rasterizer is involved at all

Multimodal models consume **raster** images (PNG/JPEG), usually as base64 data
URLs on an `image_url` content part. SVG is XML text, not a raster image, so it
cannot be passed through directly. Anything that wants a model to "look at" an
SVG must first rasterize it.

The 2.0.0 image ships no rasterizer of its own:

| Candidate | In 2.0.0? |
| --- | --- |
| `rsvg-convert` (`librsvg2-bin`) | no |
| ImageMagick (`convert` / `magick`) | no |
| `cairosvg` (Python) | no |
| `resvg` | no |
| headless Chrome | no |

So if the harness or the model wrapper looks for one, it fails exactly as
reported.

### 7.2 pi 1.5.0 probably does not fix this

The bump is **unverified** against this specific issue. pi is a harness: it
decides what to send to the model, but it does not bundle image converters, and
the 1.5.0 release notes do not mention SVG, rasterization, or image handling.

Two possibilities, and they need different fixes:

- If pi gained an internal SVG path in 1.x, the bump fixes it and nothing else is
  needed.
- If pi still shells out to a system rasterizer, the gap persists and the image
  must provide one.

Check before assuming either. Cheap test once a build exists: give the agent a
small SVG in a fresh container and see whether the error changes shape.

### 7.3 Cheapest fix: add a rasterizer to the base image

`librsvg2-bin` is a few MiB and comes from the Debian archive already used by
`system-deps.sh`, so it costs almost nothing in build time or image size.

| Option | Size | Notes |
| --- | --- | --- |
| `librsvg2-bin` | ~1-2 MiB | `rsvg-convert -w 1600 -h 1600 in.svg -o out.png`; most direct |
| `imagemagick` | ~15 MiB | also handles many other formats; heavier, and its SVG delegate still routes through librsvg |
| `cairosvg` | small pip | adds a Python dependency and a native cairo requirement |

Recommendation: `librsvg2-bin`, invoked explicitly. It is the smallest change and
its behaviour is predictable.

### 7.4 Two caveats

**Is the model actually multimodal?** A text-only model cannot consume an image
no matter what rasterizer exists; the request would be rejected or the image
ignored. Confirm `qwen3.8-27b` on SEC09 accepts image content at all before
spending effort here. If it is text-only, the correct answer is to convert SVG to
a **text** description, not to a raster.

**Rasterizing is not the same as seeing.** SVG diagrams often carry meaning in
small text. A default 800px render can make labels illegible, and the model will
then guess. Rasterize at a generous width and, where the SVG is simple, consider
also emitting its text nodes so the model has both.

### 7.5 Interaction with T3's headless Chrome

If T3's headless Chrome is resolved (see `REVAMP.md` section 4.4), it is itself a
rasterizer: Chrome renders SVG natively. That would close this gap as a side
effect for anything routed through T3's browser, and is an argument for solving
the Chrome question rather than deferring it.

The two are not equivalent though. A browser renders on demand for browser and
preview features; a CLI rasterizer is usable by any tool, including an agent
shelling out. Adding `librsvg2-bin` is worth doing regardless.

---

## 8. Sequencing

1. Bump `OPENCODE_VERSION`/`PI_VERSION`, drop `dsh`, update `PINS.md`, record
   hashes. Smallest diff that proves the bumps work.
2. Extend the smoke suite with items 1-4 and 7. Run in CI.
3. Vendor `pi-subagents`, add items 5-6. Run in CI.
4. Only after green: the `REVAMP.md` changes (T3, compose, one image).

Doing the bumps before the revamp means a failure is attributable to the bump
rather than to the restructure. Doing them together makes a red build ambiguous.
