#!/bin/bash
# <bitbar.title>Claude Pulse</bitbar.title>
# <bitbar.version>v1.0</bitbar.version>
# <bitbar.author>G + Sage + Forge</bitbar.author>
# <bitbar.author.github>ghayyath</bitbar.author.github>
# <bitbar.desc>Shows Claude subscription usage (5h + 7d) in menu bar</bitbar.desc>
# <bitbar.dependencies>jq</bitbar.dependencies>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>

# ─── Config ───────────────────────────────────────────────────────────
CACHE_FILE="/tmp/claude-pulse-cache.json"
CACHE_MAX_AGE=60  # seconds — don't hit API more than once per minute
API_URL="https://api.anthropic.com/api/oauth/usage"
API_BETA="oauth-2025-04-20"
KEYCHAIN_SERVICE="Claude Code-credentials"
CREDS_FILE="$HOME/.claude/.credentials.json"

# ─── Color Thresholds ────────────────────────────────────────────────
GREEN="#4CAF50"
YELLOW="#FF9800"
ORANGE="#FF5722"
RED="#F44336"
GRAY="#888888"
DIMGRAY="#666666"

# ─── Helpers ──────────────────────────────────────────────────────────

get_color() {
    local pct=$1
    if [ "$pct" -lt 50 ] 2>/dev/null; then
        echo "$GREEN"
    elif [ "$pct" -lt 75 ] 2>/dev/null; then
        echo "$YELLOW"
    elif [ "$pct" -lt 90 ] 2>/dev/null; then
        echo "$ORANGE"
    else
        echo "$RED"
    fi
}

make_bar() {
    local pct=$1
    local width=20
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar=""
    local filled_char="█"
    local empty_char="░"
    for ((i=0; i<filled; i++)); do bar+="$filled_char"; done
    for ((i=0; i<empty; i++)); do bar+="$empty_char"; done
    echo -n "$bar"
}

time_remaining() {
    local reset_ts="$1"
    if [ -z "$reset_ts" ] || [ "$reset_ts" = "null" ]; then
        echo -n "—"
        return
    fi

    # Use python3 for reliable ISO 8601 parsing
    local reset_epoch
    reset_epoch=$(python3 -c "
from datetime import datetime, timezone
try:
    ts = '$reset_ts'.replace('Z', '+00:00')
    dt = datetime.fromisoformat(ts)
    print(int(dt.timestamp()))
except:
    print(0)
" 2>/dev/null)

    if [ -z "$reset_epoch" ] || [ "$reset_epoch" = "0" ]; then
        echo "?"
        return
    fi

    local now_epoch
    now_epoch=$(date +%s)
    local diff=$(( reset_epoch - now_epoch ))

    if [ "$diff" -le 0 ]; then
        echo "now"
        return
    fi

    local days=$(( diff / 86400 ))
    local hours=$(( (diff % 86400) / 3600 ))
    local mins=$(( (diff % 3600) / 60 ))

    if [ "$days" -gt 0 ]; then
        echo "${days}d ${hours}h"
    elif [ "$hours" -gt 0 ]; then
        echo "${hours}h ${mins}m"
    else
        echo "${mins}m"
    fi
}

error_state() {
    local msg="$1"
    local detail="$2"
    echo "◉ ⚠ | size=13"
    printf '%s\n' "---"
    printf "%s | size=12 color=%s\n" "$msg" "$RED"
    if [ -n "$detail" ]; then
        printf "%s | size=11 color=%s\n" "$detail" "$GRAY"
    fi
    printf '%s\n' "---"
    printf "Refresh | refresh=true\n"
    printf "Open Usage Page | href=https://claude.ai/settings/usage\n"
    exit 0
}

# ─── Check Dependencies ──────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
    error_state "jq not installed" "Run: brew install jq"
fi

# ─── Get OAuth Token ──────────────────────────────────────────────────

TOKEN=""
SUB_TYPE=""

# Try Keychain first (preferred)
CREDS_JSON=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null || echo "")

