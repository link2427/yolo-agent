# yolo-agent 2.x build matrix — three images, one repo.
#
#   docker buildx bake              # build + smoke-test every image
#   docker buildx bake images       # build the three shippable images
#   docker buildx bake base         # one image (also: cpp, reverse)
#   docker buildx bake tests        # smoke suite only (same as the default)
#
# Each image is self-contained: it materializes a complete filesystem, so a
# `docker load` of any single archive is enough to run that container offline.
# There is no separately published base image to chase.

variable "REGISTRY" {
  default = "ghcr.io/link2427"
}

variable "VERSION" {
  default = "2.0.0"
}

variable "VCS_REF" {
  default = "local"
}

target "_common" {
  context = "."
  platforms = ["linux/amd64"]
  args = {
    VERSION = VERSION
    VCS_REF = VCS_REF
  }
  # Declared empty so CI can enable the GitHub Actions cache with
  # `--set '<target>.cache-from=...'` / `--set '<target>.cache-to=...'`
  # without touching this file.
  cache-from = []
  cache-to = []
}

# --- yolo-agent (base) ------------------------------------------------------
target "base" {
  inherits = ["_common"]
  dockerfile = "Dockerfile"
  target = "runtime"
  tags = [
    "${REGISTRY}/yolo-agent:${VERSION}",
    "yolo-agent:${VERSION}",
  ]
}

target "base-test" {
  inherits = ["_common"]
  dockerfile = "Dockerfile"
  target = "test"
  args = {
    VERSION = VERSION
    VCS_REF = VCS_REF
  }
}

# --- yolo-agent-cpp ---------------------------------------------------------
target "cpp" {
  inherits = ["_common"]
  dockerfile = "Dockerfile.cpp"
  target = "runtime"
  tags = [
    "${REGISTRY}/yolo-agent-cpp:${VERSION}",
    "yolo-agent-cpp:${VERSION}",
  ]
}

target "cpp-test" {
  inherits = ["_common"]
  dockerfile = "Dockerfile.cpp"
  target = "test"
  args = {
    VERSION = VERSION
    VCS_REF = VCS_REF
  }
}

# --- yolo-agent-reverse-engineering -----------------------------------------
target "reverse" {
  inherits = ["_common"]
  dockerfile = "Dockerfile.reverse"
  target = "runtime"
  tags = [
    "${REGISTRY}/yolo-agent-reverse-engineering:${VERSION}",
    "yolo-agent-reverse-engineering:${VERSION}",
  ]
}

target "reverse-test" {
  inherits = ["_common"]
  dockerfile = "Dockerfile.reverse"
  target = "test"
  args = {
    VERSION = VERSION
    VCS_REF = VCS_REF
  }
}

# `bake` with no arguments runs everything through its smoke suite.
group "default" {
  targets = ["base-test", "cpp-test", "reverse-test"]
}

group "images" {
  targets = ["base", "cpp", "reverse"]
}

group "tests" {
  targets = ["base-test", "cpp-test", "reverse-test"]
}
