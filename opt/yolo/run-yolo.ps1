# run-yolo.ps1 — yolo-dev launcher for Windows Docker Desktop
# -------------------------------------------------------------
# Same lockdown as run-yolo.sh: non-root user, read-only rootfs, all caps
# dropped, strict seccomp, resource limits. Secrets only via yolo.env.
#
# Usage (from the folder you want the agent to work in):
#   .\run-yolo.ps1                 # interactive shell as uid 10001
#   .\run-yolo.ps1 opencode        # run one command
#
# First time:  docker load --input yolo-dev_5.0.docker.tar
# Then copy yolo.env.example -> yolo.env and edit (VLLM_BASE_URL/VLLM_MODEL).

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

# Workspace folder: use $Workspace if set, otherwise the launch directory.
if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = (Get-Location).Path
}
if (-not (Test-Path -PathType Container $Workspace)) {
    Write-Error "Workspace folder not found: $Workspace — set `$Workspace at the top of run-yolo.ps1 to your project path."
    exit 1
}
$ws = (Resolve-Path $Workspace).Path

# NOTE (Docker Desktop): files in a Windows bind mount appear root-owned to
# the container; uid 10001 may not be able to write them. If agents complain
# about read-only /workspace, grant the folder write to "Users"/"Everyone"
# in Windows sharing settings, or work inside /home/agent instead.

docker run -it --rm --name yolo `
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
    --pids-limit 512 `
    --ulimit nofile=2048:2048 `
    --ulimit nproc=2048:2048 `
    --stop-timeout 30 `
    --env-file "$envFile" `
    --workdir /workspace `
    $Image @args
