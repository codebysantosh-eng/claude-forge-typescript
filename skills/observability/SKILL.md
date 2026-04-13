---
name: observability
description: Deep reference for observability — structured logging, distributed tracing, metrics, alerting, error tracking, and Next.js/Node.js integration patterns.
---

# Observability Reference

Deep reference for the **architect** and **performance-profiler** agents. Logging, tracing, metrics, and alerting patterns for production TypeScript applications.

## Core Principle

**You cannot fix what you cannot see.** Every production service needs three pillars:

| Pillar | Purpose | Tool |
|--------|---------|------|
| **Logs** | What happened, in order | Pino, Winston |
| **Traces** | How a request flowed across services | OpenTelemetry |
| **Metrics** | Aggregated system health over time | Prometheus, Vercel Analytics |

## 1. Structured Logging

```typescript
// ✗ NEVER — unstructured, unsearchable, no context
console.log("User logged in");
console.log("Error:", err);
console.log(`Order ${orderId} created for user ${userId}`);

// ✓ ALWAYS — structured JSON, searchable, contextual
import pino from "pino";

const logger = pino({
  level: process.env.LOG_LEVEL ?? "info",
  formatters: {
    level: (label) => ({ level: label }),
  },
  // Pretty print in dev, JSON in prod
  transport: process.env.NODE_ENV === "development"
    ? { target: "pino-pretty", options: { colorize: true } }
    : undefined,
});

logger.info({ userId, action: "login" }, "User logged in");
logger.error({ err, orderId, userId }, "Failed to create order");
logger.warn({ endpoint: "/api/users", count: rateLimitHits }, "Rate limit approaching threshold");
```

### Log Levels

| Level | When to Use | Example |
|-------|------------|---------|
| `fatal` | App cannot continue | DB connection pool exhausted |
| `error` | Operation failed, needs attention | Payment charge failed |
| `warn` | Degraded but functional | Rate limit approaching, retry succeeded |
| `info` | Significant business events | User signed up, order placed, deploy started |
| `debug` | Diagnostic detail | SQL query timing, cache hit/miss |
| `trace` | Granular debugging | Request/response bodies, middleware chain |

### What to Log

```typescript
// ✓ Business events
logger.info({ userId, plan: "pro", amount: 2999 }, "Subscription upgraded");

// ✓ Failures with context
logger.error({ err, userId, endpoint: "/api/checkout", paymentId }, "Checkout failed");

// ✓ Performance signals
logger.info({ durationMs: 1250, query: "findManyOrders", count: 50 }, "Slow query detected");

// ✗ NEVER log these
// - Passwords, tokens, API keys, credit card numbers
// - Full request bodies with PII (email, SSN, phone)
// - Health check pings (noise)
```

### Log Sanitization

```typescript
function sanitizeForLog(obj: Record<string, unknown>): Record<string, unknown> {
  const sensitive = ["password", "token", "secret", "authorization", "cookie", "ssn", "creditCard"];
  return Object.fromEntries(
    Object.entries(obj).map(([key, value]) =>
      sensitive.some(s => key.toLowerCase().includes(s))
        ? [key, "[REDACTED]"]
        : [key, value]
    )
  );
}

logger.info(sanitizeForLog(requestBody), "Incoming request");
```

## 2. Request Correlation

The single most important debugging tool in production. Every log line for a request shares one ID.

```typescript
// src/middleware.ts — assign correlation ID at the edge
import { NextRequest, NextResponse } from "next/server";

export function middleware(request: NextRequest) {
  const requestId = request.headers.get("x-request-id") ?? crypto.randomUUID();
  const response = NextResponse.next();
  response.headers.set("x-request-id", requestId);

  // Pass to downstream via header (available in route handlers)
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-request-id", requestId);

  return NextResponse.next({ request: { headers: requestHeaders } });
}
```

```typescript
// lib/logger.ts — child logger with request context
export function createRequestLogger(requestId: string, extra?: Record<string, unknown>) {
  return logger.child({ requestId, ...extra });
}

// In route handler
export async function POST(req: NextRequest) {
  const requestId = req.headers.get("x-request-id") ?? "unknown";
  const log = createRequestLogger(requestId, { endpoint: "/api/orders" });

  log.info("Order creation started");
  // Every log line now includes requestId — searchable across all services
}
```

## 3. Distributed Tracing (OpenTelemetry)

