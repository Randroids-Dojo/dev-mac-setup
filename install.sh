#!/bin/bash

# Hammerspoon Workspace Manager Installation Script
# Usage: ./install.sh

set -e

echo "🔧 Installing Hammerspoon Workspace Manager..."

# Check if Hammerspoon is installed
if ! command -v hs &> /dev/null; then
    echo "❌ Hammerspoon not found. Please install from: https://www.hammerspoon.org/"
    echo "   After installation, run this script again."
    exit 1
fi

# Create Hammerspoon config directory
HAMMERSPOON_DIR="$HOME/.hammerspoon"
mkdir -p "$HAMMERSPOON_DIR"

# Backup existing config if it exists
if [ -f "$HAMMERSPOON_DIR/init.lua" ]; then
    echo "📦 Backing up existing init.lua to init.lua.backup"
    cp "$HAMMERSPOON_DIR/init.lua" "$HAMMERSPOON_DIR/init.lua.backup"
fi

# Copy configuration files from current directory
echo "📁 Installing configuration files..."
cp init.lua "$HAMMERSPOON_DIR/"
cp simple-workspaces.lua "$HAMMERSPOON_DIR/"

# Set proper permissions
chmod 644 "$HAMMERSPOON_DIR/init.lua"
chmod 644 "$HAMMERSPOON_DIR/simple-workspaces.lua"

# Optional: Copy example workspaces
if [ -f "example-workspaces.json" ]; then
    echo ""
    echo "📋 Found example workspaces. Would you like to install them? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        if [ -f "$HAMMERSPOON_DIR/simple-workspaces.json" ]; then
            echo "📦 Backing up existing workspaces to simple-workspaces.json.backup"
            cp "$HAMMERSPOON_DIR/simple-workspaces.json" "$HAMMERSPOON_DIR/simple-workspaces.json.backup"
        fi
        cp example-workspaces.json "$HAMMERSPOON_DIR/simple-workspaces.json"
        chmod 644 "$HAMMERSPOON_DIR/simple-workspaces.json"
        echo "✅ Example workspaces installed!"
    else
        echo "⏭️  Skipping example workspaces installation"
    fi
fi

echo "✅ Installation complete!"
echo ""
echo "🚀 Next steps:"
echo "1. Grant Hammerspoon accessibility permissions in System Preferences"
echo "2. Reload Hammerspoon configuration (⌘⌥⌃+R)"
echo "3. Open workspace manager with ⌘⌥⌃+W"
echo ""
echo "📚 Keyboard shortcuts:"
echo "   ⌘⌥⌃+W  - Open workspace manager"
echo "   ⌘⌥⌃+S  - Save current desktop as workspace"
echo "   ⌘⌥⌃+R  - Reload Hammerspoon"
echo "   ⌘⌥⌃+/  - Show help"