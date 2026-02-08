#!/bin/bash

# Hammerspoon Setup Script
# This script sets up Hammerspoon with keyboard shortcuts for app launching
# Migrated from ScriptKit

set -e  # Exit on error

# Define paths
NEW_CONFIG="$HOME/.config/hammerspoon"
OLD_CONFIG="$HOME/.hammerspoon"

echo "🔧 Setting up Hammerspoon..."

# 1. Install Hammerspoon via Homebrew if not already installed
if ! brew list --cask hammerspoon &>/dev/null; then
    echo "📦 Installing Hammerspoon via Homebrew..."
    brew install --cask hammerspoon
else
    echo "✅ Hammerspoon already installed"
fi

# 2. Create the new target directory if it doesn't exist
mkdir -p "$NEW_CONFIG"

# 3. Check if the link is already set up
if [ -L "$OLD_CONFIG" ]; then
    echo "✅ Success: Link already exists. Nothing to do."
else
    # 4. If a real directory exists at the old path, move its contents
    if [ -d "$OLD_CONFIG" ]; then
        echo "📂 Moving existing config files to $NEW_CONFIG..."
        cp -rn "$OLD_CONFIG/"* "$NEW_CONFIG/" # -n prevents overwriting newer files
        rm -rf "$OLD_CONFIG"
    fi

    # 5. Create the symbolic link
    ln -s "$NEW_CONFIG" "$OLD_CONFIG"
    echo "✨ Hammerspoon config linked: ~/.hammerspoon -> ~/.config/hammerspoon"
fi

# 6. Create init.lua if it doesn't exist
if [ ! -f "$NEW_CONFIG/init.lua" ]; then
    echo "📝 Creating init.lua configuration..."
    cat > "$NEW_CONFIG/init.lua" << 'EOF'
-- Hammerspoon Configuration
-- Migrated from ScriptKit
-- Last Updated: 2026-01-24

-- Auto-reload configuration when init.lua changes
hs.pathwatcher.new(os.getenv("HOME") .. "/.config/hammerspoon/", function(files)
    doReload = false
    for _, file in pairs(files) do
        if file:sub(-4) == ".lua" then
            doReload = true
        end
    end
    if doReload then
        hs.reload()
    end
end):start()

-- Show notification when config reloads
hs.alert.show("Config Reloaded")

-- ===================================
-- App Launcher Shortcuts
-- ===================================

local function launchApp(appName)
    return function()
        hs.application.launchOrFocus(appName)
    end
end

-- Define keyboard shortcuts for app launching
hs.hotkey.bind({"ctrl", "cmd"}, "p", launchApp("1Password"))
hs.hotkey.bind({"ctrl", "cmd"}, "c", launchApp("Claude"))
hs.hotkey.bind({"ctrl", "cmd"}, "f", launchApp("Firefox"))
hs.hotkey.bind({"ctrl", "cmd"}, "z", launchApp("Zed"))
hs.hotkey.bind({"ctrl", "cmd"}, "e", launchApp("Terminal"))
hs.hotkey.bind({"ctrl", "cmd"}, "t", launchApp("Todoist"))

-- ===================================
-- Startup Notification
-- ===================================

hs.notify.new({
    title = "Hammerspoon",
    informativeText = "Configuration loaded - 6 app shortcuts active",
    withdrawAfter = 2
}):send()
EOF
    echo "✅ Created init.lua with 6 app launcher shortcuts"
else
    echo "⏭️  init.lua already exists, skipping creation"
fi

# 7. Launch Hammerspoon
echo "🚀 Launching Hammerspoon..."
open -a Hammerspoon

echo ""
echo "✨ Setup complete!"
echo ""
echo "📋 Next steps:"
echo "   1. Grant accessibility permissions:"
echo "      System Settings > Privacy & Security > Accessibility > Add Hammerspoon"
echo "   2. Test your shortcuts:"
echo "      • ctrl+cmd+p → 1Password"
echo "      • ctrl+cmd+c → Claude"
echo "      • ctrl+cmd+f → Firefox"
echo "      • ctrl+cmd+z → Zed"
echo "      • ctrl+cmd+e → Terminal"
echo "      • ctrl+cmd+t → Todoist"
echo ""
echo "📁 Config location: ~/.config/hammerspoon/init.lua"
echo "🔗 Symlink: ~/.hammerspoon -> ~/.config/hammerspoon"
