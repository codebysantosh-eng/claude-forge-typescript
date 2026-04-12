---
name: security-checklist
description: Deep reference for security scanning — secrets, input validation, injection, auth, token storage, XSS, CSRF, CORS, rate limiting, data protection, dependencies, headers, cloud security, and security testing patterns.
---

# Security Checklist Reference

Deep reference for the **security-scanner** agent. Checklists, code patterns, and verification commands.

## 1. Secrets Management

```typescript
// ✗ NEVER
const stripe = new Stripe("sk_live_abc123");

// ✓ ALWAYS
const key = process.env.STRIPE_SECRET_KEY;
if (!key) throw new Error("STRIPE_SECRET_KEY required");
const stripe = new Stripe(key);
```

**Verification**:
```bash
grep -rn "\b\(api[_-]\?key\|secret[_-]\?key\|password\|token\|credentials\)\b\s*[:=]" --include="*.{ts,tsx,js,jsx}" src/ lib/ app/
grep -q ".env" .gitignore && echo "OK" || echo "MISSING: .env not in .gitignore"
```

- [ ] No hardcoded secrets in source
- [ ] `.env` in `.gitignore`
- [ ] `.env.example` with placeholder values
- [ ] Required env vars validated at startup (fail fast)
- [ ] Secrets never in logs or error messages
- [ ] No `NEXT_PUBLIC_` prefix on server-only secrets

## 2. API Token Storage (CRITICAL for SPAs)

```typescript
// ✗ NEVER — XSS can steal tokens from localStorage
localStorage.setItem("token", jwt);
const token = localStorage.getItem("token");

// ✗ NEVER — sessionStorage has the same XSS risk
sessionStorage.setItem("token", jwt);

// ✓ ALWAYS — httpOnly cookies (not accessible via JavaScript)
res.cookie("session", token, {
  httpOnly: true,      // Cannot be read by document.cookie
  secure: true,        // HTTPS only
  sameSite: "lax",     // CSRF protection
  maxAge: 3600000,     // 1 hour
  path: "/",
});

// ✓ Token refresh flow
// 1. Short-lived access token (15min) in httpOnly cookie
// 2. Refresh token (7d) in httpOnly cookie with /api/auth/refresh path
// 3. Client calls /api/auth/refresh when 401 received
// 4. Server validates refresh token, issues new access token
```

**Verification**:
```bash
grep -rn "localStorage\.\(setItem\|getItem\).*\(token\|jwt\|session\|auth\)" --include="*.{ts,tsx,js,jsx}" src/
```

- [ ] No tokens in localStorage or sessionStorage
- [ ] Auth tokens in httpOnly + Secure + SameSite cookies
- [ ] Short-lived access tokens (15min-1hr)
- [ ] Refresh token rotation on use

## 3. Input Validation

```typescript
import { z } from "zod";

const CreateUserSchema = z.object({
  email: z.string().email().max(255),
  name: z.string().min(1).max(100).trim(),
  role: z.enum(["user", "admin"]),
});

app.post("/users", (req, res) => {
  const data = CreateUserSchema.parse(req.body);
  return createUser(data);
});
```

- [ ] Every API endpoint and Server Action validates input with Zod schema
- [ ] File uploads check size, type, and magic bytes
- [ ] No user input passed directly to SQL, shell, file paths, or HTML

## 4. Injection Prevention

| Type | Vector | Prevention |
|------|--------|-----------|
| **SQL** | String concatenation | Parameterized queries, Prisma |
| **Command** | `exec(userInput)` | `execFile` with args array |
| **XSS** | `innerHTML = userInput` | Framework escaping, DOMPurify, CSP |
| **Path traversal** | `readFile(userPath)` | `path.resolve()` + validate |
| **SSRF** | `fetch(userUrl)` server-side | Whitelist domains |

## 5. Authentication

```typescript
import bcrypt from "bcrypt";

const hash = await bcrypt.hash(password, 12);
const valid = await bcrypt.compare(input, hash);

// JWT with proper claims
const token = jwt.sign(
  { sub: user.id, role: user.role },
  process.env.JWT_SECRET!,
  { expiresIn: "1h", audience: "myapp", issuer: "myapp" }
);
```

- [ ] Passwords hashed with bcrypt (cost 12+) or argon2
- [ ] JWT has expiry, audience, and issuer claims
- [ ] Token refresh mechanism for long sessions
- [ ] Logout invalidates session server-side

## 6. Authorization

```typescript
// ✗ Only checks auth, not authz
app.get("/api/users/:id", requireAuth, async (req, res) => {
  const user = await db.users.findById(req.params.id);
  return res.json(user); // Any user can see ANY user
});

// ✓ Checks authorization
app.get("/api/users/:id", requireAuth, async (req, res) => {
  if (req.user.id !== req.params.id && req.user.role !== "admin") {
    return res.status(403).json({ error: "Forbidden" });
  }
  const user = await db.users.findById(req.params.id);
  return res.json(user);
});
```

