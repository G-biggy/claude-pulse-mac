#!/bin/bash
echo ""
echo "  Removing Claude Pulse..."
echo ""

SWIFTBAR_PLUGIN_DIR=$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || echo "$HOME/Library/Application Support/SwiftBar/plugins")
rm -f "$SWIFTBAR_PLUGIN_DIR/claude-pulse.5m.sh"
rm -f /tmp/claude-pulse-cache.json

echo "  \u2705 Claude Pulse removed."
echo "  SwiftBar itself was NOT uninstalled."
echo "  To remove SwiftBar: brew uninstall --cask swiftbar"
echo ""
