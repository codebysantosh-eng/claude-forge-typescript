---
description: Interactive onboarding — learn what's installed, detect your project stack, and get a personalised first-step recommendation.
---

# /onboard

Welcome to Claude Forge. No agent — this is a direct onboarding walkthrough.

## Steps

Execute in order:

### 1. Detect Project Context

Read the following files if they exist (don't error if missing):
- `package.json` — identify framework (Next.js, Express, Hono, Vite, etc.) and test runner (vitest, jest, etc.)
- `CLAUDE.md` — check if project already has custom instructions
- `vitest.config.ts` / `jest.config.*` — confirm test setup
- `tsconfig.json` — confirm TypeScript

### 2. Print Toolkit Summary

Print a summary block like this (fill in actual counts from the installed directories):

```
Claude Forge — TypeScript Edition
──────────────────────────────────
  Agents    8   specialized subprocesses
  Commands  15  slash commands
  Skills     6  deep reference patterns
  Rules      5  always-on guardrails
  Hooks     10  safety automation
──────────────────────────────────
```

### 3. Show the Workflow

Print this lifecycle overview:

```
Workflow
  /explore     → map an unfamiliar codebase
  /design      → research + architecture + phased plan
  /tdd         → build features test-first
  /fix         → resolve type/build/lint errors
  /inspect     → code review (local file or PR number)
  /scan        → security audit
  /profile     → find performance bottlenecks
  /healthcheck → full verification suite (types, build, lint, tests, secrets)
  /pre-deploy  → deployment readiness checklist
  /incident    → production incident response
```

### 4. Personalised First-Step Recommendation

Based on what was detected in Step 1, recommend ONE command to run next:

| Situation | Recommendation |
|-----------|---------------|
| No `CLAUDE.md` found | Run `/explore` — it will map the codebase and generate a CLAUDE.md |
| Has `CLAUDE.md` but no tests | Run `/add-tests` — retroactively add coverage to existing code |
| Has tests but hasn't reviewed architecture | Run `/design` — research and plan before building |
| Active TODO / known bug to fix | Run `/tdd` — implement with tests first |
| Pre-existing codebase, unknown quality | Run `/inspect` — get a ranked list of issues |
| About to deploy | Run `/pre-deploy` — verify everything is ready |
| Just exploring | Run `/healthcheck` — see the current state of the project |

Print the recommendation clearly:

```
Recommended first command for your project: /explore
Reason: No CLAUDE.md found — map the codebase first so every future command
        has accurate context.
```

### 5. Active Hooks

Print a brief summary of what the installed hooks do automatically:

```
Active Hooks (run automatically — no action needed)
  PreToolUse   Blocks secrets committed to git
  PreToolUse   Warns before deleting files outside build/dist/tmp
  PreToolUse   Flags SQL queries missing WHERE clauses
  PostToolUse  Reminds to run format:check after editing source files
  PostToolUse  Suggests running tests after editing test files
  Stop         Prints a session summary when Claude Code exits
  (+ 4 more — see hooks/README.md for full list)
```

### 6. Invite First Action

End with:

```
You're set up. Type a command above to begin, or ask a question about your
codebase and I'll help from there.
```

## Arguments

$ARGUMENTS: *(none)*
