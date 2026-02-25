#!/bin/bash

# Glow Setup Script
# Symlinks macOS Preferences/glow → ~/.config/glow so glow finds chezmoi-managed config
# Also installs glow via Homebrew if not already installed

set -e

# Define paths
NEW_CONFIG="$HOME/.config/glow"
OLD_CONFIG="$HOME/Library/Preferences/glow"

echo "🔧 Setting up Glow..."

# 1. Install glow via Homebrew if not already installed
if ! command -v glow &>/dev/null; then
    echo "📦 Installing Glow via Homebrew..."
    brew install glow
else
    echo "✅ Glow already installed"
fi

# 2. Create the new target directory if it doesn't exist
mkdir -p "$NEW_CONFIG"

# 3. Check if the link is already set up
if [ -L "$OLD_CONFIG" ]; then
    echo "✅ Success: Link already exists. Nothing to do."
    exit 0
fi

# 4. If a real directory exists at the old path, move its contents
if [ -d "$OLD_CONFIG" ]; then
    echo "📂 Moving existing config files to $NEW_CONFIG..."
    cp -rn "$OLD_CONFIG/." "$NEW_CONFIG/"
    rm -rf "$OLD_CONFIG"
fi

# 5. Create the symbolic link
ln -s "$NEW_CONFIG" "$OLD_CONFIG"
echo "✨ Glow is now linked to ~/.config/glow"
echo ""
echo "📁 Config: ~/.config/glow/glow.yml"
echo "🎨 Style:  ~/.config/glow/ayu-mirage.json"
echo "🔗 Symlink: ~/Library/Preferences/glow -> ~/.config/glow"
