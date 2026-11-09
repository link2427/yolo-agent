# yolo-agent 3 build matrix: one Dockerfile, three tiers of one image.
#
#   docker buildx bake              build every tier through its smoke suite
#   docker buildx bake images       the three shippable tiers
#   docker buildx bake core         one tier (also: cpp, full)
#
# Tags: yolo-agent:<version>-core | -cpp | -full. The tiers share their lower
# layers and an identical "apps" layer, so `docker save` of all three together
# is barely larger than the full tier alone.

variable "REGISTRY" {
  default = "ghcr.io/link2427"
}

variable "VERSION" {
  default = "3.0.0"
}

variable "VCS_REF" {
  default = "local"
}

target "_common" {
  context    = "."
  dockerfile = "Dockerfile"
  platforms  = ["linux/amd64"]
  args = {
    VERSION = VERSION
    VCS_REF = VCS_REF
  }
  # Declared empty so CI can enable a cache with --set without editing this file.
  cache-from = []
  cache-to   = []
}

target "core" {
  inherits = ["_common"]
  target   = "core"
  tags     = ["${REGISTRY}/yolo-agent:${VERSION}-core", "yolo-agent:${VERSION}-core"]
}

target "cpp" {
  inherits = ["_common"]
  target   = "cpp"
  tags     = ["${REGISTRY}/yolo-agent:${VERSION}-cpp", "yolo-agent:${VERSION}-cpp"]
}

target "full" {
  inherits = ["_common"]
  target   = "full"
  tags = [
    "${REGISTRY}/yolo-agent:${VERSION}-full",
    "${REGISTRY}/yolo-agent:${VERSION}",
    "yolo-agent:${VERSION}-full",
  ]
}

target "core-test" {
  inherits = ["_common"]
  target   = "core-test"
}

target "cpp-test" {
  inherits = ["_common"]
  target   = "cpp-test"
}

target "full-test" {
  inherits = ["_common"]
  target   = "full-test"
}

group "default" {
  targets = ["core-test", "cpp-test", "full-test"]
}

group "images" {
  targets = ["core", "cpp", "full"]
}

group "tests" {
  targets = ["core-test", "cpp-test", "full-test"]
}
