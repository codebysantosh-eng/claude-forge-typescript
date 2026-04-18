#!/usr/bin/env bash
set -euo pipefail

# Hook Integration Tests
# Verifies that hooks catch what they claim to catch.
# Run: ./hooks/tests/run-tests.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_SCRIPTS_DIR="${SCRIPT_DIR}/../scripts"
PASS=0
FAIL=0
TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

run_hook() {
  local hook_id="$1"
  local input="$2"
  echo "$input" | node "${HOOKS_SCRIPTS_DIR}/${hook_id}.js" 2>/dev/null || true
}

assert_blocks() {
  local test_name="$1"
  local hook_id="$2"
  local input="$3"
  TOTAL=$((TOTAL + 1))

  local result
  result=$(run_hook "$hook_id" "$input")

  if echo "$result" | grep -q '"decision":"block"'; then
    echo -e "  ${GREEN}PASS${NC} $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $test_name — expected block, got: $result"
    FAIL=$((FAIL + 1))
  fi
}

assert_warns() {
  local test_name="$1"
  local hook_id="$2"
  local input="$3"
  TOTAL=$((TOTAL + 1))

  local result
  result=$(run_hook "$hook_id" "$input")

  if echo "$result" | grep -q '"message"'; then
    echo -e "  ${GREEN}PASS${NC} $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $test_name — expected warning, got: $result"
    FAIL=$((FAIL + 1))
  fi
}

assert_passes() {
  local test_name="$1"
  local hook_id="$2"
  local input="$3"
  TOTAL=$((TOTAL + 1))

  local result
  result=$(run_hook "$hook_id" "$input")

  if [ -z "$result" ]; then
    echo -e "  ${GREEN}PASS${NC} $test_name"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} $test_name — expected pass (empty), got: $result"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "⚒  Claude Forge — Hook Integration Tests"
echo ""

# ─── block-hook-bypass ───
echo "block-hook-bypass:"
assert_blocks "blocks --no-verify on git commit" \
  "block-hook-bypass" \
  '{"tool_input":{"command":"git commit -m \"test\" --no-verify"}}'

assert_blocks "blocks --no-gpg-sign on git commit" \
  "block-hook-bypass" \
  '{"tool_input":{"command":"git commit --no-gpg-sign -m \"test\""}}'

assert_passes "allows normal git commit" \
  "block-hook-bypass" \
  '{"tool_input":{"command":"git commit -m \"feat: add feature\""}}'

# ─── block-force-push ───
echo ""
echo "block-force-push:"
assert_blocks "blocks git push --force" \
  "block-force-push" \
  '{"tool_input":{"command":"git push origin main --force"}}'

assert_passes "allows git push --force-with-lease" \
  "block-force-push" \
  '{"tool_input":{"command":"git push origin main --force-with-lease"}}'

assert_passes "allows normal git push" \
  "block-force-push" \
  '{"tool_input":{"command":"git push origin main"}}'

# ─── next-public-secret-guard ───
echo ""
echo "next-public-secret-guard:"
assert_blocks "blocks NEXT_PUBLIC_SECRET_KEY" \
  "next-public-secret-guard" \
  '{"tool_input":{"file_path":"src/.env","new_string":"NEXT_PUBLIC_SECRET_KEY=abc123"}}'

assert_blocks "blocks NEXT_PUBLIC_API_KEY" \
  "next-public-secret-guard" \
  '{"tool_input":{"file_path":"src/config.ts","content":"const key = process.env.NEXT_PUBLIC_API_KEY"}}'

assert_blocks "blocks NEXT_PUBLIC_CLIENT_SECRET" \
  "next-public-secret-guard" \
  '{"tool_input":{"file_path":"src/.env","new_string":"NEXT_PUBLIC_CLIENT_SECRET=mysecret"}}'

assert_passes "allows NEXT_PUBLIC_APP_URL" \
  "next-public-secret-guard" \
  '{"tool_input":{"file_path":"src/.env","new_string":"NEXT_PUBLIC_APP_URL=https://myapp.com"}}'

