#!/usr/bin/env bash
# One-click installer: Obsidian + Claude Code beginner setup (macOS + Linux)
# Safe to re-run. No sudo. Each step handles its own failures and continues.
set -u

say() { printf '\n==> %s\n' "$1"; }
warn() { printf '\n!! %s\n' "$1"; }

# --- read input from the real terminal even when piped via curl | bash ---
ask() {
  # ask "prompt" "default" -> echoes the answer
  prompt="$1"
  default="$2"
  if [ -r /dev/tty ]; then
    printf '%s [%s]: ' "$prompt" "$default" > /dev/tty
    read -r reply < /dev/tty || reply=""
    if [ -z "$reply" ]; then
      echo "$default"
    else
      echo "$reply"
    fi
  else
    warn "No interactive terminal detected; using default: $default"
    echo "$default"
  fi
}

# --- 1. detect OS ---
OS="unknown"
case "$(uname -s)" in
  Darwin) OS="macos" ;;
  Linux) OS="linux" ;;
  *) warn "Unrecognized OS ($(uname -s)); proceeding with Linux-style steps." ; OS="linux" ;;
esac
say "Detected OS: $OS"

# --- 2. Obsidian ---
say "Checking for Obsidian..."
if [ -d "/Applications/Obsidian.app" ] || command -v obsidian >/dev/null 2>&1 || \
   [ -d "$HOME/.local/share/flatpak/app/md.obsidian.Obsidian" ] || \
   [ -d "/var/lib/flatpak/app/md.obsidian.Obsidian" ]; then
  say "Obsidian already installed. Skipping."
elif [ "$OS" = "macos" ]; then
  if command -v brew >/dev/null 2>&1; then
    say "Installing Obsidian via Homebrew (brew install --cask obsidian)..."
    brew install --cask obsidian || warn "Homebrew install failed. Download manually: https://obsidian.md/download"
  else
    warn "Homebrew not found. Download Obsidian manually: https://obsidian.md/download"
  fi
else
  if command -v flatpak >/dev/null 2>&1; then
    say "Installing Obsidian via Flatpak (flathub md.obsidian.Obsidian)..."
    flatpak install --user -y flathub md.obsidian.Obsidian || warn "Flatpak install failed. AppImage instructions: https://obsidian.md/download"
  else
    warn "Flatpak not found. Get the AppImage instead: https://obsidian.md/download"
  fi
fi

# --- 3. Claude Code ---
say "Checking for Claude Code CLI..."
if command -v claude >/dev/null 2>&1; then
  say "Claude Code already installed. Skipping."
else
  say "Installing Claude Code (curl -fsSL https://claude.ai/install.sh | bash)..."
  curl -fsSL https://claude.ai/install.sh | bash || warn "Claude Code install script failed."
  if ! command -v claude >/dev/null 2>&1; then
    warn "claude still not on PATH. Applying a PATH fix to your shell rc file."
    case "${SHELL:-}" in
      */zsh) RC="$HOME/.zshrc" ;;
      */bash) RC="$HOME/.bashrc" ;;
      *) RC="$HOME/.profile" ;;
    esac
    PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
    if [ -f "$RC" ] && grep -qF "$PATH_LINE" "$RC" 2>/dev/null; then
      say "PATH fix already present in $RC."
    else
      printf '\n# Added by claude-config-public installer\n%s\n' "$PATH_LINE" >> "$RC"
      say "Added PATH fix to $RC. Open a new terminal window for it to take effect."
    fi
  fi
fi

# --- 4. vault folder ---
# Matches the guide's suggested path; deliberately avoids ~/Documents, which
# iCloud "Desktop & Documents" sync silently cloud-syncs on macOS.
DEFAULT_VAULT="$HOME/Vaults/MyVault"

say "Choosing your Obsidian vault folder."
VAULT_PATH="$(ask "Vault folder path" "$DEFAULT_VAULT")"

case "$VAULT_PATH" in
  *iCloud*|*"Library/Mobile Documents"*|*OneDrive*|*Dropbox*)
    warn "That path looks like it's inside a cloud-synced folder (iCloud/OneDrive/Dropbox)."
    warn "Cloud sync + Obsidian's own sync/git can conflict. Consider a plain local folder instead."
    ;;
esac

if [ -d "$VAULT_PATH" ]; then
  say "Vault folder already exists: $VAULT_PATH. Skipping creation."
else
  say "Creating vault folder: $VAULT_PATH"
  mkdir -p "$VAULT_PATH" || warn "Could not create $VAULT_PATH. Create it manually."
fi

# --- 5. starter CLAUDE.md ---
CLAUDE_MD="$VAULT_PATH/CLAUDE.md"
if [ -f "$CLAUDE_MD" ]; then
  say "CLAUDE.md already exists at $CLAUDE_MD. Leaving it alone."
else
  say "Writing starter CLAUDE.md to $CLAUDE_MD"
  cat > "$CLAUDE_MD" <<'EOF'
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
EOF
fi

# --- 6. next steps ---
say "Setup complete."
cat <<EOF

Next steps:
  1. Open Obsidian and choose "Open folder as vault" -> select:
       $VAULT_PATH
  2. Open a terminal in that same folder and run:
       cd "$VAULT_PATH" && claude
  3. If Claude Code was just installed, open a NEW terminal window first
     so your PATH picks it up.

EOF
