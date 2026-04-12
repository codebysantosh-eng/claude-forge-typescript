---
description: Restructure existing code safely — verify tests exist, refactor with all checks green.
argument-hint: "[target file or description]"
---

# /refactor

Restructure existing code without changing behavior. No agent — this is a direct workflow for brownfield work.

## Prerequisites

Before refactoring, verify a safety net exists:

```bash
# 1. Check test coverage for the target code
npx vitest --coverage --reporter=json 2>/dev/null || npx jest --coverage --json 2>/dev/null

# 2. Run current tests — they MUST pass before any changes
npm test

# 3. Type check
npx tsc --noEmit
```

**If coverage is low**: Run `/add-tests` first. Never refactor untested code.

## Process

1. **Verify tests pass** — run full suite, confirm green
2. **Make one structural change** — extract function, move file, rename, split module
3. **Run checks** — `npx tsc --noEmit && npm run lint && npm test`
4. **Commit** — small, atomic commit describing the structural change
5. **Repeat** — next structural change, verify, commit

## What This Is For

- Moving functions/components to better locations
- Extracting shared utilities from duplicated code
- Splitting large files (>800 lines)
- Renaming for clarity
- Reducing nesting depth
- Simplifying complex conditionals

## What This Is NOT For

- Adding features — use `/tdd`
- Fixing bugs — use `/tdd` (reproduce with test first)
- Fixing build errors — use `/fix`
- Architecture changes — use `/design` first
- Performance optimization — use `/profile` first

## Rules

1. **Tests must exist before you start** — no refactoring in the dark
2. **Behavior must not change** — same inputs, same outputs
3. **One change at a time** — extract, verify, commit. Don't batch.
4. **All checks green after every change** — types, lint, tests
5. **Stop if tests break** — fix the refactor, not the tests (unless test was testing implementation details)

## Arguments

$ARGUMENTS: file path, component name, or description of what to restructure
