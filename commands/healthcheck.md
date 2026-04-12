---
description: Run all verification checks — build, types, lint, format, tests, secrets, console.log. Stops on first failure.
---

# /healthcheck

Run comprehensive verification. No agent — this is a direct check pipeline.

## Pipeline

Execute in order, stop on critical failure:

| Step | Check | Command | Pass |
|------|-------|---------|------|
| 1 | **Type check** | `npx tsc --noEmit` | No type errors |
| 2 | **Build** | `npm run build` | Exit code 0 |
| 3 | **Lint** | `npm run lint` | No errors (warnings OK) |
| 4 | **Format** | `npx prettier --check .` | All files formatted |
| 5 | **Tests** | `npm test` | All passing, coverage reported |
| 6 | **Secrets scan** | grep for hardcoded secrets | None in source |
| 7 | **Console.log** | grep source files | None (test files OK) |
| 8 | **Git status** | `git status` | Show uncommitted changes |

If types or build fail → report errors and STOP.

## Modes

| Mode | Flag | Checks |
|------|------|--------|
| Quick | `/healthcheck quick` | Types + build only |
| Full | `/healthcheck` | All 8 (default) |

## On Failure

| Failure | Suggested Fix |
|---------|--------------|
| Type/build errors | `/fix` |
| Format issues | `npx prettier --write .` to auto-fix |
| Low coverage | `/tdd` or `/add-tests` |
| Secrets found | Move to env vars immediately |
| Console.log | Replace with structured logger |

## Arguments

$ARGUMENTS: `quick` | `full`

**Note**: For pre-PR security scanning, use `/scan` separately. For deployment readiness, use `/pre-deploy`.
