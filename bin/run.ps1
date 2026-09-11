[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Container = $(if ($env:CONTAINER) { $env:CONTAINER } else { "base" }),
    [string]$Image = $env:YOLO_IMAGE,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Command = @()
)

$ErrorActionPreference = "Stop"

# One host folder is mounted, at /workspace. Pick the image with -Container or
# the CONTAINER environment variable: base | cpp | reverse.
switch ($Container) {
    "base" { $defaultImage = "yolo-agent:2.0.0"; $seccompName = "seccomp-base.json"; $flavor = "base" }
    "cpp" { $defaultImage = "yolo-agent-cpp:2.0.0"; $seccompName = "seccomp-toolchain.json"; $flavor = "cpp" }
    "reverse" { $defaultImage = "yolo-agent-reverse-engineering:2.0.0"; $seccompName = "seccomp-toolchain.json"; $flavor = "reverse" }
    default { throw "Container must be base, cpp, or reverse (got '$Container')" }
}
if (-not $Image) { $Image = $defaultImage }

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$envFile = if ($env:YOLO_ENV_FILE) { $env:YOLO_ENV_FILE } else { Join-Path $repoRoot "config\$Container.env" }
$seccomp = Join-Path $repoRoot "config\$seccompName"
$homeVolume = if ($env:YOLO_HOME_VOLUME) { $env:YOLO_HOME_VOLUME } else { "yolo-agent-$Container-home-v1" }
$memory = if ($env:YOLO_MEM) { $env:YOLO_MEM } else { "8g" }
$cpus = if ($env:YOLO_CPUS) { $env:YOLO_CPUS } else { "4" }
$workspace = (Get-Location).Path

if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
    throw "$envFile missing; copy config\$Container.env.example to config\$Container.env"
}

$dockerArgs = @(
    "run", "-it", "--rm", "--name", "yolo-agent-$Container",
    "--user", "10001:10001", "--read-only",
    "--tmpfs", "/tmp:rw,nosuid,size=2g",
    "--tmpfs", "/run:rw,noexec,nosuid,size=64m",
    "--tmpfs", "/dev/shm:rw,noexec,nosuid,size=256m",
    "-v", "${homeVolume}:/home/agent",
    "-v", "${workspace}:/workspace",
    "--cap-drop", "ALL",
    "--security-opt", "no-new-privileges",
    "--security-opt", "seccomp=$seccomp",
    "--memory", $memory, "--cpus", $cpus,
    "--pids-limit", "512",
    "--ulimit", "nofile=2048:2048",
    "--ulimit", "nproc=2048:2048",
    "--stop-timeout", "30",
    "--env-file", $envFile,
    "--env", "YOLO_FLAVOR=$flavor",
    "--workdir", "/workspace",
    $Image
)
$dockerArgs += $Command
& docker @dockerArgs
exit $LASTEXITCODE
