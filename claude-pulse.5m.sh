#!/bin/bash
# <bitbar.title>Claude Pulse</bitbar.title>
# <bitbar.version>v1.3</bitbar.version>
# <bitbar.author>G + Sage + Forge</bitbar.author>
# <bitbar.author.github>ghayyath</bitbar.author.github>
# <bitbar.desc>Shows Claude subscription usage (Session + Weekly + Sonnet) in menu bar</bitbar.desc>
# <bitbar.dependencies>jq</bitbar.dependencies>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>

# ─── Config ───────────────────────────────────────────────────────
CACHE_FILE="/tmp/claude-pulse-cache.json"
CACHE_MAX_AGE=60
API_URL="https://api.anthropic.com/api/oauth/usage"
API_BETA="oauth-2025-04-20"
KEYCHAIN_SERVICE="Claude Code-credentials"
CREDS_FILE="$HOME/.claude/.credentials.json"
REFRESH_URL="https://console.anthropic.com/v1/oauth/token"
CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"

# ─── Colors (matches Android widget) ─────────────────────────────
BRAND="#6ee7b7"      # Brand green — bars + percentages
YELLOW="#FF9800"     # 50-74%
ORANGE="#FF5722"     # 75-89%
RED="#F44336"        # 90-100%
WHITE="#FFFFFF"      # Header text
LABEL="#B3B3B3"     # Row labels (70% white, like Android #B3FFFFFF)
DIM="#808080"        # Reset times (50% white)
FAINT="#666666"      # Timestamps

# ─── Helpers ─────────────────────────────────────────────────────

get_color() {
    local pct=$1
    if [ "$pct" -lt 50 ] 2>/dev/null; then
        echo "$BRAND"
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
    local width=15
    local filled=$(( pct * width / 100 ))
    # Ensure at least 1 filled block when usage > 0
    if [ "$pct" -gt 0 ] 2>/dev/null && [ "$filled" -eq 0 ]; then
        filled=1
    fi
    local empty=$(( width - filled ))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo -n "$bar"
}

time_remaining() {
    local reset_ts="$1"
    if [ -z "$reset_ts" ] || [ "$reset_ts" = "null" ]; then
        echo -n ""
        return
    fi

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
        printf "%s | size=11 color=%s\n" "$detail" "$DIM"
    fi
    printf '%s\n' "---"
    printf "Refresh | refresh=true\n"
    printf "Open Usage Page | href=https://claude.ai/settings/usage\n"
    exit 0
}

# ─── Auto-Refresh OAuth Token ────────────────────────────────────

auto_refresh_token() {
    local refresh_token
    refresh_token=$(echo "$CREDS_JSON" | jq -r '.claudeAiOauth.refreshToken // empty' 2>/dev/null)

    if [ -z "$refresh_token" ]; then
        return 1
    fi

    local refresh_response
    refresh_response=$(curl -sL --max-time 15 -X POST "$REFRESH_URL" \
        -H "Content-Type: application/json" \
        -d "$(printf '{"grant_type":"refresh_token","refresh_token":"%s","client_id":"%s"}' "$refresh_token" "$CLIENT_ID")" \
        2>/dev/null)

    local new_access
    new_access=$(echo "$refresh_response" | jq -r '.access_token // empty' 2>/dev/null)

    if [ -z "$new_access" ]; then
        return 1
    fi

    local new_refresh
    new_refresh=$(echo "$refresh_response" | jq -r '.refresh_token // empty' 2>/dev/null)
    local expires_in
    expires_in=$(echo "$refresh_response" | jq -r '.expires_in // 28800' 2>/dev/null)

    local new_expires_at
    new_expires_at=$(( ($(date +%s) + expires_in) * 1000 ))

    CREDS_JSON=$(echo "$CREDS_JSON" | jq \
        --arg at "$new_access" \
        --arg rt "${new_refresh:-$refresh_token}" \
        --argjson ea "$new_expires_at" \
        '.claudeAiOauth.accessToken = $at | .claudeAiOauth.refreshToken = $rt | .claudeAiOauth.expiresAt = $ea' \
        2>/dev/null)

    security delete-generic-password -s "$KEYCHAIN_SERVICE" 2>/dev/null
    security add-generic-password -s "$KEYCHAIN_SERVICE" -a "$USER" -w "$CREDS_JSON" 2>/dev/null

    if [ -f "$CREDS_FILE" ]; then
        echo "$CREDS_JSON" > "$CREDS_FILE" 2>/dev/null
    fi

    TOKEN="$new_access"
    EXPIRES_AT="$new_expires_at"

    return 0
}

# ─── Check Dependencies ──────────────────────────────────────────

if ! command -v jq &>/dev/null; then
    error_state "jq not installed" "Run: brew install jq"
fi

# ─── Get OAuth Token ─────────────────────────────────────────────

TOKEN=""
SUB_TYPE=""

CREDS_JSON=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null || echo "")

