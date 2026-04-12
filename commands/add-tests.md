---
description: Retroactively add missing unit and integration tests to maximize coverage.
---

# /add-tests

Analyze source files, identify untested or under-tested code, and generate tests retroactively.

Accepts an optional argument: a file path, glob pattern, or "all" (default: "all").

```
/add-tests                        # scan everything
/add-tests src/routes/items.ts    # single file
/add-tests src/middleware/*.ts    # glob pattern
```

## What It Does

1. Discovers the test framework and conventions
2. Maps source files to test files and finds gaps
3. Reports a coverage gap table — waits for user confirmation
4. Generates tests matching existing project conventions
5. Runs and fixes until green
6. Reports summary

## The Phases

### Phase 1 — Discovery

1. **Identify test framework** — Read `package.json` for test deps (vitest, jest, mocha, etc.) and locate the config file. Note the test file pattern and location.
2. **Map source → test files** — List all source files matching the target (excluding tests, types, config). Check if a corresponding test file exists.
3. **Classify gaps** as: No tests / Partial / Well tested (skip)
4. **Report gap analysis** — Print summary table. Ask user to confirm before generating.

### Phase 2 — Analysis

5. **Read the source** — identify exports, routes, middleware, validators, classes.
6. **Read existing tests** (if partial) — avoid duplicating coverage.
7. **Study conventions** — read 1-2 existing test files for import style, mock patterns, setup/teardown, assertion style.

### Phase 3 — Generation

8. **Write tests** following these rules:
   - Match existing conventions exactly
   - One behavior per test with descriptive names
   - Happy path first, then errors, edges, boundaries
   - **Routes**: valid → response, invalid input → 400, unauthorized → 401, not found → 404, server error → 500
   - **Functions**: normal inputs, edge cases, error throwing
   - **Middleware**: pass-through on valid, block on invalid
   - Mock external deps using same patterns as existing tests
   - Test behavior, not implementation details
   - Skip type-only files

### Phase 4 — Validation

10. **Run new tests** — use the project's test command, scoped to new files if possible.
11. **Fix failures** — adjust the test (not source code). Re-run until green.
12. **Run full suite** — ensure no regressions.

### Phase 5 — Report

13. **Print summary** with tests added, status, and any skipped files.

## Rules

- **Do NOT modify source code** — only create/modify test files
- **Do NOT delete or modify existing passing tests**
- **Ask before proceeding** after the gap analysis
- Coverage targets defined in `rules/testing.md`
- Keep tests independent — no shared mutable state

## When to Use

- After building features without tests
- When inheriting untested code
- Before major refactors (ensure coverage first)
- During pre-production audits
- When `/healthcheck` reveals test gaps

## After add-tests

- `/inspect` — Review the generated tests for quality
- `/healthcheck` — Verify full suite passes
- `/tdd` — Switch to test-first for new features
- `/scan` — If untested code touches auth/payments
