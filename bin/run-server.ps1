[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Container = $(if ($env:CONTAINER) { $env:CONTAINER } else { "base" }),
    [string]$Image = $env:YOLO_IMAGE
)

$ErrorActionPreference = "Stop"

# Persistent browser stack: code-server (:8080) + ttyd/tmux terminal (:7681).
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
$bindAddress = if ($env:YOLO_BIND_ADDRESS) { $env:YOLO_BIND_ADDRESS } else { "0.0.0.0" }
$codePort = if ($env:YOLO_CODE_PORT) { $env:YOLO_CODE_PORT } else { "8080" }
$terminalPort = if ($env:YOLO_TERMINAL_PORT) { $env:YOLO_TERMINAL_PORT } else { "7681" }
$workspace = (Get-Location).Path
$name = "yolo-agent-$Container-server"

if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
    throw "$envFile missing; copy config\$Container.env.example to config\$Container.env"
}

& docker rm -f $name 2>$null | Out-Null
$dockerArgs = @(
    "run", "-d", "--name", $name, "--restart", "unless-stopped",
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
    "--pids-limit", "2048",
    "--ulimit", "nofile=2048:2048",
    "--ulimit", "nproc=2048:2048",
    "--stop-timeout", "30",
    "-p", "${bindAddress}:${codePort}:8080",
    "-p", "${bindAddress}:${terminalPort}:7681",
    "--env-file", $envFile,
    "--env", "YOLO_FLAVOR=$flavor",
    "--workdir", "/workspace",
    $Image, "/opt/yolo/server-start.sh"
)
& docker @dockerArgs | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "yolo-agent ($Container) server running:"
Write-Host "  VS Code:  http://${bindAddress}:${codePort}"
Write-Host "  Terminal: http://${bindAddress}:${terminalPort}"
Write-Host "  Logs:     docker logs -f $name"
Write-Host "  Stop:     docker rm -f $name"
