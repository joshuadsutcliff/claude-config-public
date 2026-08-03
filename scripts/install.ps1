# One-click installer: Obsidian + Claude Code beginner setup (Windows PowerShell)
# Safe to re-run. No admin elevation required. ASCII-only output.

function Say($msg) {
    Write-Host ""
    Write-Host "==> $msg"
}

function Warn($msg) {
    Write-Host ""
    Write-Host "!! $msg"
}

function Ask($prompt, $default) {
    $reply = Read-Host "$prompt [$default]"
    if ([string]::IsNullOrWhiteSpace($reply)) {
        return $default
    }
    return $reply
}

Say "Starting Obsidian + Claude Code setup for Windows."

# --- 1. Obsidian ---
Say "Checking for Obsidian..."
$obsidianInstalled = $false
$obsidianPaths = @(
    "$env:LOCALAPPDATA\Obsidian\Obsidian.exe",
    "$env:PROGRAMFILES\Obsidian\Obsidian.exe"
)
foreach ($p in $obsidianPaths) {
    if (Test-Path $p) { $obsidianInstalled = $true }
}
if (Get-Command obsidian -ErrorAction SilentlyContinue) { $obsidianInstalled = $true }

if ($obsidianInstalled) {
    Say "Obsidian already installed. Skipping."
} else {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Say "Installing Obsidian via winget..."
        try {
            winget install --id Obsidian.Obsidian -e --accept-source-agreements --accept-package-agreements
        } catch {
            Warn "winget install failed. Download manually: https://obsidian.md/download"
        }
    } else {
        Warn "winget not found. Download Obsidian manually: https://obsidian.md/download"
    }
}

# --- 2. Claude Code ---
Say "Checking for Claude Code CLI..."
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Say "Claude Code already installed. Skipping."
} else {
    Say "Installing Claude Code (irm https://claude.ai/install.ps1 | iex)..."
    try {
        irm https://claude.ai/install.ps1 | iex
    } catch {
        Warn "Claude Code install script failed."
    }
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Warn "claude is still not on PATH. Open a NEW PowerShell window and try again."
        Warn "If it still is not found, reinstall from https://claude.ai/install.ps1 in a fresh terminal."
    }
}

# --- 3. vault folder ---
# Matches the guide's suggested path; deliberately avoids Documents, which is
# often OneDrive-redirected.
$DefaultVault = Join-Path $env:USERPROFILE "Vaults\MyVault"

# Warn if Documents is OneDrive-redirected
try {
    $docsPath = [Environment]::GetFolderPath("MyDocuments")
    if ($docsPath -like "*OneDrive*") {
        Warn "Your Documents folder appears to be redirected into OneDrive ($docsPath)."
        Warn "OneDrive sync can conflict with Obsidian. Consider a local, non-synced folder instead."
    }
} catch {
    # non-fatal, continue
}

Say "Choosing your Obsidian vault folder."
$VaultPath = Ask "Vault folder path" $DefaultVault

if ($VaultPath -like "*OneDrive*" -or $VaultPath -like "*Dropbox*") {
    Warn "That path looks like it is inside a cloud-synced folder (OneDrive/Dropbox)."
    Warn "Cloud sync + Obsidian's own sync/git can conflict. Consider a plain local folder instead."
}

if (Test-Path $VaultPath) {
    Say "Vault folder already exists: $VaultPath. Skipping creation."
} else {
    Say "Creating vault folder: $VaultPath"
    try {
        New-Item -ItemType Directory -Path $VaultPath -Force | Out-Null
    } catch {
        Warn "Could not create $VaultPath. Create it manually."
    }
}

# --- 4. starter CLAUDE.md ---
$ClaudeMd = Join-Path $VaultPath "CLAUDE.md"
if (Test-Path $ClaudeMd) {
    Say "CLAUDE.md already exists at $ClaudeMd. Leaving it alone."
} else {
    Say "Writing starter CLAUDE.md to $ClaudeMd"
    $starter = @'
# My Vault: Claude Code Instructions

## What this vault is
Personal knowledge vault in Obsidian. Every note is a plain Markdown file.
You (Claude) run from the vault root and may read, create, and edit notes.

## Ground rules
1. Dates are always YYYY-MM-DD.
2. Never delete a note unless I explicitly ask. Prefer moving it to `Archive/`.
3. Do not touch the `.obsidian/` folder (app settings) unless I ask.
4. Every new note gets YAML frontmatter: `type`, `date`, and 2-4 `tags`.
5. Quick captures go to `+Inbox/`; file them properly when I ask you to organize.
6. When you answer a question from my notes, cite the notes you used with
   [[wikilinks]] so I can jump to them in Obsidian.

## Folder map (edit to match your vault)
- `+Inbox/` : unsorted quick captures
- `Notes/` : evergreen reference notes
- `Projects/` : one folder per active project
- `Daily/` : daily notes, named YYYY-MM-DD.md
- `Archive/` : retired notes (instead of deletion)

## How to work with me
- Search before answering; say so when you can't find something.
- Propose a plan before any reorganization that moves more than a few files.
- Keep responses short and practical; I'm reading in a terminal.
'@
    Set-Content -Path $ClaudeMd -Value $starter -Encoding UTF8
}

# --- 5. next steps ---
Say "Setup complete."
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Open Obsidian and choose 'Open folder as vault' -> select:"
Write-Host "       $VaultPath"
Write-Host "  2. Open a terminal in that same folder and run:"
Write-Host "       cd `"$VaultPath`"; claude"
Write-Host "  3. If Claude Code was just installed, open a NEW PowerShell window first"
Write-Host "     so your PATH picks it up."
Write-Host ""
