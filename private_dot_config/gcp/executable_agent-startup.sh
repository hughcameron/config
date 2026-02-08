#!/bin/bash
# GCP Agent VM Startup Script
# Used as --metadata-from-file=startup-script for agent VMs
#
# After VM creation, deploy secrets:
#   gcloud compute instances add-metadata <INSTANCE> \
#     --project=<PROJECT> --zone=<ZONE> \
#     --metadata-from-file=age-key=$HOME/.config/chezmoi/age/keys.txt
#
#   gcloud compute ssh <INSTANCE> --project=<PROJECT> --zone=<ZONE> -- \
#     'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && chezmoi init --apply https://github.com/hughcameron/config.git'

set -e

USERNAME="hugh"
BREW="/home/linuxbrew/.linuxbrew/bin/brew"

echo "=== GCP Agent VM Startup ==="

# Create user
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -s /usr/bin/zsh "$USERNAME"
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME
    chmod 440 /etc/sudoers.d/$USERNAME
    echo "Created user $USERNAME"
fi

# System packages
apt-get update
apt-get install -y \
    zsh git curl wget unzip build-essential \
    nodejs npm age \
    file ffmpeg p7zip-full poppler-utils imagemagick xclip

# Homebrew
if [ ! -f "$BREW" ]; then
    su - $USERNAME -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    su - $USERNAME -c 'echo "eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\"" >> ~/.profile'
    echo "Homebrew installed"
fi

# Chezmoi
su - $USERNAME -c "eval \"\$($BREW shellenv)\" && brew install chezmoi" || true

# Age key from instance metadata
AGE_DIR="/home/$USERNAME/.config/chezmoi/age"
su - $USERNAME -c "mkdir -p $AGE_DIR"
AGE_KEY=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/attributes/age-key" \
    -H "Metadata-Flavor: Google" 2>/dev/null || true)
if [ -n "$AGE_KEY" ]; then
    echo "$AGE_KEY" > "$AGE_DIR/keys.txt"
    chown $USERNAME:$USERNAME "$AGE_DIR/keys.txt"
    chmod 600 "$AGE_DIR/keys.txt"
    echo "Age key deployed from metadata"

    # If age key is present, run chezmoi init
    su - $USERNAME -c "eval \"\$($BREW shellenv)\" && chezmoi init --apply https://github.com/hughcameron/config.git" || echo "chezmoi init failed — may need GitHub SSH key"
else
    echo "No age key in metadata — deploy manually after boot"
fi

# Claude Code (global npm)
npm install -g @anthropic-ai/claude-code || true

# MCP SDK (if chezmoi deployed the mcp-servers dir)
if [ -d "/home/$USERNAME/.claude/mcp-servers" ]; then
    su - $USERNAME -c "eval \"\$($BREW shellenv)\" && cd ~/.claude/mcp-servers && npm init -y 2>/dev/null && npm install @modelcontextprotocol/sdk" || true
fi

# Brew bundle (if chezmoi deployed the Brewfile)
BREWFILE="/home/$USERNAME/.config/homebrew/brewfile.txt"
if [ -f "$BREWFILE" ]; then
    su - $USERNAME -c "eval \"\$($BREW shellenv)\" && brew bundle install --file $BREWFILE" || true
fi

# Yazi plugins
su - $USERNAME -c "eval \"\$($BREW shellenv)\" && ya pkg install" 2>/dev/null || true

# Create repo directory
su - $USERNAME -c 'mkdir -p ~/github'

echo "=== GCP Agent VM startup complete ==="