assert_passes "allows NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY (no SECRET/PASSWORD/PRIVATE match)" \
  "next-public-secret-guard" \
  '{"tool_input":{"file_path":"src/.env","new_string":"NEXT_PUBLIC_STRIPE_PUBLISHABLE=pk_live_abc"}}'

# ─── console-log-warn ───
echo ""
echo "console-log-warn:"
assert_warns "warns on console.log in source file" \
  "console-log-warn" \
  '{"tool_input":{"file_path":"src/lib/utils.ts","new_string":"console.log(\"debug\")"}}'

assert_passes "skips console.log in test file" \
  "console-log-warn" \
  '{"tool_input":{"file_path":"src/lib/utils.test.ts","new_string":"console.log(\"debug\")"}}'

assert_passes "skips console.log in spec file" \
  "console-log-warn" \
  '{"tool_input":{"file_path":"src/lib/utils.spec.tsx","new_string":"console.log(\"debug\")"}}'

assert_passes "no warning when no console.log" \
  "console-log-warn" \
  '{"tool_input":{"file_path":"src/lib/utils.ts","new_string":"const x = 1;"}}'

# ─── config-guard ───
echo ""
echo "config-guard:"
assert_warns "warns on tsconfig.json edit" \
  "config-guard" \
  '{"tool_input":{"file_path":"/project/tsconfig.json","new_string":"{}"}}'

assert_warns "warns on next.config edit" \
  "config-guard" \
  '{"tool_input":{"file_path":"/project/next.config.js","new_string":"{}"}}'

assert_warns "warns on prisma schema edit" \
  "config-guard" \
  '{"tool_input":{"file_path":"/project/prisma/schema.prisma","new_string":"model User {}"}}'

assert_passes "no warning on normal source file" \
  "config-guard" \
  '{"tool_input":{"file_path":"src/lib/utils.ts","new_string":"export const x = 1;"}}'

# ─── large-file-warn ───
echo ""
echo "large-file-warn:"
TMPFILE=$(mktemp /tmp/forge-test-XXXXXX.ts)
for i in $(seq 1 850); do echo "const line${i} = ${i};" >> "$TMPFILE"; done

assert_warns "warns on file >800 lines" \
  "large-file-warn" \
  "{\"tool_input\":{\"file_path\":\"${TMPFILE}\"}}"

rm -f "$TMPFILE"

TMPFILE2=$(mktemp /tmp/forge-test-XXXXXX.ts)
echo "const x = 1;" > "$TMPFILE2"

assert_passes "no warning on small file" \
  "large-file-warn" \
  "{\"tool_input\":{\"file_path\":\"${TMPFILE2}\"}}"

rm -f "$TMPFILE2"

# ─── coverage-threshold-warn ───
echo ""
echo "coverage-threshold-warn:"
assert_warns "warns when overall coverage is below 80%" \
  "coverage-threshold-warn" \
  '{"tool_input":{"command":"npm test -- --coverage"},"tool_output":{"stdout":"All files | 65.00 | 70.00 | 60.00 | 65.00 |","exit_code":0}}'

assert_warns "warns when coverage is exactly at boundary (79%)" \
  "coverage-threshold-warn" \
  '{"tool_input":{"command":"jest --coverage"},"tool_output":{"stdout":"All files | 79.00 | 75.00 | 79.00 | 79.00 |","exit_code":0}}'

assert_passes "no warning when coverage meets target (80%)" \
  "coverage-threshold-warn" \
  '{"tool_input":{"command":"npm test -- --coverage"},"tool_output":{"stdout":"All files | 80.00 | 80.00 | 80.00 | 80.00 |","exit_code":0}}'

assert_passes "no warning for non-coverage commands" \
  "coverage-threshold-warn" \
  '{"tool_input":{"command":"npm run build"},"tool_output":{"stdout":"Build successful","exit_code":0}}'

# ─── Summary ───
echo ""
echo "─────────────────────────────────"
echo -e "Total: ${TOTAL}  ${GREEN}Pass: ${PASS}${NC}  ${RED}Fail: ${FAIL}${NC}"
echo "─────────────────────────────────"

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}Some tests failed!${NC}"
  exit 1
else
  echo -e "${GREEN}All tests passed!${NC}"
fi
echo ""
