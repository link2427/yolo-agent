[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Image = $(if ($env:YOLO_IMAGE) { $env:YOLO_IMAGE } else { "yolo-agent:1.2.2" }),
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Command = @()
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$envFile = if ($env:YOLO_ENV_FILE) { $env:YOLO_ENV_FILE } else { Join-Path $repoRoot "config\yolo.env" }
$seccomp = Join-Path $repoRoot "config\seccomp-yolo.json"
$homeVolume = if ($env:YOLO_HOME_VOLUME) { $env:YOLO_HOME_VOLUME } else { "yolo-agent-home-v1" }
$memory = if ($env:YOLO_MEM) { $env:YOLO_MEM } else { "8g" }
$cpus = if ($env:YOLO_CPUS) { $env:YOLO_CPUS } else { "4" }
$workspace = (Get-Location).Path

if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
    throw "$envFile missing; copy config\yolo.env.example to config\yolo.env"
}

$dockerArgs = @(
    "run", "-it", "--rm", "--name", "yolo-agent",
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
    "--workdir", "/workspace",
    $Image
)
$dockerArgs += $Command
& docker @dockerArgs
exit $LASTEXITCODE
