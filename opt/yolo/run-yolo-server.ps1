# run-yolo-server.ps1 — yolo-dev SERVER launcher for Windows Docker Desktop
# ---------------------------------------------------------------------------
# Detached container with the browser UIs:
#   code-server (VS Code) : http://localhost:8080
#   ttyd+tmux (terminal)  : http://localhost:7681
# Same lockdown as run-yolo.ps1: non-root, read-only rootfs, cap-drop,
# strict seccomp, resource limits. Secrets only via yolo.env.
#
# Usage:
#   .\run-yolo-server.ps1          # start (idempotent: replaces yolo-server)
#   docker logs -f yolo-server     # watch logs
#   docker stop yolo-server        # stop
#
# First time:  docker load --input yolo-dev_5.0.docker.tar
# Then copy yolo.env.example -> yolo.env and edit.

param([string]$Image = "yolo-dev:6.0")

# ===== CONFIG ===============================================================
# The Windows folder to mount as /workspace (where the agents work).
# Set this to your project path, e.g.:
#     $Workspace = "C:\Users\you\projects\myapp"
# Leave it empty ("") to use the folder you launch the script from.
$Workspace = ""
# ============================================================================

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path $here "yolo.env"

if (-not (Test-Path $envFile)) {
    Write-Error "yolo.env missing — copy yolo.env.example to yolo.env and edit (VLLM_BASE_URL / VLLM_MODEL)."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = (Get-Location).Path
}
if (-not (Test-Path -PathType Container $Workspace)) {
    Write-Error "Workspace folder not found: $Workspace — set `$Workspace at the top of run-yolo-server.ps1."
    exit 1
}
$ws = (Resolve-Path $Workspace).Path

docker rm -f yolo-server 2>$null

docker run -d --name yolo-server --restart unless-stopped `
    --user 10001:10001 `
    --read-only `
    --tmpfs /tmp:rw,nosuid,size=2g `
    --tmpfs /run:rw,noexec,nosuid,size=64m `
    --tmpfs /dev/shm:rw,noexec,nosuid,size=256m `
    -v "yolo-home-v6:/home/agent" `
    -v "${ws}:/workspace" `
    --cap-drop ALL `
    --security-opt no-new-privileges `
    --security-opt seccomp="$here\seccomp-yolo.json" `
    --memory 8g `
    --cpus 4 `
    --pids-limit 2048 `
    --ulimit nofile=2048:2048 `
    --ulimit nproc=2048:2048 `
    --stop-timeout 30 `
    -p 0.0.0.0:8080:8080 `
    -p 0.0.0.0:7681:7681 `
    --env-file "$envFile" `
    --workdir /workspace `
    $Image /opt/yolo/server-start.sh

Write-Host ""
Write-Host "yolo-dev server running:"
Write-Host "  VS Code (code-server): http://localhost:8080"
Write-Host "  Terminal (ttyd+tmux):  http://localhost:7681"
Write-Host "  Logs:  docker logs -f yolo-server"
Write-Host "  Stop:  docker stop yolo-server"
