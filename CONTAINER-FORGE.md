# Container Forge

This repository builds Docker-compatible Linux/amd64 image archives without
Docker-in-Docker and without mounting a host Docker socket. It also builds
happily on any ordinary machine with a Docker daemon — the notes below are the
specifics for the Container Forge workspace.

## Normal workflow

1. Create a Dockerfile and its build context under `/home/coder`.
2. Build and export it:

   ```bash
   cd /home/coder/project
   container-build my-image:1.0 . -f Dockerfile
   ```

3. Open **Exports** in Coder and download the completed bundle directory.
4. In the offline environment, verify `SHA256SUMS`, then use the exact
   `docker load` command written to `LOAD-IN-SCIF.txt`.

Common options:

```bash
container-build yolo-agent-cpp:2.0.0 . \
  -f Dockerfile.cpp --target runtime

container-build yolo-agent:2.0.0 . --reproducible
```

For an archive too large for one approved disc:

```bash
container-split /home/coder/exports/<bundle>/<image>.docker.tar 3900M
```

Registry credentials for private base images can be stored with:

```bash
container-registry-login registry.example.mil USERNAME
```

## Building this repository's three images

The Forge builder runs one Dockerfile at a time, so build and export each image
separately:

```bash
container-build yolo-agent:2.0.0 . --target runtime
container-build yolo-agent-cpp:2.0.0 . -f Dockerfile.cpp --target runtime
container-build yolo-agent-reverse-engineering:2.0.0 . -f Dockerfile.reverse --target runtime
```

Each context is the repository root, because the Dockerfiles share
`docker/install/`, `docker/rootfs/`, `docker/requirements-*.txt`, `config/`, and
`docs/`. The `.dockerignore` allowlist covers all three Dockerfiles.

To validate an image before exporting it, build the `test` target instead — that
runs the per-image smoke suite (agent versions, a compiled ELF64 and PE32+
binary, a real PyInstaller extraction, and the three HTTP surfaces):

```bash
container-build yolo-agent-cpp:2.0.0-test . -f Dockerfile.cpp --target test
```

With an ordinary Docker daemon and BuildKit, `docker buildx bake` does all three
plus their smoke suites in one command.

### Packaging offline bundles

On a machine with a Docker daemon and the built images:

```bash
./scripts/package-offline.sh 2.0.0 \
  base:yolo-agent:2.0.0 \
  cpp:yolo-agent-cpp:2.0.0 \
  reverse:yolo-agent-reverse-engineering:2.0.0 \
  -- dist
```

That produces one ZIP per image, each containing the image archive, launchers,
the matching compose file, seccomp profile, env template, documentation,
checksums, and a `LOAD-OFFLINE.txt` with the exact load commands. A bundle that
would exceed GitHub's 2 GiB asset limit is split into numbered parts with a
`REASSEMBLE.txt`.

## Important boundaries

- The target is Linux/amd64, matching the intended offline Docker hosts. All
  three images are single-architecture by design; multi-arch would multiply
  the size of every offline bundle.
- This workspace builds images but does not run them. Put validation in a
  Dockerfile `test` target and build that stage with `--target`.
- Build contexts and Dockerfiles must remain under `/home/coder` because that is
  the only volume mounted into the disposable builder.
- The builder is recycled after every build, so one Dockerfile cannot leave
  filesystem state behind for the next one.
- Builds need network access for their pinned downloads. The exported images do
  not: everything is fetched at build time and baked in. See
  [PINS.md](PINS.md) for the complete list.
