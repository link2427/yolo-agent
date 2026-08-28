# Container Forge

This workspace builds Docker-compatible Linux/amd64 image archives without
Docker-in-Docker and without mounting a host Docker socket.

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
container-build pytorch-scif:1.0 . \
  --build-arg CUDA_VERSION=13.0 \
  --target runtime

container-build opencode-scif:1.0 . --reproducible
```

For an archive too large for one approved disc, run:

```bash
container-split /home/coder/exports/<bundle>/<image>.docker.tar 3900M
```

Registry credentials for private base images can be stored with:

```bash
container-registry-login registry.example.mil USERNAME
```

## Important boundaries

- The target is Linux/amd64, matching the intended offline Docker hosts.
- This workspace builds images but does not run them. Put validation in a
  Dockerfile test stage and build that stage with `--target`.
- Build contexts and Dockerfiles must remain under `/home/coder` because
  that is the only volume mounted into the disposable builder.
- The builder is recycled after every build so one Dockerfile cannot leave
  filesystem state behind for the next one.