```typescript
// instrumentation.ts (Next.js instrumentation hook)
export async function register() {
  if (process.env.NEXT_RUNTIME === "nodejs") {
    const { NodeSDK } = await import("@opentelemetry/sdk-node");
    const { getNodeAutoInstrumentations } = await import("@opentelemetry/auto-instrumentations-node");
    const { OTLPTraceExporter } = await import("@opentelemetry/exporter-trace-otlp-http");

    const sdk = new NodeSDK({
      traceExporter: new OTLPTraceExporter({
        url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT ?? "http://localhost:4318/v1/traces",
      }),
      instrumentations: [
        getNodeAutoInstrumentations({
          "@opentelemetry/instrumentation-http": { enabled: true },
          "@opentelemetry/instrumentation-fetch": { enabled: true },
        }),
      ],
      serviceName: process.env.OTEL_SERVICE_NAME ?? "my-app",
    });

    sdk.start();
  }
}
```

```typescript
// next.config.js — enable instrumentation
module.exports = {
  experimental: {
    instrumentationHook: true,
  },
};
```

### Custom Spans

```typescript
import { trace } from "@opentelemetry/api";

const tracer = trace.getTracer("my-app");

export async function processOrder(orderId: string) {
  return tracer.startActiveSpan("processOrder", async (span) => {
    span.setAttribute("order.id", orderId);

    try {
      const order = await fetchOrder(orderId);
      span.setAttribute("order.amount", order.total);

      await chargePayment(order);
      span.setAttribute("order.status", "charged");

      await sendConfirmation(order);
      span.setStatus({ code: 1 }); // OK
      return order;
    } catch (err) {
      span.setStatus({ code: 2, message: String(err) }); // ERROR
      span.recordException(err as Error);
      throw err;
    } finally {
      span.end();
    }
  });
}
```

### Tracing Backends

| Backend | Best For | Cost |
|---------|----------|------|
| **Vercel OTEL** | Vercel deployments (zero config) | Included in Pro |
| **Grafana Tempo** | Self-hosted, Grafana ecosystem | Free (self-hosted) |
| **Honeycomb** | High-cardinality debugging | Free tier available |
| **Datadog** | Full-stack APM | $$$ |
| **Jaeger** | Local development, open-source | Free |

## 4. Metrics

```typescript
// Custom metrics with OpenTelemetry
import { metrics } from "@opentelemetry/api";

const meter = metrics.getMeter("my-app");

const requestCounter = meter.createCounter("http.requests.total", {
  description: "Total HTTP requests",
});

const requestDuration = meter.createHistogram("http.request.duration_ms", {
  description: "HTTP request duration in milliseconds",
});

const activeConnections = meter.createUpDownCounter("db.connections.active", {
  description: "Active database connections",
});

// In middleware or route handler
export async function POST(req: NextRequest) {
  const start = Date.now();
  requestCounter.add(1, { method: "POST", route: "/api/orders" });

  try {
    const result = await handleOrder(req);
    requestDuration.record(Date.now() - start, { method: "POST", status: "200" });
    return result;
  } catch (err) {
    requestDuration.record(Date.now() - start, { method: "POST", status: "500" });
    throw err;
  }
}
```

### Key Metrics to Track

| Metric | Type | Alert Threshold |
|--------|------|----------------|
| Request rate (RPS) | Counter | Spike > 3x normal |
| Error rate (5xx / total) | Ratio | > 1% |
| P95 latency | Histogram | > 2s for API, > 4s for pages |
| DB connection pool usage | Gauge | > 80% capacity |
| Queue depth | Gauge | Growing without drain |
| Memory usage (RSS) | Gauge | > 80% of limit |
| Cache hit rate | Ratio | < 50% (check eviction) |

## 5. Error Tracking

```typescript
// lib/errors.ts — structured error classes
export class AppError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly statusCode: number = 500,
    public readonly context?: Record<string, unknown>
  ) {
    super(message);
    this.name = "AppError";
  }
}

export class NotFoundError extends AppError {
  constructor(resource: string, id: string) {
    super(`${resource} not found: ${id}`, "NOT_FOUND", 404, { resource, id });
  }
}

// In route handler — log with full context, return generic message
export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const user = await findUser(params.id);
    if (!user) throw new NotFoundError("User", params.id);
    return NextResponse.json(user);
  } catch (err) {
    if (err instanceof AppError) {
      logger.warn({ err, code: err.code, ...err.context }, err.message);
      return NextResponse.json({ error: err.message }, { status: err.statusCode });
    }
    // Unexpected error — log details, return generic message
    logger.error({ err, params }, "Unhandled error in GET /api/users/[id]");
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
```

