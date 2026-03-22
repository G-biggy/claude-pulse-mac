#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "  \U0001FAC0 Claude Pulse \u2014 Menu Bar Usage Monitor"
echo "  \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"
echo ""

# \u2500\u2500\u2500 1. Check/install jq \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

if command -v jq &>/dev/null; then
    echo "  \u2705 jq found"
else
    echo "  \U0001F4E6 Installing jq..."
    brew install jq
    echo "  \u2705 jq installed"
fi

# \u2500\u2500\u2500 2. Check/install SwiftBar \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

if [ -d "/Applications/SwiftBar.app" ]; then
    echo "  \u2705 SwiftBar found"
else
    echo "  \U0001F4E6 Installing SwiftBar..."
    brew install --cask swiftbar
    echo "  \u2705 SwiftBar installed"
fi

# \u2500\u2500\u2500 3. Configure SwiftBar plugins directory \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

SWIFTBAR_PLUGIN_DIR=$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || echo "")

if [ -z "$SWIFTBAR_PLUGIN_DIR" ]; then
    SWIFTBAR_PLUGIN_DIR="$HOME/Library/Application Support/SwiftBar/plugins"
    mkdir -p "$SWIFTBAR_PLUGIN_DIR"
    defaults write com.ameba.SwiftBar PluginDirectory "$SWIFTBAR_PLUGIN_DIR"
    echo "  \U0001F4C1 Plugin directory set: $SWIFTBAR_PLUGIN_DIR"
else
    echo "  \u2705 Plugin directory: $SWIFTBAR_PLUGIN_DIR"
fi

# \u2500\u2500\u2500 4. Install plugin \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

chmod +x "$SCRIPT_DIR/claude-pulse.5m.sh"
ln -sf "$SCRIPT_DIR/claude-pulse.5m.sh" "$SWIFTBAR_PLUGIN_DIR/claude-pulse.5m.sh"
echo "  \u2705 Plugin linked"

# \u2500\u2500\u2500 5. Verify Claude Code credentials \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

if security find-generic-password -s "Claude Code-credentials" &>/dev/null; then
    SUB_TYPE=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.subscriptionType // "unknown"' 2>/dev/null)
    echo "  \u2705 Claude Code credentials found (plan: $SUB_TYPE)"

    # Check for user:profile scope
    HAS_PROFILE=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.scopes | if . then (. | index("user:profile") // -1) else -1 end' 2>/dev/null)
    if [ "$HAS_PROFILE" = "-1" ] || [ "$HAS_PROFILE" = "null" ]; then
        echo ""
        echo "  \u26a0\ufe0f  Token may be missing 'user:profile' scope."
        echo "     If the plugin shows errors, run:"
        echo "       security delete-generic-password -s 'Claude Code-credentials'"
        echo "       Then restart Claude Code to get a fresh token."
    fi
elif [ -f "$HOME/.claude/.credentials.json" ]; then
    echo "  \u2705 Claude Code credentials found (file)"
else
    echo ""
    echo "  \u26a0\ufe0f  No Claude Code credentials found."
    echo "     Run 'claude' in terminal and log in first."
    echo "     Then re-run this installer."
fi

# \u2500\u2500\u2500 6. Launch SwiftBar \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

if pgrep -x "SwiftBar" > /dev/null; then
    echo "  \u2705 SwiftBar is running"
    # Trigger a refresh by touching the plugin file
    touch "$SWIFTBAR_PLUGIN_DIR/claude-pulse.5m.sh"
else
    echo "  \U0001F680 Launching SwiftBar..."
    open -a SwiftBar
    sleep 3
fi

# \u2500\u2500\u2500 Done \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

echo ""
echo "  \u2705 Claude Pulse installed!"
echo ""
echo "  Look for \u25c9 in your menu bar (might take a few seconds)."
echo "  Click it to see your 5-hour and weekly usage."
echo ""
echo "  Refreshes automatically every 5 minutes."
echo "  Click 'Refresh Now' in the dropdown for instant update."
echo ""
