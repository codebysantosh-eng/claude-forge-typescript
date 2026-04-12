---
description: Review code for bugs, security, performance, and maintainability. Works on local changes or GitHub PRs with full review pipeline.
argument-hint: [pr-number | pr-url | blank for local]
---

# /inspect

Invoke the **code-inspector** agent to review code.

**Input**: $ARGUMENTS

## Mode Selection

If `$ARGUMENTS` contains a PR number, PR URL, or `--pr` → **PR Inspection** (full 7-phase pipeline)
Otherwise → **Local Inspection** (uncommitted changes)

## What It Does

**Local**: Reads changed files, applies severity-ranked checklist, reports findings.

**PR**: Fetches PR, builds context, deep reviews across 7 categories (correctness, type safety, patterns, security, performance, completeness, maintainability), runs validation, publishes verdict to GitHub.

## Verdicts

| Condition | Decision |
|-----------|----------|
| Zero CRITICAL/HIGH | **APPROVE** |
| Only MEDIUM/LOW | **APPROVE with comments** |
| Any HIGH | **REQUEST CHANGES** |
| Any CRITICAL | **BLOCK** |

## After Inspection

- `/scan` — Deep security audit for sensitive code
- `/fix` — Fix issues found
- `/healthcheck` — Final verification before merge

## Agent

`agents/code-inspector.md`
