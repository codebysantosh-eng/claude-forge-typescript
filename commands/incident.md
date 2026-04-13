---
description: Production incident response — diagnose, mitigate, fix, and document with structured runbook.
argument-hint: "[error message | symptom | service name]"
---

# /incident

Structured production incident response. No agent — this is a direct diagnostic workflow.

## Triage (first 5 minutes)

### 1. Assess Severity

| Severity | Criteria | Response |
|----------|----------|----------|
| **SEV-1** | Service down, data loss, security breach | All hands, external comms |
| **SEV-2** | Major feature broken, significant user impact | On-call + backup |
| **SEV-3** | Degraded performance, partial outage | On-call investigates |
| **SEV-4** | Minor issue, workaround available | Next business day |

### 2. Gather Signals

```bash
# Recent deploys — what changed?
gh run list --limit 10
git log --oneline -10 --format="%h %s (%cr)"

# CI status — is main green?
gh run list --branch main --limit 3

# Recent commits to main
git log main --oneline -10 --since="24 hours ago"

# Check for open incidents or related issues
gh issue list --label "bug" --state open --limit 10
```

### 3. Check Application Health

```bash
# Is the app responding?
curl -s -o /dev/null -w "%{http_code} %{time_total}s" https://YOUR_APP_URL/api/health

# Check error rates (Vercel)
# vercel logs --since 1h | grep -c "ERROR"

# Database connectivity
# npx prisma db execute --stdin <<< "SELECT 1" 2>&1
```

## Diagnose

### 4. Search Logs

```bash
# Vercel logs (last hour)
# vercel logs --since 1h --output json | jq 'select(.level == "error")'

# Local reproduction
npm run dev
# Hit the failing endpoint / reproduce the user journey
```

### 5. Narrow the Cause

| Symptom | Likely Cause | Check |
|---------|-------------|-------|
| 500 errors spiked | Bad deploy, DB issue | `git log`, DB connection count |
| Timeout errors | Slow query, external dep down | DB slow query log, third-party status pages |
| Memory OOM | Memory leak, unbounded cache | RSS metrics, heap snapshot |
| Connection refused | DB pool exhausted, service down | Connection pool metrics, `pg_stat_activity` |
| Auth failures | Token expired, secret rotated | Check secret manager, JWT expiry |
| Partial outage | One region/pod unhealthy | Health check per-region, pod logs |

### 6. Check Dependencies

```bash
# Stripe status
curl -s https://status.stripe.com/api/v2/status.json | jq '.status'

# AWS status
curl -s https://health.aws.amazon.com/health/status

# Vercel status
curl -s https://www.vercel-status.com/api/v2/status.json | jq '.status'

# Database (if accessible)
# SELECT count(*) FROM pg_stat_activity WHERE state = 'active';
# SELECT * FROM pg_stat_activity WHERE state = 'active' AND query_start < now() - interval '30 seconds';
```

## Mitigate

### 7. Decide: Fix Forward or Rollback

| Condition | Action |
|-----------|--------|
| Cause is clear, fix is small | Fix forward — deploy hotfix |
| Cause is unclear | Rollback to last known good |
| Data corruption risk | Rollback + DB point-in-time restore |
| Security breach | Rotate secrets + rollback + audit |

### 8. Rollback Checklist

```bash
# Find last known good deploy
gh run list --branch main --status success --limit 5

# Revert to previous commit
git revert HEAD --no-edit
git push origin main

# Or rollback via Vercel
# vercel rollback

# If DB migration was involved — check if migration is backwards-compatible
# If not, deploy migration rollback FIRST, then code rollback
```

### 9. Hotfix Checklist

```bash
# Create hotfix branch
git checkout -b fix/incident-$(date +%Y%m%d) main

# Make the fix — minimal change
# Run verification
npx tsc --noEmit && npm run lint && npm test

# Push and deploy
git push -u origin fix/incident-$(date +%Y%m%d)
gh pr create --title "fix: [incident description]" --body "SEV-X incident hotfix" --base main
```

## Resolve

### 10. Verify Recovery

```bash
# Confirm error rate is back to normal
# Check health endpoint
curl -s -o /dev/null -w "%{http_code}" https://YOUR_APP_URL/api/health

# Monitor for 15 minutes before declaring resolved
```

### 11. Communicate

| Audience | Channel | Template |
|----------|---------|----------|
| Team | Slack | "SEV-X resolved. Cause: [X]. Fix: [Y]. Monitoring." |
| Users (if impacted) | Status page / email | "Issue resolved. [Service] is operating normally." |
| Management (SEV-1/2) | Email / Slack | "Incident resolved. Post-mortem scheduled for [date]." |

## Post-Mortem

### 12. Write Post-Mortem (within 48 hours)

```markdown
# Post-Mortem: [Incident Title]

**Date**: YYYY-MM-DD
**Duration**: HH:MM start → HH:MM resolved (X minutes)
**Severity**: SEV-X
**Author**: [name]

## Summary
[1-2 sentences: what happened, who was impacted, how long]

## Timeline
| Time | Event |
|------|-------|
| HH:MM | First alert / user report |
| HH:MM | On-call acknowledged |
| HH:MM | Root cause identified |
| HH:MM | Fix deployed |
| HH:MM | Monitoring confirmed recovery |

## Root Cause
[What actually broke and why. Be specific — "the DB connection pool was exhausted
because the new query in PR #123 held connections for 30s instead of 500ms"]

## What Went Well
- [Detection was fast — alert fired within 2 minutes]
- [Rollback was clean — no data loss]

## What Went Wrong
- [No alert for connection pool usage]
- [Staging didn't catch it — different pool size]

## Action Items
| Action | Owner | Deadline | Ticket |
|--------|-------|----------|--------|
| Add DB pool usage alert | @name | YYYY-MM-DD | #123 |
| Match staging pool config to prod | @name | YYYY-MM-DD | #124 |
| Add integration test for query timeout | @name | YYYY-MM-DD | #125 |

## Lessons Learned
[What systemic change prevents this class of incident]
```

## Rules

1. **Mitigate first, diagnose second** — restore service before finding root cause
2. **Communicate early and often** — silence is worse than "we're investigating"
3. **No blame** — post-mortems are about systems, not people
4. **Every SEV-1/2 gets a post-mortem** — within 48 hours, with action items
5. **Action items have owners and deadlines** — or they won't happen

## Arguments

$ARGUMENTS: error message, symptom description, or service name to investigate