if [ -z "$CREDS_JSON" ]; then
    if [ -f "$CREDS_FILE" ]; then
        CREDS_JSON=$(cat "$CREDS_FILE" 2>/dev/null || echo "")
    fi
fi

if [ -z "$CREDS_JSON" ]; then
    error_state "No Claude Code credentials" "Run 'claude' in terminal to log in"
fi

TOKEN=$(echo "$CREDS_JSON" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
SUB_TYPE=$(echo "$CREDS_JSON" | jq -r '.claudeAiOauth.subscriptionType // "unknown"' 2>/dev/null)
RATE_TIER=$(echo "$CREDS_JSON" | jq -r '.claudeAiOauth.rateLimitTier // ""' 2>/dev/null)
EXPIRES_AT=$(echo "$CREDS_JSON" | jq -r '.claudeAiOauth.expiresAt // 0' 2>/dev/null)

if [ -z "$TOKEN" ]; then
    error_state "Invalid credentials" "OAuth token not found in Keychain"
fi

NOW_MS=$(( $(date +%s) * 1000 ))
if [ "$EXPIRES_AT" -gt 0 ] 2>/dev/null && [ "$EXPIRES_AT" -lt "$NOW_MS" ] 2>/dev/null; then
    if ! auto_refresh_token; then
        error_state "Token expired" "Run 'claude login' to refresh"
    fi
fi

# ─── Fetch Usage Data (with cache) ───────────────────────────────

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

    if echo "$USAGE_JSON" | jq -e '.error' &>/dev/null; then
        ERROR_TYPE=$(echo "$USAGE_JSON" | jq -r '.error.type // ""' 2>/dev/null)
        if [ "$ERROR_TYPE" = "authentication_error" ]; then
            if auto_refresh_token; then
                USAGE_JSON=$(curl -s --max-time 10 "$API_URL" \
                    -H "Authorization: Bearer $TOKEN" \
                    -H "anthropic-beta: $API_BETA" \
                    -H "Content-Type: application/json" \
                    -H "Accept: application/json" \
                    2>/dev/null)
            fi
        fi

        if echo "$USAGE_JSON" | jq -e '.error' &>/dev/null; then
            ERROR_MSG=$(echo "$USAGE_JSON" | jq -r '.error.message // "Unknown API error"' 2>/dev/null)
            if [ -f "$CACHE_FILE" ]; then
                USAGE_JSON=$(cat "$CACHE_FILE")
                CACHE_AGE=$(( $(date +%s) - $(stat -f "%m" "$CACHE_FILE" 2>/dev/null || echo 0) ))
                USE_CACHE=true
            else
                error_state "API Error" "$ERROR_MSG"
            fi
        else
            echo "$USAGE_JSON" > "$CACHE_FILE"
        fi
    elif [ -z "$USAGE_JSON" ] || ! echo "$USAGE_JSON" | jq -e '.' &>/dev/null; then
        if [ -f "$CACHE_FILE" ]; then
            USAGE_JSON=$(cat "$CACHE_FILE")
            CACHE_AGE=$(( $(date +%s) - $(stat -f "%m" "$CACHE_FILE" 2>/dev/null || echo 0) ))
            USE_CACHE=true
        else
            error_state "Cannot reach Anthropic" "Check your internet connection"
        fi
    else
        echo "$USAGE_JSON" > "$CACHE_FILE"
    fi
fi

# ─── Parse Usage Data ────────────────────────────────────────────

FIVE_H_PCT=$(echo "$USAGE_JSON" | jq -r '.five_hour.utilization // 0' 2>/dev/null)
FIVE_H_RESET=$(echo "$USAGE_JSON" | jq -r '.five_hour.resets_at // null' 2>/dev/null)
SEVEN_D_PCT=$(echo "$USAGE_JSON" | jq -r '.seven_day.utilization // 0' 2>/dev/null)
SEVEN_D_RESET=$(echo "$USAGE_JSON" | jq -r '.seven_day.resets_at // null' 2>/dev/null)
SONNET_PCT=$(echo "$USAGE_JSON" | jq -r '.seven_day_sonnet.utilization // 0' 2>/dev/null)
SONNET_RESET=$(echo "$USAGE_JSON" | jq -r '.seven_day_sonnet.resets_at // null' 2>/dev/null)

FIVE_H_PCT=$(printf "%.0f" "$FIVE_H_PCT" 2>/dev/null || echo "0")
SEVEN_D_PCT=$(printf "%.0f" "$SEVEN_D_PCT" 2>/dev/null || echo "0")
SONNET_PCT=$(printf "%.0f" "$SONNET_PCT" 2>/dev/null || echo "0")

# ─── Build Display ───────────────────────────────────────────────

FIVE_H_COLOR=$(get_color "$FIVE_H_PCT")
SEVEN_D_COLOR=$(get_color "$SEVEN_D_PCT")
SONNET_COLOR=$(get_color "$SONNET_PCT")

# Menu bar — show 5h as primary, escalate color if weekly is worse
MENU_COLOR="$FIVE_H_COLOR"
if [ "$SEVEN_D_PCT" -ge 75 ] 2>/dev/null && [ "$FIVE_H_PCT" -lt 75 ] 2>/dev/null; then
    MENU_COLOR="$SEVEN_D_COLOR"
fi

MENU_TEXT="◉ ${FIVE_H_PCT}%"
if [ "$SEVEN_D_PCT" -ge 75 ] 2>/dev/null; then
    MENU_TEXT="◉ ${FIVE_H_PCT}%·${SEVEN_D_PCT}%"
fi

# Remaining times
FIVE_H_REMAINING=$(time_remaining "$FIVE_H_RESET")
SEVEN_D_REMAINING=$(time_remaining "$SEVEN_D_RESET")
SONNET_REMAINING=$(time_remaining "$SONNET_RESET")

# Progress bars
FIVE_H_BAR=$(make_bar "$FIVE_H_PCT")
SEVEN_D_BAR=$(make_bar "$SEVEN_D_PCT")
SONNET_BAR=$(make_bar "$SONNET_PCT")

# Format percentages right-aligned (pad to 3 chars)
FIVE_H_LABEL=$(printf "%3s%%" "$FIVE_H_PCT")
SEVEN_D_LABEL=$(printf "%3s%%" "$SEVEN_D_PCT")
SONNET_LABEL=$(printf "%3s%%" "$SONNET_PCT")

# Updated timestamp
if [ "$USE_CACHE" = true ] && [ "$CACHE_AGE" -gt 0 ]; then
    if [ "$CACHE_AGE" -lt 60 ]; then
        UPDATED="${CACHE_AGE}s ago"
    elif [ "$CACHE_AGE" -lt 3600 ]; then
        UPDATED="$(( CACHE_AGE / 60 ))m ago"
    else
        UPDATED="$(( CACHE_AGE / 3600 ))h ago"
    fi
else
    UPDATED="just now"
fi

# ─── Render (matches Android widget layout) ────────────────────

# Menu bar icon
printf '%s | color=%s size=13\n' "$MENU_TEXT" "$MENU_COLOR"
printf '%s\n' "---"

# Header row: CLAUDE PULSE + updated time (like Android header)
# Map plan display name from subscriptionType + rateLimitTier
case "$RATE_TIER" in
    *max_20x*) SUB_LABEL="Max 20x" ;;
    *max_5x*)  SUB_LABEL="Max 5x" ;;
    *)
        case "$SUB_TYPE" in
            pro)  SUB_LABEL="Pro" ;;
            free) SUB_LABEL="Free" ;;
            max)  SUB_LABEL="Max" ;;
            *)    SUB_LABEL="$SUB_TYPE" ;;
        esac
    ;;
