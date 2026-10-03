#!/bin/bash
# <bitbar.title>Claude Pulse</bitbar.title>
# <bitbar.version>v1.7</bitbar.version>
# <bitbar.author>G + Sage + Forge</bitbar.author>
# <bitbar.author.github>ghayyath</bitbar.author.github>
# <bitbar.desc>Shows Claude subscription usage (Session, Weekly, and per-model limits like Fable) in menu bar</bitbar.desc>
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
# Read-only: Claude Code owns its login. This script never refreshes the
# token or writes to the Keychain; a stale token means "open Claude Code".

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

TOKEN_STALE=false
NOW_MS=$(( $(date +%s) * 1000 ))
if [ "$EXPIRES_AT" -gt 0 ] 2>/dev/null && [ "$EXPIRES_AT" -lt "$NOW_MS" ] 2>/dev/null; then
    # Expired token: Claude Code refreshes it next time it runs. Show the
    # last known numbers meanwhile instead of touching its login.
    TOKEN_STALE=true
    if [ -f "$CACHE_FILE" ]; then
        USAGE_JSON=$(cat "$CACHE_FILE" 2>/dev/null)
        CACHE_AGE=$(( $(date +%s) - $(stat -f "%m" "$CACHE_FILE" 2>/dev/null || echo 0) ))
        USE_CACHE=true
    else
        error_state "Token expired" "Open Claude Code to refresh"
    fi
fi

# ─── Fetch Usage Data (with cache) ───────────────────────────────

if [ -z "$USE_CACHE" ]; then
    USE_CACHE=false
fi
if [ -z "$USAGE_JSON" ]; then
    USAGE_JSON=""
fi
if [ -z "$CACHE_AGE" ]; then
    CACHE_AGE=0
fi

if [ "$USE_CACHE" = false ]; then
    if [ -f "$CACHE_FILE" ]; then
        CACHE_AGE=$(( $(date +%s) - $(stat -f "%m" "$CACHE_FILE" 2>/dev/null || echo 0) ))
        if [ "$CACHE_AGE" -lt "$CACHE_MAX_AGE" ]; then
            USAGE_JSON=$(cat "$CACHE_FILE" 2>/dev/null)
            USE_CACHE=true
        fi
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

        # Rate limit — not an auth problem, fall back to cache
        if [ "$ERROR_TYPE" = "rate_limit_error" ]; then
            if [ -f "$CACHE_FILE" ]; then
                USAGE_JSON=$(cat "$CACHE_FILE")
                CACHE_AGE=$(( $(date +%s) - $(stat -f "%m" "$CACHE_FILE" 2>/dev/null || echo 0) ))
                USE_CACHE=true
            else
                error_state "Rate limited" "Try again in a few minutes"
            fi
        elif [ "$ERROR_TYPE" = "authentication_error" ]; then
            TOKEN_STALE=true
        fi

        # Still have an error after handling? Fall back to cache or error out
        if echo "$USAGE_JSON" | jq -e '.error' &>/dev/null; then
            ERROR_MSG=$(echo "$USAGE_JSON" | jq -r '.error.message // "Unknown API error"' 2>/dev/null)
            if [ -f "$CACHE_FILE" ]; then
                USAGE_JSON=$(cat "$CACHE_FILE")
                CACHE_AGE=$(( $(date +%s) - $(stat -f "%m" "$CACHE_FILE" 2>/dev/null || echo 0) ))
                USE_CACHE=true
            elif [ "$TOKEN_STALE" = true ]; then
                error_state "Token expired" "Open Claude Code to refresh"
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
# Prefer the generic `limits` array (session, weekly, and per-model scoped
# limits like Fable). Fall back to the legacy five_hour/seven_day fields.
# Output: one TSV row per limit → label, percent, resets_at

