#!/bin/bash

# Define paths
NEW_CONFIG="$HOME/.config/nushell"
OLD_CONFIG="$HOME/Library/Application Support/nushell"

# 1. Create the new target directory if it doesn't exist
mkdir -p "$NEW_CONFIG"

# 2. Check if the link is already set up
if [ -L "$OLD_CONFIG" ]; then
    echo "✅ Success: Link already exists. Nothing to do."
    exit 0
fi

# 3. If a real directory exists at the old path, move its contents
if [ -d "$OLD_CONFIG" ]; then
    echo "📂 Moving existing config files to $NEW_CONFIG..."
    cp -rn "$OLD_CONFIG/"* "$NEW_CONFIG/" # -n prevents overwriting newer files
    rm -rf "$OLD_CONFIG"
fi

# 4. Create the symbolic link
ln -s "$NEW_CONFIG" "$OLD_CONFIG"
echo "✨ Nushell is now linked to ~/.config/nushell"
