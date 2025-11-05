#!/usr/bin/env bash
set -euo pipefail

# SwiftBar VPN plugin installer
# Usage: bash SwiftBar/install-swiftbar-plugin.sh

# --- Compute paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"        # .../SwiftBar
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"                      # repo root
PLUGIN_SRC="$PROJECT_ROOT/SwiftBar/plugin/vpn-proxy.30s.sh"          # plugin file in repo
CONFIG_DIR="$HOME/.config/swiftbar-vpn"
CONFIG_FILE="$CONFIG_DIR/config"
PLUGINS_DIR="$HOME/Library/Application Support/SwiftBar/plugins"
PLUGIN_DST="$PLUGINS_DIR/$(basename "$PLUGIN_SRC")"
SWIFTBAR_APP_1="/Applications/SwiftBar.app"
SWIFTBAR_APP_2="$HOME/Applications/SwiftBar.app"

echo "== SwiftBar VPN plugin installer =="

# --- Sanity checks ---
if [ ! -f "$PROJECT_ROOT/docker-compose.yml" ]; then
  echo "Error: $PROJECT_ROOT/docker-compose.yml not found."
  echo "Run this script from a repo where docker-compose.yml is at the project root."
  exit 1
fi

if [ ! -f "$PLUGIN_SRC" ]; then
  echo "Error: plugin file not found: $PLUGIN_SRC"
  exit 1
fi

# --- Create user config (if missing) and set COMPOSE_DIR ---
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" <<EOF
# SwiftBar VPN plugin config
# Absolute path to your project root (where docker-compose.yml resides):
COMPOSE_DIR="$PROJECT_ROOT"
EOF
  echo "Created config: $CONFIG_FILE"
else
  echo "Config already exists: $CONFIG_FILE"
  if ! grep -q '^COMPOSE_DIR=' "$CONFIG_FILE"; then
    echo "COMPOSE_DIR=\"$PROJECT_ROOT\"" >> "$CONFIG_FILE"
    echo "Added COMPOSE_DIR to $CONFIG_FILE"
  fi
fi

# --- Check SwiftBar installation ---
if [ ! -d "$SWIFTBAR_APP_1" ] && [ ! -d "$SWIFTBAR_APP_2" ]; then
  echo
  echo "SwiftBar is not installed."
  echo "Install it and re-run this script:"
  echo "  brew install --cask swiftbar"
  exit 1
fi

# --- Link plugin into SwiftBar's plugins directory ---
mkdir -p "$PLUGINS_DIR"
chmod +x "$PLUGIN_SRC"

if [ -L "$PLUGIN_DST" ] || [ -f "$PLUGIN_DST" ]; then
  echo "Updating existing plugin at: $PLUGIN_DST"
  rm -f "$PLUGIN_DST"
fi

ln -s "$PLUGIN_SRC" "$PLUGIN_DST"
echo "Symlink created: $PLUGIN_DST → $PLUGIN_SRC"

echo
echo "Done!"
echo "Open SwiftBar (or restart it), then use 'Refresh All' in the SwiftBar menu."
echo "The plugin reads COMPOSE_DIR from $CONFIG_FILE"

