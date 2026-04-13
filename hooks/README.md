# Forge Hooks

Automated safety net that runs during Claude Code sessions.

## Hook Map

```
PreToolUse (before action)          PostToolUse (after action)       Stop (end of response)
┌───────────────────────────┐      ┌──────────────────────┐        ┌─────────────────────┐
│ block-hook-bypass          │      │ console-log-warn     │        │ test-reminder       │
│ pre-commit-scan            │      │ build-fail-hint      │        └─────────────────────┘
│ block-force-push           │      │ large-file-warn      │
│ config-guard               │      │ env-gitignore-guard   │
│ next-public-secret-guard   │      └──────────────────────┘
└───────────────────────────┘
```

## What Each Hook Does

| Hook | Phase | Action |
|------|-------|--------|
| `block-hook-bypass` | Pre | Blocks `--no-verify` and `--no-gpg-sign` in git commands |
| `pre-commit-scan` | Pre | Blocks commits with secrets, `console.log`, `debugger` |
| `block-force-push` | Pre | Blocks `--force` push (use `--force-with-lease`) |
| `config-guard` | Pre | Warns before modifying eslint/prettier/tsconfig/next.config/prisma schema |
| `next-public-secret-guard` | Pre | Blocks `NEXT_PUBLIC_` prefix on server-only secrets (keys, tokens, passwords) |
| `console-log-warn` | Post | Warns when `console.log` is added (skips test files) |
| `build-fail-hint` | Post | Suggests `/fix` when build commands fail |
| `large-file-warn` | Post | Warns when edited file exceeds 800 lines |
| `env-gitignore-guard` | Post | Warns if `.env` file created without `.gitignore` entry |
| `test-reminder` | Stop | Reminds to add tests if source files changed without test files |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Continue |
| 2 | Block (PreToolUse only) |

## Testing

Run the hook integration test suite to verify hooks work correctly:

```bash
./hooks/tests/run-tests.sh
```

21 tests covering: secret blocking, force-push prevention, NEXT_PUBLIC_ guard, console.log warnings, config guards, and file size warnings.

## Installation

The `install.sh` script deep-merges hooks into your `.claude/settings.json` (requires `jq`). Existing custom hooks are preserved.

Manual: merge `hooks.json` into your project's `.claude/settings.json` under the `hooks` key.
