# Claude Pulse · macOS

A lightweight macOS menu bar monitor for your Claude subscription usage. Pure bash — no compilation, no Xcode, no Swift.

![License: MIT](https://img.shields.io/badge/license-MIT-green)
![Platform: macOS](https://img.shields.io/badge/platform-macOS-blue)
![Shell: Bash](https://img.shields.io/badge/shell-bash-orange)

![Claude Pulse menu bar](docs/images/menu-bar.png)

## What It Shows

- **Session** — Your rolling 5-hour usage with time until reset
- **Weekly** — 7-day usage across all models with reset countdown
- **Sonnet** — 7-day Sonnet-specific usage with reset countdown
- **Color thresholds** — Brand green (<50%), yellow (50–74%), orange (75–89%), red (90%+)
- **Plan info** — Your subscription tier (Max, Pro, etc.)

Click the `◉` icon in your menu bar for the full dropdown.

## Requirements

- macOS 14 (Sonoma) or later
- [Homebrew](https://brew.sh)
- [SwiftBar](https://github.com/swiftbar/SwiftBar) — the menu bar plugin runtime
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) logged in (provides the OAuth token)
- `jq` for JSON parsing

## Install

**1. Install SwiftBar** (if you don't have it):

```bash
brew install --cask swiftbar
```

Open SwiftBar once and set your plugins directory when prompted (default: `~/Library/Application Support/SwiftBar/plugins`).

**2. Install Claude Pulse:**

```bash
git clone https://github.com/G-biggy/claude-pulse-mac.git
cd claude-pulse-mac
chmod +x install.sh
./install.sh
```

The install script will check for `jq` and SwiftBar, symlink the plugin, and verify your Claude Code credentials.

Look for `◉` in your menu bar. That's it.

## How It Works

1. Reads your Claude Code OAuth token from macOS Keychain
2. Calls Anthropic's usage API (`/api/oauth/usage`)
3. Caches the response for 60 seconds to stay respectful
4. Formats the data as a SwiftBar menu bar plugin
5. Auto-refreshes every 5 minutes
6. Auto-refreshes the OAuth token when it expires

No tokens are stored outside of macOS Keychain. No data is sent anywhere except Anthropic's API.

## Uninstall

```bash
./uninstall.sh
```

## Troubleshooting

**◉ shows a warning icon:**
- Make sure Claude Code is installed and you're logged in: `claude login`
- Check that your Keychain has the `Claude Code-credentials` entry

**Token scope error:**
```bash
security delete-generic-password -s "Claude Code-credentials"
# Quit all Claude Code instances, then restart Claude Code
```

**Not refreshing:**
- Click `◉` → **Refresh Now**
- Make sure SwiftBar is running (look for its icon in the menu bar)

## Also Available

📱 [Claude Pulse · Android](https://github.com/G-biggy/claude-pulse-android) — the same thing as a resizable home screen widget.

## Built By

G + Sage + Forge — the [Claude Mind](https://github.com/G-biggy) system.
