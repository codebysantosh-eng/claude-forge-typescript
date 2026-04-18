#!/usr/bin/env bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "⚒  Claude Forge — Uninstaller"
echo ""

# Parse arguments
TARGET="${HOME}/.claude"
LABEL="globally"

while [[ $# -gt 0 ]]; do
  case $1 in
    --project)
      TARGET="${2:-.}/.claude"
      LABEL="from project: ${TARGET}"
      shift 2
      ;;
    --help)
      echo "Usage: ./uninstall.sh [options]"
      echo ""
      echo "Options:"
      echo "  --project <path>  Uninstall from a specific project (default: ~/.claude)"
      echo "  --help            Show this help"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option:${NC} $1"
      exit 1
      ;;
  esac
done

echo "Uninstalling ${LABEL}"
echo ""

# Remove forge directories (agents, commands, skills, rules)
REMOVED=0
for dir in agents commands skills rules; do
  if [ -d "${TARGET}/${dir}" ] || [ -L "${TARGET}/${dir}" ]; then
    rm -rf "${TARGET:?}/${dir:?}"
    echo -e "  ${GREEN}✓${NC} Removed ${dir}/"
    REMOVED=$((REMOVED + 1))
  fi
done

if [ "$REMOVED" -eq 0 ]; then
  echo -e "  ${YELLOW}⚠${NC} No forge directories found in ${TARGET}"
  echo ""
  exit 0
fi

# Remove forge hooks from settings.json
SETTINGS_FILE="${TARGET}/settings.json"
if [ -f "$SETTINGS_FILE" ] && command -v jq &>/dev/null; then
  if jq -e '.hooks' "$SETTINGS_FILE" &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    HOOKS_SOURCE="${SCRIPT_DIR}/hooks/hooks.json"
    if [ -f "$HOOKS_SOURCE" ]; then
      # Remove only Forge hooks (by ID) — preserves user's custom hooks
      jq --slurpfile forge "$HOOKS_SOURCE" '
        ($forge[0].hooks | to_entries | map(.value[].id) | flatten) as $forgeIds |
        .hooks |= with_entries(
          .value |= [.[] | select(.id as $id | $forgeIds | index($id) | not)]
        ) |
        # Remove empty hook phase arrays
        .hooks |= with_entries(select(.value | length > 0)) |
        # Remove hooks key entirely if empty
        if (.hooks | length) == 0 then del(.hooks) else . end
      ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
    else
      # Fallback: remove all hooks (hooks.json not found)
      jq 'del(.hooks)' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
    fi
    mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    echo -e "  ${GREEN}✓${NC} Removed forge hooks from settings.json (custom hooks preserved)"

    # Remove settings.json if it's now empty (only has {})
    if [ "$(jq 'length' "$SETTINGS_FILE")" -eq 0 ]; then
      rm "$SETTINGS_FILE"
      echo -e "  ${GREEN}✓${NC} Removed empty settings.json"
    fi
  fi
elif [ -f "$SETTINGS_FILE" ]; then
  echo -e "  ${YELLOW}⚠${NC} jq not found — remove hooks from settings.json manually"
fi

# Note about backups
BACKUPS=$(find "${TARGET}" -maxdepth 1 -name ".backup-*" -type d 2>/dev/null | wc -l | tr -d ' ')
if [ "$BACKUPS" -gt 0 ]; then
  echo ""
  echo -e "  ${YELLOW}Note:${NC} ${BACKUPS} backup(s) still in ${TARGET}/.backup-*"
  echo "  Remove manually if no longer needed: rm -rf ${TARGET}/.backup-*"
fi

echo ""
echo -e "${GREEN}Done!${NC} Claude Forge has been uninstalled."
echo "  Restart Claude Code to pick up changes."
echo ""