LIMIT_ROWS=$(echo "$USAGE_JSON" | jq -r '
    if (.limits | type) == "array" and (.limits | length) > 0 then
        .limits[] | [
            (if .kind == "session" then "Session"
             elif .kind == "weekly_all" then "Weekly"
             else (.scope.model.display_name // .scope.surface.display_name // .kind) end),
            (.percent // 0 | round),
            (.resets_at // "null")
        ]
    else
        ([ "Session", .five_hour.utilization, .five_hour.resets_at ],
         [ "Weekly", .seven_day.utilization, .seven_day.resets_at ],
         (if .seven_day_sonnet then [ "Sonnet", .seven_day_sonnet.utilization, .seven_day_sonnet.resets_at ] else empty end))
        | [ .[0], (.[1] // 0 | round), (.[2] // "null") ]
    end | @tsv' 2>/dev/null)

if [ -z "$LIMIT_ROWS" ]; then
    error_state "Unexpected API response" "No usage limits found"
fi

# Reset label: "2h 56m · 11:29 AM" (same day) or "1d 13h · Sun 10:59 PM"
reset_label() {
    local reset_ts="$1"
    local remaining
    remaining=$(time_remaining "$reset_ts")
    [ -z "$remaining" ] && return
    local epoch
    epoch=$(python3 -c "
from datetime import datetime
try: print(int(datetime.fromisoformat('$reset_ts'.replace('Z', '+00:00')).timestamp()))
except: print(0)
" 2>/dev/null)
    if [ -z "$epoch" ] || [ "$epoch" = "0" ] || [ "$remaining" = "now" ]; then
        echo "$remaining"
        return
    fi
    local clock
    if [ "$(date -r "$epoch" +%F)" = "$(date +%F)" ]; then
        clock=$(date -r "$epoch" "+%-I:%M %p")
    else
        clock=$(date -r "$epoch" "+%a %-I:%M %p")
    fi
    echo "$remaining · $clock"
}

# ─── Build Display ───────────────────────────────────────────────

# Menu bar: session % as primary; append the worst other limit if ≥75%
SESSION_PCT=0
WORST_OTHER=0
while IFS=$'\t' read -r label pct reset; do
    if [ "$label" = "Session" ]; then
        SESSION_PCT=$pct
    elif [ "$pct" -gt "$WORST_OTHER" ] 2>/dev/null; then
        WORST_OTHER=$pct
    fi
done <<< "$LIMIT_ROWS"

MENU_COLOR=$(get_color "$SESSION_PCT")
MENU_TEXT="◉ ${SESSION_PCT}%"
if [ "$WORST_OTHER" -ge 75 ] 2>/dev/null; then
    MENU_TEXT="◉ ${SESSION_PCT}%·${WORST_OTHER}%"
    if [ "$SESSION_PCT" -lt "$WORST_OTHER" ]; then
        MENU_COLOR=$(get_color "$WORST_OTHER")
    fi
fi

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
if [ "$TOKEN_STALE" = true ]; then
    printf 'Token expired · open Claude Code to refresh | size=10 color=%s\n' "$YELLOW"
fi

# One row per limit: label + bar + percentage, then reset line
while IFS=$'\t' read -r label pct reset; do
    printf '%s\n' "---"
    color=$(get_color "$pct")
    printf '%-8.8s %s  %s | font=Menlo size=12 color=%s trim=false\n' \
        "$label" "$(make_bar "$pct")" "$(printf "%3s%%" "$pct")" "$color"
    when=$(reset_label "$reset")
    if [ -n "$when" ]; then
        printf '         Resets in %s | font=Menlo size=10 color=%s trim=false\n' "$when" "$DIM"
    else
        printf '         No active window | font=Menlo size=10 color=%s trim=false\n' "$DIM"
    fi
done <<< "$LIMIT_ROWS"

printf '%s\n' "---"
printf 'Refresh Now | refresh=true\n'
printf 'Open Usage Page | href=https://claude.ai/settings/usage\n'