- [ ] Every endpoint checks authentication AND authorization
- [ ] Every Server Action validates the session at the top
- [ ] Row Level Security for Prisma/Supabase
- [ ] Never rely on client-side authorization

## 7. CORS Configuration

```typescript
// ✗ DANGEROUS — allows any origin with credentials
app.use(cors({ origin: true, credentials: true }));
app.use(cors({ origin: "*" })); // No credentials, but still risky

// ✓ Whitelist specific origins
const ALLOWED_ORIGINS = [
  "https://myapp.com",
  "https://staging.myapp.com",
  process.env.NODE_ENV === "development" && "http://localhost:3000",
].filter(Boolean);

app.use(cors({
  origin: ALLOWED_ORIGINS,
  credentials: true,
  methods: ["GET", "POST", "PATCH", "DELETE"],
}));

// ✓ Next.js middleware CORS
export function middleware(request: NextRequest) {
  const origin = request.headers.get("origin");
  if (origin && !ALLOWED_ORIGINS.includes(origin)) {
    return new NextResponse(null, { status: 403 });
  }
}
```

- [ ] CORS restricted to known origins (never `*` with credentials)
- [ ] Credentials only from whitelisted origins
- [ ] Methods restricted to what's needed

## 8. XSS Prevention

```tsx
// React auto-escapes — SAFE:
<div>{userComment}</div>

// ✗ DANGEROUS:
<div dangerouslySetInnerHTML={{ __html: userComment }} />

// ✓ If you MUST render HTML:
import DOMPurify from "dompurify";
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(userComment) }} />
```

- [ ] No `dangerouslySetInnerHTML` without DOMPurify
- [ ] CSP headers configured
- [ ] No `eval()` or `Function()` with user input

## 9. Rate Limiting

### Express

```typescript
import rateLimit from "express-rate-limit";

app.use("/api/", rateLimit({ windowMs: 15 * 60 * 1000, max: 100 }));
app.use("/api/auth/", rateLimit({ windowMs: 15 * 60 * 1000, max: 5 }));
```

### Next.js (App Router Middleware)

**WARNING**: In-memory rate limiting (`Map`, global variables) does NOT work on Vercel or any serverless/edge deployment — each invocation gets a fresh memory space. Use Redis-backed solutions for production.

```typescript
// src/middleware.ts — PRODUCTION: Redis-backed rate limiting
import { NextRequest, NextResponse } from "next/server";
import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";

const ratelimit = new Ratelimit({
  redis: Redis.fromEnv(),
  limiter: Ratelimit.slidingWindow(100, "15 m"),
});

const authRatelimit = new Ratelimit({
  redis: Redis.fromEnv(),
  limiter: Ratelimit.slidingWindow(5, "15 m"),
  prefix: "ratelimit:auth",
});

export async function middleware(request: NextRequest) {
  if (!request.nextUrl.pathname.startsWith("/api/")) {
    return NextResponse.next();
  }

  // Use request.ip (Vercel) or validated x-forwarded-for (last entry only)
  const forwarded = request.headers.get("x-forwarded-for");
  const ip = request.ip ?? (forwarded ? forwarded.split(",").pop()?.trim() : null) ?? "anonymous";

  const limiter = request.nextUrl.pathname.startsWith("/api/auth/")
    ? authRatelimit
    : ratelimit;

  const { success, limit, remaining, reset } = await limiter.limit(ip);

  if (!success) {
    return NextResponse.json(
      { error: "Too many requests" },
      {
        status: 429,
        headers: {
          "X-RateLimit-Limit": String(limit),
          "X-RateLimit-Remaining": String(remaining),
          "Retry-After": String(Math.ceil((reset - Date.now()) / 1000)),
        },
      }
    );
  }

  return NextResponse.next();
}

export const config = { matcher: "/api/:path*" };
```

**Local development only** (not for production):
```typescript
// Simple in-memory limiter for local dev — DO NOT deploy this
const rateLimitMap = new Map<string, { count: number; lastReset: number }>();
// ... (works only in long-lived Node.js process, NOT serverless/edge)
```

- [ ] All public endpoints rate-limited
- [ ] Auth endpoints: 5 attempts per 15 minutes
- [ ] Expensive operations: tight limits
- [ ] Production uses Redis-backed rate limiting (Upstash, Redis, etc.)
- [ ] IP resolution uses `request.ip` or validated proxy chain — never raw `x-forwarded-for`

## 10. CSRF Protection

Server Actions get automatic CSRF protection via origin checking in Next.js. But custom `/api/` route handlers using cookie-based auth do **NOT** get this automatically.

