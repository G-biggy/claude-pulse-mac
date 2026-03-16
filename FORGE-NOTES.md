# Forge Notes — Claude Pulse v1.0

**Tested:** 2026-03-17 01:30 UTC+3
**Status:** Script runs cleanly, produces valid SwiftBar output with real API data

## What Worked As-Is
- Keychain credential extraction — flawless
- API call with `anthropic-beta: oauth-2025-04-20` header — returns real data
- Token has `user:profile` scope (no re-auth needed)
- Cache logic (60s TTL, stale fallback)
- Color thresholds, time remaining calculations
- python3 ISO 8601 parsing
- install.sh and uninstall.sh look correct (not tested — need SwiftBar GUI)

## What I Had to Fix
Three issues, all bash printf-related:

1. **Unicode escapes (`\u2588`, `\u25c9`, etc.)** — bash's printf doesn't interpret `\uXXXX`. Replaced all escape sequences with actual UTF-8 characters (█, ░, ◉, ·, —, ⚠).

2. **printf format injection** — `printf "$MENU_TEXT | ..."` where `MENU_TEXT` contained `10%` — the `%` was interpreted as a format specifier. Fixed by using `printf '%s | ...'` with `$MENU_TEXT` as an argument.

3. **printf `---` as option flag** — `printf "---\n"` fails because `---` starts with `--`, which printf interprets as an option. Fixed with `printf '%s\n' "---"`.

## API Response (FYI)
The API returns more fields than the spec anticipated:
```json
{
  "five_hour": { "utilization": 10.0, "resets_at": "..." },
  "seven_day": { "utilization": 20.0, "resets_at": "..." },
  "seven_day_oauth_apps": null,
  "seven_day_opus": null,
  "seven_day_sonnet": { "utilization": 5.0, "resets_at": "..." },
  "seven_day_cowork": null,
  "extra_usage": { "is_enabled": true, "monthly_limit": 5000, "used_credits": 0.0 }
}
```
Future idea: show per-model breakdown and extra usage credits in dropdown.

## Gotchas for G
- SwiftBar must be running for the plugin to work. `install.sh` handles launching it.
- First SwiftBar launch will ask for a plugins directory — the installer sets it to `~/Library/Application Support/SwiftBar/plugins/`.
- macOS may prompt for Keychain access the first time the script runs via SwiftBar.
- If you see "Token expired" in the menu bar, run `claude login` in terminal.