### Error Tracking Services

| Service | Best For |
|---------|----------|
| **Sentry** | Full-stack error tracking with source maps, breadcrumbs, session replay |
| **Vercel Error Tracking** | Zero-config for Vercel deployments |
| **BugSnag** | Mobile + web error tracking |

```typescript
// Sentry Next.js integration
// sentry.client.config.ts
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  tracesSampleRate: process.env.NODE_ENV === "production" ? 0.1 : 1.0,
  environment: process.env.NODE_ENV,
});
```

## 6. Alerting Rules

| Alert | Condition | Severity | Action |
|-------|-----------|----------|--------|
| High error rate | 5xx > 1% for 5 min | **CRITICAL** | Page on-call |
| Slow responses | P95 > 5s for 10 min | **HIGH** | Investigate DB/external deps |
| DB pool exhausted | Active connections > 90% | **CRITICAL** | Scale or optimize queries |
| Memory leak | RSS growing > 10MB/hour | **HIGH** | Profile, check event listeners |
| Cert expiry | < 14 days | **MEDIUM** | Renew SSL certificate |
| Dependency vulnerability | CRITICAL CVE | **HIGH** | Patch and deploy |
| Queue backlog | Depth growing for > 15 min | **HIGH** | Scale workers or investigate stuck jobs |

### Alert Hygiene

- **Every alert must be actionable** — if you can't do anything, it's noise
- **Deduplicate** — group by error fingerprint, not individual occurrence
- **Escalation path** — warning → Slack, critical → PagerDuty/Opsgenie
- **Review monthly** — delete alerts nobody acted on in 30 days

## 7. Next.js Specific Patterns

### Route Handler Logging Wrapper

```typescript
// lib/api.ts — reusable wrapper with logging, timing, error handling
import { NextRequest, NextResponse } from "next/server";

type Handler = (req: NextRequest, ctx: { params: Record<string, string> }) => Promise<NextResponse>;

export function withLogging(handler: Handler): Handler {
  return async (req, ctx) => {
    const requestId = req.headers.get("x-request-id") ?? crypto.randomUUID();
    const log = createRequestLogger(requestId, {
      method: req.method,
      path: req.nextUrl.pathname,
    });
    const start = Date.now();

    try {
      log.info("Request started");
      const response = await handler(req, ctx);
      log.info({ durationMs: Date.now() - start, status: response.status }, "Request completed");
      return response;
    } catch (err) {
      log.error({ err, durationMs: Date.now() - start }, "Request failed");
      return NextResponse.json({ error: "Internal server error" }, { status: 500 });
    }
  };
}

// Usage
export const GET = withLogging(async (req) => {
  const users = await prisma.user.findMany();
  return NextResponse.json(users);
});
```

### Server Action Logging

```typescript
"use server";

export async function createOrder(prevState: unknown, formData: FormData) {
  const log = logger.child({ action: "createOrder", userId: session.userId });

  log.info("Order creation started");
  // ... validation, DB write
  log.info({ orderId: order.id, amount: order.total }, "Order created successfully");

  revalidatePath("/orders");
  redirect(`/orders/${order.id}`);
}
```

## Recommended Stack

| Layer | Local Dev | Production |
|-------|-----------|------------|
| Logging | Pino + pino-pretty | Pino → Vercel Logs / Datadog / Loki |
| Tracing | Jaeger (Docker) | Vercel OTEL / Grafana Tempo / Honeycomb |
| Metrics | Console output | Prometheus + Grafana / Vercel Analytics |
| Errors | Console | Sentry / Vercel Error Tracking |
| Alerting | N/A | PagerDuty / Opsgenie + Slack |

## Setup Checklist

- [ ] Structured logging with Pino (not console.log)
- [ ] Request correlation IDs propagated through middleware
- [ ] OpenTelemetry instrumentation enabled
- [ ] Error tracking configured (Sentry or equivalent)
- [ ] Key business metrics tracked (orders, signups, payments)
- [ ] P95 latency and error rate alerts configured
- [ ] Log sanitization — no PII or secrets in logs
- [ ] Log levels appropriate (info in prod, debug in dev)
- [ ] Dashboard with request rate, error rate, latency, DB pool