```typescript
// ✓ Server Actions — CSRF protected by framework (origin header check)
"use server";
export async function updateProfile(formData: FormData) { /* safe */ }

// ✗ API route with cookie auth — NO automatic CSRF protection
// app/api/users/route.ts
export async function POST(req: NextRequest) {
  const session = req.cookies.get("session"); // Cookie sent automatically by browser
  // An attacker's site can trigger this POST via form submission
}

// ✓ API route with CSRF protection — validate origin header
export async function POST(req: NextRequest) {
  const origin = req.headers.get("origin");
  const host = req.headers.get("host");
  if (!origin || new URL(origin).host !== host) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }
  // ... proceed with cookie auth
}
```

**CSRF Decision Matrix:**

| Auth Method | Endpoint Type | CSRF Risk | Protection |
|-------------|--------------|-----------|------------|
| httpOnly cookie | Server Action | None | Framework handles it |
| httpOnly cookie | `/api/` route (GET) | None | GET should be idempotent |
| httpOnly cookie | `/api/` route (POST/PUT/DELETE) | **HIGH** | Validate `Origin` header or use CSRF token |
| Bearer token (header) | Any | None | Token must be explicitly attached |

- [ ] Server Actions used for mutations where possible (automatic CSRF)
- [ ] `/api/` routes with cookie auth validate `Origin` header
- [ ] `SameSite=Lax` on auth cookies (blocks cross-site POST from `<form>`)
- [ ] GET endpoints are idempotent (no side effects)

## 11. Security Headers

```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Content-Security-Policy: default-src 'self'
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: camera=(), microphone=(), geolocation=()
```

```typescript
// next.config.js — configure security headers
const securityHeaders = [
  { key: "Strict-Transport-Security", value: "max-age=31536000; includeSubDomains; preload" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
];

module.exports = {
  async headers() {
    return [{ source: "/(.*)", headers: securityHeaders }];
  },
};
```

## 12. Dependencies & Supply Chain

```bash
npm audit --production
npm ci  # Use ci, not install — respects lockfile exactly
```

- [ ] No known CRITICAL vulnerabilities
- [ ] Lock files committed (`package-lock.json` or `pnpm-lock.yaml`)
- [ ] Use `npm ci` in CI (not `npm install`) — prevents lockfile drift
- [ ] Automated scanning in CI (Dependabot, npm audit)
- [ ] Pin GitHub Actions to commit SHA (not tags): `uses: actions/checkout@<sha>`
- [ ] Verify no private package name squatting (check npm for your `@org/` scope)

## 13. Prototype Pollution

```typescript
// ✗ DANGEROUS — attacker can pollute Object prototype via __proto__
const config = Object.assign({}, userInput);
const merged = { ...defaults, ...userInput };

// ✓ SAFE — validate with Zod before merging
const ConfigSchema = z.object({ theme: z.string(), lang: z.string() });
const config = ConfigSchema.parse(userInput);
```

- [ ] No `Object.assign` or spread with raw user input
- [ ] All user JSON validated with Zod schema before merging into app state

## 14. Secrets in Git History (Emergency)

If a secret has been committed to git history:

1. **Rotate the secret IMMEDIATELY** — new value in secret manager
2. **Invalidate sessions** using the compromised secret
3. **Remove from history**:
   ```bash
   # Option A: git-filter-repo (recommended)
   pip install git-filter-repo
   git filter-repo --invert-paths --path <file-with-secret>
   
   # Option B: BFG Repo Cleaner
   bfg --replace-text passwords.txt
   git reflog expire --expire=now --all && git gc --prune=now
   ```
4. **Force push** — the one justified use of `git push --force`
5. **Check GitHub** → Settings → Code security → Secret scanning alerts
6. **Audit access logs** during exposure window

## 15. Cloud & Infrastructure Security

- [ ] IAM follows least privilege — no `*:*` policies
- [ ] Database not publicly accessible
- [ ] Secrets in cloud secret manager (Vercel Secrets, AWS SSM)
- [ ] CI/CD uses OIDC (not long-lived keys)
- [ ] Backups configured and tested
- [ ] SSL/TLS in strict mode

## Pre-Deployment Checklist

1. [ ] No hardcoded secrets
2. [ ] All inputs schema-validated (Zod)
3. [ ] No injection vectors
4. [ ] Auth on every endpoint and Server Action
5. [ ] Authorization at resource level
6. [ ] Tokens in httpOnly cookies (not localStorage)
7. [ ] CORS restricted to known origins
8. [ ] Rate limiting on public + expensive endpoints
9. [ ] Security headers configured
10. [ ] Dependencies audited, supply chain secured
11. [ ] No `NEXT_PUBLIC_` on server secrets
12. [ ] CSRF protection on `/api/` routes using cookie auth
13. [ ] No prototype pollution vectors (user input validated before merge)
