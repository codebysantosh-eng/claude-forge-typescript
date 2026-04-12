---
description: Generate, run, and maintain end-to-end tests for critical user journeys using Playwright.
---

# /e2e

Invoke the **e2e-runner** agent to create and execute E2E tests.

## What It Does

1. Identifies critical user journeys by risk priority
2. Generates Playwright tests using Page Object Model
3. Configures multi-browser execution (Chromium, Firefox, WebKit)
4. Runs tests and captures artifacts (screenshots, videos, traces)
5. Identifies and quarantines flaky tests
6. Generates CI/CD pipeline config

## When to Use

- Testing auth, checkout, onboarding, or other critical flows
- Before major releases or production deploys
- After large feature merges
- Setting up E2E testing for a new project

## Best Practices

- Use semantic locators: `getByRole()`, `getByLabel()`, `getByTestId()`
- Wait for conditions, not time: `waitForResponse()` > `waitForTimeout()`
- Page Object Model for reusable interactions
- Isolate tests — each creates its own data

## After E2E

- `/inspect` — Review if tests reveal code issues
- `/healthcheck` — Full verification suite
- `/pre-deploy` — Deployment readiness check

## Agent

`agents/e2e-runner.md`
