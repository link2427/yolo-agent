variable "REGISTRY" {
  default = "ghcr.io/link2427"
}

variable "VERSION" {
  default = "1.2.0"
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

target "image" {
  inherits = ["_common"]
  target   = "runtime"
  tags = [
    "${REGISTRY}/yolo-agent:${VERSION}",
    "yolo-agent:${VERSION}",
  ]
}

target "test" {
  inherits = ["_common"]
  target   = "test"
}

group "default" {
  targets = ["test"]
}

group "images" {
  targets = ["image"]
}