esac
printf 'CLAUDE PULSE · %s | size=12 color=%s\n' "$SUB_LABEL" "$WHITE"
printf 'Updated %s | size=10 color=%s\n' "$UPDATED" "$FAINT"
printf '%s\n' "---"

# Session row: label + bar + percentage
printf 'Session  %s  %s | font=Menlo size=12 color=%s trim=false\n' "$FIVE_H_BAR" "$FIVE_H_LABEL" "$FIVE_H_COLOR"
if [ -n "$FIVE_H_REMAINING" ]; then
    printf '         Resets in %s | font=Menlo size=10 color=%s trim=false\n' "$FIVE_H_REMAINING" "$DIM"
else
    printf '         No active window | font=Menlo size=10 color=%s trim=false\n' "$DIM"
fi

printf '%s\n' "---"

# Weekly row
printf 'Weekly   %s  %s | font=Menlo size=12 color=%s trim=false\n' "$SEVEN_D_BAR" "$SEVEN_D_LABEL" "$SEVEN_D_COLOR"
if [ -n "$SEVEN_D_REMAINING" ]; then
    printf '         Resets in %s | font=Menlo size=10 color=%s trim=false\n' "$SEVEN_D_REMAINING" "$DIM"
else
    printf '         No active limit | font=Menlo size=10 color=%s trim=false\n' "$DIM"
fi

printf '%s\n' "---"

# Sonnet row
printf 'Sonnet   %s  %s | font=Menlo size=12 color=%s trim=false\n' "$SONNET_BAR" "$SONNET_LABEL" "$SONNET_COLOR"
if [ -n "$SONNET_REMAINING" ]; then
    printf '         Resets in %s | font=Menlo size=10 color=%s trim=false\n' "$SONNET_REMAINING" "$DIM"
else
    printf '         No active limit | font=Menlo size=10 color=%s trim=false\n' "$DIM"
fi

printf '%s\n' "---"
printf 'Refresh Now | refresh=true\n'
printf 'Open Usage Page | href=https://claude.ai/settings/usage\n'
