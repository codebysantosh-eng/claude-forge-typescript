# Claude Forge — TypeScript Edition

## Project Overview

A complete Claude Code development system for TypeScript, React, and Next.js projects — 8 agents, 13 commands, 10 hooks, 5 skills, and 5 rules covering the full lifecycle from research to deployment.

## Structure

- `agents/` — 8 specialized agents (markdown with YAML frontmatter), each with "When to Engage" and "When NOT to Engage" sections
- `commands/` — 13 slash commands (markdown with description frontmatter)
- `hooks/` — 10 safety hooks (JSON) + documentation
- `skills/` — 5 deep reference patterns for agents to pull from
- `rules/` — 5 always-on guardrails
- `install.sh` — Idempotent installer (symlink or copy mode)
- `uninstall.sh` — Clean removal of all forge components

## Agent → Command Map

| Agent | Command | Role |
|-------|---------|------|
| architect | `/design` | Research + design + plan |
| tdd-developer | `/tdd` | Build test-first |
| error-resolver | `/fix` | Fix build errors |
| code-inspector | `/inspect` | Review code (local + PR) |
| security-scanner | `/scan` | Security audit |
| e2e-runner | `/e2e` | E2E tests (Playwright) |
| performance-profiler | `/profile` | Performance profiling |
| code-explorer | `/explore` | Map codebases |
| *(none)* | `/refactor` | Restructure code safely |
| *(none)* | `/add-tests` | Retroactive test coverage |
| *(none)* | `/learn` | Extract patterns |
| *(none)* | `/healthcheck` | Verification suite |
| *(none)* | `/pre-deploy` | Deploy readiness |

## Conventions

- File naming: lowercase with hyphens (utilities), PascalCase (components)
- Agents: YAML frontmatter with name, description, tools, model
- Commands: description frontmatter, $ARGUMENTS for input
- Skills: SKILL.md in named subdirectory
- Rules: short guardrails that reference skills for detail
- Coverage targets: authoritative source is `rules/testing.md`
- Every agent has "When to Engage" and "When NOT to Engage" sections to prevent token waste
