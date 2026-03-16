# Claude Pulse

A macOS menu bar widget that shows your Claude subscription usage at a glance.

Click the menu bar icon to see your 5-hour window and weekly usage percentages, color-coded progress bars, and countdown timers to reset.

## What It Shows

- **5-Hour Window** — Your rolling 5-hour usage percentage with time until reset
- **Weekly (7-Day)** — Your rolling weekly usage percentage with time until reset
- **Color coding** — Green (<50%), Yellow (50-74%), Orange (75-89%), Red (90%+)
- **Plan info** — Your subscription tier

## Requirements

- macOS 14 (Sonoma) or later
- [Homebrew](https://brew.sh)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) logged in (provides the OAuth token)
- `jq` (installed automatically)
- [SwiftBar](https://github.com/swiftbar/SwiftBar) (installed automatically)

## Install

```bash
cd ~/VS-workspace/claude-pulse
chmod +x install.sh
./install.sh
```

That's it. Look for ◉ in your menu bar.

## How It Works

1. Reads your Claude Code OAuth token from macOS Keychain
2. Calls Anthropic's usage API (`/api/oauth/usage`)
3. Caches the response for 60 seconds
4. Formats the data as a SwiftBar menu bar plugin
5. Auto-refreshes every 5 minutes

No tokens are stored outside of macOS Keychain. No data is sent anywhere except Anthropic's API.

## Uninstall

```bash
./uninstall.sh
```

## Troubleshooting

**◉ shows a warning icon:**
- Make sure Claude Code is installed and you're logged in (`claude login`)
- Check that your Keychain has the `Claude Code-credentials` entry

**Token scope error:**
```bash
security delete-generic-password -s "Claude Code-credentials"
# Quit all Claude Code instances, then restart Claude Code
```

**Not refreshing:**
- Click the ◉ icon and select "Refresh Now"
- Check SwiftBar is running (look for its icon in menu bar)

## Built By

G + Sage + Forge — the Claude Mind system.
