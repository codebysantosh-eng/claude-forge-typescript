---
description: Implement features using strict test-driven development — failing tests first, minimal implementation, then refactor.
---

# /tdd

Invoke the **tdd-developer** agent to build test-first.

## The Cycle

```
RED       Write failing test that defines expected behavior
GREEN     Write minimum code to make it pass
VERIFY    Run typecheck + lint + format check + full test suite
REFACTOR  Clean up while all checks stay green
REPEAT    Until feature is complete
```

## What It Does

1. Defines interfaces and type signatures
2. Writes failing tests — verified to fail
3. Implements minimal code to pass
4. Runs full verification: `tsc --noEmit` + lint + format + full test suite
5. Refactors with all checks green
6. Verifies coverage meets targets defined in `rules/testing.md`

## Rules

- Tests BEFORE implementation — always
- One test at a time for complex features
- Test behavior, not implementation details
- Every GREEN step must pass: typecheck + lint + format + full test suite
- Errors in files you touch are your responsibility

## When to Use

- Implementing features from an approved design
- Fixing bugs (write test that reproduces it first)
- Refactoring (ensure tests exist before changing)
- Any new function, endpoint, or component

## After TDD

- `/inspect` — Review the implementation
- `/fix` — If build breaks
- `/scan` — If code touches auth/payments/user input
- `/e2e` — If the feature has a user-facing flow

## Agent

`agents/tdd-developer.md`

## Reference

See `skills/tdd-patterns/SKILL.md` for mocking strategies, test data factories, and CI integration.