if [ -z "$CREDS_JSON" ]; then
    # Fallback to credentials file
    if [ -f "$CREDS_FILE" ]; then
        CREDS_JSON=$(cat "$CREDS_FILE" 2>/dev/null || echo "")
    fi
fi

if [ -z "$CREDS_JSON" ]; then
    error_state "No Claude Code credentials" "Run 'claude' in terminal to log in"
fi

TOKEN=$(echo "$CREDS_JSON" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
SUB_TYPE=$(echo "$CREDS_JSON" | jq -r '.claudeAiOauth.subscriptionType // "unknown"' 2>/dev/null)
EXPIRES_AT=$(echo "$CREDS_JSON" | jq -r '.claudeAiOauth.expiresAt // 0' 2>/dev/null)

if [ -z "$TOKEN" ]; then
    error_state "Invalid credentials" "OAuth token not found in Keychain"
fi

# Check token expiry (expiresAt is in milliseconds)
NOW_MS=$(( $(date +%s) * 1000 ))
if [ "$EXPIRES_AT" -gt 0 ] 2>/dev/null && [ "$EXPIRES_AT" -lt "$NOW_MS" ] 2>/dev/null; then
    error_state "Token expired" "Run 'claude login' to refresh"
fi

# ─── Fetch Usage Data (with cache) ───────────────────────────────────

USE_CACHE=false
USAGE_JSON=""
CACHE_AGE=0

if [ -f "$CACHE_FILE" ]; then
    CACHE_AGE=$(( $(date +%s) - $(stat -f "%m" "$CACHE_FILE" 2>/dev/null || echo 0) ))
    if [ "$CACHE_AGE" -lt "$CACHE_MAX_AGE" ]; then
        USAGE_JSON=$(cat "$CACHE_FILE" 2>/dev/null)
        USE_CACHE=true
    fi
fi

if [ "$USE_CACHE" = false ]; then
    USAGE_JSON=$(curl -s --max-time 10 "$API_URL" \
        -H "Authorization: Bearer $TOKEN" \
        -H "anthropic-beta: $API_BETA" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        2>/dev/null)

    # Check for API error
    if echo "$USAGE_JSON" | jq -e '.error' &>/dev/null; then
        ERROR_MSG=$(echo "$USAGE_JSON" | jq -r '.error.message // "Unknown API error"' 2>/dev/null)
        # Try cached data
        if [ -f "$CACHE_FILE" ]; then
            USAGE_JSON=$(cat "$CACHE_FILE")
            CACHE_AGE=$(( $(date +%s) - $(stat -f "%m" "$CACHE_FILE" 2>/dev/null || echo 0) ))
            USE_CACHE=true
        else
            error_state "API Error" "$ERROR_MSG"
        fi
    elif [ -z "$USAGE_JSON" ] || ! echo "$USAGE_JSON" | jq -e '.' &>/dev/null; then
        # Invalid response — try cache
        if [ -f "$CACHE_FILE" ]; then
            USAGE_JSON=$(cat "$CACHE_FILE")
            CACHE_AGE=$(( $(date +%s) - $(stat -f "%m" "$CACHE_FILE" 2>/dev/null || echo 0) ))
            USE_CACHE=true
        else
            error_state "Cannot reach Anthropic" "Check your internet connection"
        fi
    else
        # Valid fresh response — cache it
        echo "$USAGE_JSON" > "$CACHE_FILE"
    fi
fi

# ─── Parse Usage Data ─────────────────────────────────────────────────

FIVE_H_PCT=$(echo "$USAGE_JSON" | jq -r '.five_hour.utilization // 0' 2>/dev/null)
FIVE_H_RESET=$(echo "$USAGE_JSON" | jq -r '.five_hour.resets_at // null' 2>/dev/null)
SEVEN_D_PCT=$(echo "$USAGE_JSON" | jq -r '.seven_day.utilization // 0' 2>/dev/null)
SEVEN_D_RESET=$(echo "$USAGE_JSON" | jq -r '.seven_day.resets_at // null' 2>/dev/null)

# Round to integers for display
FIVE_H_PCT=$(printf "%.0f" "$FIVE_H_PCT" 2>/dev/null || echo "0")
SEVEN_D_PCT=$(printf "%.0f" "$SEVEN_D_PCT" 2>/dev/null || echo "0")

# ─── Generate Output ──────────────────────────────────────────────────

FIVE_H_COLOR=$(get_color "$FIVE_H_PCT")
SEVEN_D_COLOR=$(get_color "$SEVEN_D_PCT")

# Menu bar line — show 5h as primary, add 7d if also high
MENU_COLOR="$FIVE_H_COLOR"
if [ "$SEVEN_D_PCT" -ge 75 ] 2>/dev/null && [ "$FIVE_H_PCT" -lt 75 ] 2>/dev/null; then
    MENU_COLOR="$SEVEN_D_COLOR"
fi

MENU_TEXT="◉ ${FIVE_H_PCT}%"
if [ "$SEVEN_D_PCT" -ge 75 ] 2>/dev/null; then
    MENU_TEXT="◉ ${FIVE_H_PCT}%·${SEVEN_D_PCT}%"
fi

# Calculate remaining times
FIVE_H_REMAINING=$(time_remaining "$FIVE_H_RESET")
SEVEN_D_REMAINING=$(time_remaining "$SEVEN_D_RESET")

# Progress bars
FIVE_H_BAR=$(make_bar "$FIVE_H_PCT")
SEVEN_D_BAR=$(make_bar "$SEVEN_D_PCT")

# ─── Render ───────────────────────────────────────────────────────────

# Menu bar
printf '%s | color=%s size=13\n' "$MENU_TEXT" "$MENU_COLOR"

# Dropdown
printf '%s\n' "---"

# 5-hour window
printf "5-Hour Window | size=12 color=%s\n" "$DIMGRAY"
printf "%s %s%% | font=Menlo size=11 color=%s\n" "$FIVE_H_BAR" "$FIVE_H_PCT" "$FIVE_H_COLOR"
if [ "$FIVE_H_RESET" != "null" ] && [ -n "$FIVE_H_RESET" ]; then
    printf "Resets in %s | size=11 color=%s\n" "$FIVE_H_REMAINING" "$GRAY"
else
    printf "No active window | size=11 color=%s\n" "$GRAY"
fi

printf '%s\n' "---"

# 7-day window
printf "Weekly (7-Day) | size=12 color=%s\n" "$DIMGRAY"
printf "%s %s%% | font=Menlo size=11 color=%s\n" "$SEVEN_D_BAR" "$SEVEN_D_PCT" "$SEVEN_D_COLOR"
if [ "$SEVEN_D_RESET" != "null" ] && [ -n "$SEVEN_D_RESET" ]; then
    printf "Resets in %s | size=11 color=%s\n" "$SEVEN_D_REMAINING" "$GRAY"
else
    printf "No active limit | size=11 color=%s\n" "$GRAY"
fi

printf '%s\n' "---"

# Footer
SUB_LABEL=$(echo "$SUB_TYPE" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
printf "Plan: %s | size=11 color=%s\n" "$SUB_LABEL" "$GRAY"

if [ "$USE_CACHE" = true ] && [ "$CACHE_AGE" -gt 0 ]; then
    if [ "$CACHE_AGE" -lt 60 ]; then
        printf "Updated: %ss ago | size=10 color=%s\n" "$CACHE_AGE" "$DIMGRAY"
    elif [ "$CACHE_AGE" -lt 3600 ]; then
        printf "Updated: %sm ago | size=10 color=%s\n" "$(( CACHE_AGE / 60 ))" "$DIMGRAY"
    else
        printf "Updated: %sh ago (stale) | size=10 color=%s\n" "$(( CACHE_AGE / 3600 ))" "$ORANGE"
    fi
else
    printf "Updated: just now | size=10 color=%s\n" "$DIMGRAY"
fi

printf '%s\n' "---"
printf "Refresh Now | refresh=true\n"
printf "Open Usage Page | href=https://claude.ai/settings/usage\n"
