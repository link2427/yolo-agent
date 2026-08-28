variable "REGISTRY" {
  default = "ghcr.io/link2427"
}

variable "VERSION" {
  default = "1.0.0"
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
}

target "headless" {
  inherits = ["_common"]
  target   = "runtime-headless"
  tags = [
    "${REGISTRY}/yolo-agent:${VERSION}-headless",
    "yolo-agent:${VERSION}-headless",
  ]
}

target "full" {
  inherits = ["_common"]
  target   = "runtime-full"
  tags = [
    "${REGISTRY}/yolo-agent:${VERSION}",
    "yolo-agent:${VERSION}",
  ]
}

target "test-headless" {
  inherits = ["_common"]
  target   = "test-headless"
}

target "test-full" {
  inherits = ["_common"]
  target   = "test-full"
}

group "default" {
  targets = ["test-headless", "test-full"]
}

group "images" {
  targets = ["headless", "full"]
}
