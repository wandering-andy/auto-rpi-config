# Safe reset and publish repository (PowerShell)

$ErrorActionPreference = 'Stop'

# --- Config ---
$repoName = 'auto-rpi-config'
$ghPublic = $true   # $false => create private
$description = 'Automated Raspberry Pi configuration system'
# ----------------

# Helpers
function Write-Info($m){ Write-Host $m -ForegroundColor Cyan }
function Write-Warn($m){ Write-Host $m -ForegroundColor Yellow }
function Write-Err($m){ Write-Host $m -ForegroundColor Red }

# 1) Backup existing .git if present
if (Test-Path -Path '.git') {
    $ts = (Get-Date -Format 'yyyyMMddHHmmss')
    $backupName = "..\git-backup-$ts"
    Write-Info "Backing up .git -> $backupName"
    Move-Item -Path '.git' -Destination $backupName
} else {
    Write-Info ".git not found; skipping backup"
}

# 2) Reinitialize git on main
Write-Info "Initializing new git repository (branch: main)"
git init -b main

# 3) Ensure no stale remote
try { git remote remove origin 2>$null } catch {}

# 4) Ensure .gitignore present (optional user check)
if (-not (Test-Path -Path '.gitignore')) {
    Write-Warn ".gitignore not found in repo root. Consider adding one to avoid committing secrets."
}

# 5) Stage all files
Write-Info "Staging files..."
git add -A

# 6) Commit if there are staged changes
$hasChanges = (& git status --porcelain) -ne ''
if ($hasChanges) {
    $commitMsg = "Initial release: auto-rpi-config`n`nSimple, idempotent framework to configure Raspberry Pi OS Lite for homelab use."
    Write-Info "Committing changes..."
    git commit -m $commitMsg
} else {
    Write-Info "No changes to commit."
}

# 7) Create GitHub repo and push using gh
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Err "gh CLI not found. Install and authenticate with 'gh auth login' before running this script."
    exit 1
}

# Prepare gh args
$ghArgs = @('repo','create',$repoName,'--source=.', '--remote=origin','--push')
if ($ghPublic) { $ghArgs += '--public' } else { $ghArgs += '--private' }
$ghArgs += @('--description',$description)

Write-Info "Creating GitHub repository and pushing..."
# gh may error if repo already exists; allow it to fail and fallback to force push
try {
    & gh @ghArgs
} catch {
    Write-Warn "gh repo create failed (maybe repo exists). Attempting to push to origin..."
    try {
        git push -u origin main --force
    } catch {
        Write-Err "Failed to push to origin: $_"
        exit 1
    }
}

# 8) Verify and open repo in browser
Write-Info "Opening repo in browser (if available)..."
try { & gh repo view --web } catch { Write-Warn "gh repo view failed or not available" }

Write-Info "Done."
