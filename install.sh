#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "⚒  Claude Forge — TypeScript Edition"
echo ""

# Check source directories exist
for dir in agents commands skills rules; do
  if [ ! -d "${SCRIPT_DIR}/${dir}" ]; then
    echo -e "${RED}Error:${NC} ${dir}/ not found. Run this from the claude-forge-typescript directory."
    exit 1
  fi
done

# Parse arguments
TARGET="${HOME}/.claude"
MODE="symlink"
LABEL="globally"

while [[ $# -gt 0 ]]; do
  case $1 in
    --project)
      TARGET="${2:-.}/.claude"
      LABEL="to project: ${TARGET}"
      shift 2
      ;;
    --copy)
      MODE="copy"
      shift
      ;;
    --help)
      echo "Usage: ./install.sh [options]"
      echo ""
      echo "Options:"
      echo "  --project <path>  Install to a specific project (default: ~/.claude)"
      echo "  --copy            Copy files instead of symlink (no auto-upgrade)"
      echo "  --help            Show this help"
      echo ""
      echo "Default: symlinks to ~/.claude/ (git pull = instant update)"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option:${NC} $1"
      exit 1
      ;;
  esac
done

echo "Installing ${LABEL} (mode: ${MODE})"
echo ""

# Backup existing files if they exist
BACKED_UP=false
for dir in agents commands skills rules; do
  if [ -d "${TARGET}/${dir}" ]; then
    if [ "$BACKED_UP" = false ]; then
      echo -e "${YELLOW}Backing up existing files to ${TARGET}/.backup-${TIMESTAMP}/${NC}"
      BACKED_UP=true
    fi
    mkdir -p "${TARGET}/.backup-${TIMESTAMP}"
    cp -r "${TARGET}/${dir}" "${TARGET}/.backup-${TIMESTAMP}/${dir}" 2>/dev/null || true
  fi
done

# Install each directory
TOTAL_FILES=0
for dir in agents commands skills rules; do
  mkdir -p "${TARGET}/${dir}"

  if [ "$MODE" = "symlink" ]; then
    # Remove existing contents and symlink
    rm -rf "${TARGET:?}/${dir:?}"
    ln -sf "${SCRIPT_DIR}/${dir}" "${TARGET}/${dir}"
  else
    # Copy files
    cp -r "${SCRIPT_DIR}/${dir}/"* "${TARGET}/${dir}/"
  fi

  count=$(find "${SCRIPT_DIR}/${dir}" -type f | wc -l | tr -d ' ')
  TOTAL_FILES=$((TOTAL_FILES + count))
  echo -e "  ${GREEN}✓${NC} ${dir} (${count} files)"
done

# Auto-merge hooks into settings.json
echo ""
SETTINGS_FILE="${TARGET}/settings.json"
HOOKS_SOURCE="${SCRIPT_DIR}/hooks/hooks.json"

if [ -f "$HOOKS_SOURCE" ]; then
  if command -v jq &>/dev/null; then
    if [ -f "$SETTINGS_FILE" ]; then
      # Deep-merge hooks by phase (PreToolUse, PostToolUse, Stop) — preserves user's custom hooks
      cp "$SETTINGS_FILE" "${SETTINGS_FILE}.backup-${TIMESTAMP}" 2>/dev/null || true
      EXISTING_HOOK_COUNT=$(jq '[.hooks // {} | to_entries[] | .value | length] | add // 0' "$SETTINGS_FILE")
      FORGE_IDS=$(jq '[.hooks | to_entries[] | .value[] | .id] | join(",")' "$HOOKS_SOURCE")
      # Remove existing forge hooks (by ID), then append new ones per phase
      jq --slurpfile forge "$HOOKS_SOURCE" '
        .hooks as $existing |
        ($forge[0].hooks | to_entries | map(.key) | .[]) as $phase |
        # Forge hook IDs for dedup
        ($forge[0].hooks | to_entries | map(.value[].id)) as $forgeIds |
        .hooks[$phase] = (
          [($existing[$phase] // [])[] | select(.id as $id | $forgeIds | index($id) | not)] +
          ($forge[0].hooks[$phase] // [])
        )
      ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
      mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
      if [ "$EXISTING_HOOK_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}✓${NC} hooks deep-merged into settings.json — your custom hooks preserved (backup: settings.json.backup-${TIMESTAMP})"
      else
        echo -e "  ${GREEN}✓${NC} hooks merged into settings.json (backup: settings.json.backup-${TIMESTAMP})"
      fi
    else
      # Create new settings.json with hooks
      mkdir -p "$(dirname "$SETTINGS_FILE")"
      jq '{hooks: .hooks}' "$HOOKS_SOURCE" > "$SETTINGS_FILE"
      echo -e "  ${GREEN}✓${NC} hooks installed to settings.json"
    fi
  else
    echo -e "  ${YELLOW}⚠${NC} jq not found — hooks require manual setup"
    echo "    Install jq: brew install jq (macOS) / apt install jq (Linux)"
    echo "    Or manually merge hooks/hooks.json into ${SETTINGS_FILE}"
  fi
fi

# Summary
echo ""
echo -e "${GREEN}Done!${NC} Installed ${TOTAL_FILES} files."
if [ "$MODE" = "symlink" ]; then
  echo "  Upgrade anytime: cd ${SCRIPT_DIR} && git pull"
fi
echo "  Restart Claude Code to pick up changes."
echo ""
