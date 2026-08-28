[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Image = $(if ($env:YOLO_IMAGE) { $env:YOLO_IMAGE } else { "yolo-agent:7.0.0" })
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$envFile = if ($env:YOLO_ENV_FILE) { $env:YOLO_ENV_FILE } else { Join-Path $repoRoot "config\yolo.env" }
$seccomp = Join-Path $repoRoot "config\seccomp-yolo.json"
$homeVolume = if ($env:YOLO_HOME_VOLUME) { $env:YOLO_HOME_VOLUME } else { "yolo-agent-home-v7" }
$memory = if ($env:YOLO_MEM) { $env:YOLO_MEM } else { "8g" }
$cpus = if ($env:YOLO_CPUS) { $env:YOLO_CPUS } else { "4" }
$bindAddress = if ($env:YOLO_BIND_ADDRESS) { $env:YOLO_BIND_ADDRESS } else { "127.0.0.1" }
$codePort = if ($env:YOLO_CODE_PORT) { $env:YOLO_CODE_PORT } else { "8080" }
$terminalPort = if ($env:YOLO_TERMINAL_PORT) { $env:YOLO_TERMINAL_PORT } else { "7681" }
$workspace = (Get-Location).Path

if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
    throw "$envFile missing; copy config\yolo.env.example to config\yolo.env"
}

& docker rm -f yolo-agent-server 2>$null | Out-Null
$dockerArgs = @(
    "run", "-d", "--name", "yolo-agent-server", "--restart", "unless-stopped",
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
    "--workdir", "/workspace",
    $Image, "/opt/yolo/server-start.sh"
)
& docker @dockerArgs | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "yolo-agent server running:"
Write-Host "  VS Code: http://${bindAddress}:${codePort}"
Write-Host "  Terminal: http://${bindAddress}:${terminalPort}"
Write-Host "  Logs: docker logs -f yolo-agent-server"
