#!/bin/bash

# Define paths
NEW_CONFIG_DIR="$HOME/.config/ghostty"
OLD_CONFIG_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"

# 1. Create the new target directory if it doesn't exist
mkdir -p "$NEW_CONFIG_DIR"

# 2. Check if the link is already set up
if [ -L "$OLD_CONFIG_DIR" ]; then
    echo "✅ Success: Link already exists. Nothing to do."
    exit 0
fi

# 3. If a real directory exists at the old path, move its contents
if [ -d "$OLD_CONFIG_DIR" ]; then
    echo "📂 Moving existing config files to $NEW_CONFIG_DIR..."
    # The -n (no-clobber) option prevents overwriting existing files in the destination.
    # Using . ensures that hidden files are also copied
    cp -rn "$OLD_CONFIG_DIR/." "$NEW_CONFIG_DIR/"
    rm -rf "$OLD_CONFIG_DIR"
fi

# 4. Create the symbolic link
ln -s "$NEW_CONFIG_DIR" "$OLD_CONFIG_DIR"
echo "✨ Ghostty is now linked to ~/.config/ghostty"
