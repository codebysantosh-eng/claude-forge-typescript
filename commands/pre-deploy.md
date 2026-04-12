---
description: Pre-deployment readiness check — CI status, migrations, env vars, dependencies, rollback plan.
---

# /pre-deploy

Run deployment readiness validation. No agent — this is a direct checklist.

## Checklist

### 1. CI/CD Status
```bash
gh run list --branch main --limit 5
```
- [ ] All workflows green on deploy branch

### 2. Code Quality
- [ ] `/healthcheck` passes (build, types, lint, tests, secrets)
- [ ] Test coverage meets targets in `rules/testing.md`

### 3. Database Migrations
```bash
git diff main...HEAD --name-only | grep -i "migration\|schema\|prisma"
```
- [ ] All Prisma migrations committed and tested
- [ ] `npx prisma migrate deploy` ready for production
- [ ] Backwards-compatible (or deploy coordinated)

### 4. Environment Variables
```bash
grep -rn "process.env\." --include="*.{ts,tsx,js,jsx}" src/ lib/ app/ | grep -oP 'process\.env\.[A-Z_]+' | sort -u
```
- [ ] New env vars documented in `.env.example`
- [ ] New env vars set in production (Vercel / hosting provider)
- [ ] No `NEXT_PUBLIC_` prefix on server-only secrets
- [ ] No removed vars still referenced in code

### 5. Dependencies
```bash
git diff main...HEAD -- package.json
npm audit --production 2>/dev/null
```
- [ ] New deps reviewed and intentional
- [ ] No known security vulnerabilities
- [ ] `package-lock.json` committed

### 6. Rollback Plan
- [ ] Previous version tagged and deployable
- [ ] Prisma migrations reversible
- [ ] Feature flags can disable new features without rollback

## Output

```
Deployment Readiness
───────────────────────────────
CI/CD        ✓ All green
Healthcheck  ✓ PASS
Migrations   ✓ 1 new, rollback exists
Env Vars     ⚠ STRIPE_WEBHOOK_SECRET — confirm set in prod
Dependencies ✓ Clean audit
Rollback     ✓ v1.2.3 tagged
───────────────────────────────
Status: READY — after confirming env var
```

## When to Use

- Before any production deployment
- Before cutting a release tag
- After merging a large feature to main
