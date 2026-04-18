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

## 8. OTel — Context Propagation

Traces only work across service boundaries if the trace context (trace ID + span ID) travels with the request. OTel handles this via W3C `traceparent` headers automatically with auto-instrumentation, but you need to propagate manually in edge cases.

```typescript
// Propagating context through a fetch call manually
import { context, propagation, trace } from "@opentelemetry/api";

async function callDownstreamService(orderId: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };

  // Inject current trace context into outgoing headers
  propagation.inject(context.active(), headers);

  const response = await fetch("https://payments-service/charge", {
    method: "POST",
    headers,
    body: JSON.stringify({ orderId }),
  });

  return response.json();
}
```

```typescript
// Extracting context from an incoming request (e.g. Hono middleware)
import { propagation, context, trace } from "@opentelemetry/api";

app.use("*", async (c, next) => {
  const extractedContext = propagation.extract(context.active(), {
    get: (carrier, key) => c.req.header(key),
    keys: () => Object.keys(c.req.raw.headers),
  });

  return context.with(extractedContext, () => next());
});
```

### Baggage — Cross-Service Attributes

Baggage lets you attach key-value pairs to a trace context so downstream services can read them without re-fetching from a database.

```typescript
import { propagation, context, baggageEntryMetadataFromString } from "@opentelemetry/api";

// Attach at the entry point
const baggage = propagation.createBaggage({
  "user.id": { value: userId },
  "user.plan": { value: "pro", metadata: baggageEntryMetadataFromString("cached") },
});
const ctx = propagation.setBaggage(context.active(), baggage);

// Read anywhere downstream (same process or across services)
const bag = propagation.getBaggage(context.active());
const plan = bag?.getEntry("user.plan")?.value; // "pro"
```

## 9. OTel — Sampling Strategies

Never trace 100% of requests in production — the volume is too high and most traces are uninteresting. Sample strategically.

```typescript
// instrumentation.ts — production-ready sampling config
import { NodeSDK } from "@opentelemetry/sdk-node";
import {
  ParentBasedSampler,
  TraceIdRatioBased,
  AlwaysOnSampler,
} from "@opentelemetry/sdk-trace-base";

const sampler =
  process.env.NODE_ENV === "production"
    ? new ParentBasedSampler({
        // Sample 10% of new traces; always follow parent's decision
        root: new TraceIdRatioBased(0.1),
      })
    : new AlwaysOnSampler(); // 100% in dev

const sdk = new NodeSDK({
  sampler,
  // ... rest of config
});
```

### Tail-based sampling (recommended for production)

Head-based sampling (above) decides at the start — you may drop a slow request. Tail-based sampling decides *after* the trace completes, keeping 100% of errors and slow requests:

```typescript
// Use OpenTelemetry Collector with tail sampling processor
// otel-collector-config.yaml
//
// processors:
//   tail_sampling:
//     decision_wait: 10s
//     policies:
//       - name: keep-errors
//         type: status_code
//         status_code: { status_codes: [ERROR] }
//       - name: keep-slow
//         type: latency
//         latency: { threshold_ms: 2000 }
//       - name: sample-rest
//         type: probabilistic
//         probabilistic: { sampling_percentage: 5 }
```

| Strategy | Sample | Keep |
|----------|--------|------|
| Head ratio (10%) | 10% at start | Random — may drop errors |
| Parent-based | Follows caller | Consistent across services |
| Tail-based | After complete | 100% errors + slow, sample rest |

## 10. OTel — Database Span Instrumentation

Auto-instrumentation covers most cases, but explicit spans add business context that generic DB spans don't have.

```typescript
import { trace, SpanStatusCode } from "@opentelemetry/api";

const tracer = trace.getTracer("db-layer");

// Wrap Prisma calls with named spans
export async function findUserWithOrders(userId: string) {
  return tracer.startActiveSpan("db.user.findWithOrders", async (span) => {
    span.setAttributes({
      "db.system": "postgresql",
      "db.operation": "SELECT",
      "db.table": "users,orders",
      "app.user_id": userId,
    });

    try {
      const user = await prisma.user.findUnique({
        where: { id: userId },
        include: { orders: { take: 10, orderBy: { createdAt: "desc" } } },
      });

      span.setAttributes({
        "app.result.found": user !== null,
        "app.result.order_count": user?.orders.length ?? 0,
      });
      span.setStatus({ code: SpanStatusCode.OK });
      return user;
    } catch (err) {
      span.setStatus({ code: SpanStatusCode.ERROR, message: String(err) });
      span.recordException(err as Error);
      throw err;
    } finally {
      span.end();
    }
  });
}
```

### Prisma query events for slow query detection

```typescript
// src/db/client.ts
import { PrismaClient } from "@prisma/client";
import { logger } from "../lib/logger";

const prisma = new PrismaClient({
  log: [{ emit: "event", level: "query" }],
});

prisma.$on("query", (e) => {
  if (e.duration > 200) {
    logger.warn(
      { durationMs: e.duration, query: e.query, params: e.params },
      "Slow Prisma query"
    );
  }
});

export { prisma };
```

## 11. Hono Middleware — Logging + Tracing

```typescript
// src/middleware/observability.ts
import type { MiddlewareHandler } from "hono";
import { trace, SpanStatusCode, context, propagation } from "@opentelemetry/api";
import { logger } from "../lib/logger";

const tracer = trace.getTracer("hono-api");

export const observabilityMiddleware: MiddlewareHandler = async (c, next) => {
  const requestId = c.req.header("x-request-id") ?? crypto.randomUUID();
  const log = logger.child({
    requestId,
    method: c.req.method,
    path: c.req.path,
  });

  c.set("requestId", requestId);
  c.set("log", log);

  // Extract OTel context from incoming headers
  const extractedCtx = propagation.extract(context.active(), {
    get: (_, key) => c.req.header(key),
    keys: () => [],
  });

  return context.with(extractedCtx, () =>
    tracer.startActiveSpan(`${c.req.method} ${c.req.path}`, async (span) => {
      span.setAttributes({
        "http.method": c.req.method,
        "http.route": c.req.path,
        "http.request_id": requestId,
      });

      const start = Date.now();
      log.info("Request started");

      try {
        await next();
        const status = c.res.status;
        span.setAttributes({ "http.status_code": status });
        span.setStatus({ code: status >= 500 ? SpanStatusCode.ERROR : SpanStatusCode.OK });
        log.info({ durationMs: Date.now() - start, status }, "Request completed");
      } catch (err) {
        span.setStatus({ code: SpanStatusCode.ERROR, message: String(err) });
        span.recordException(err as Error);
        log.error({ err, durationMs: Date.now() - start }, "Request failed");
        throw err;
      } finally {
        c.header("x-request-id", requestId);
        span.end();
      }
    })
  );
};
```

```typescript
// src/app.ts — mount once, covers all routes
import { observabilityMiddleware } from "./middleware/observability";

app.use("*", observabilityMiddleware);
```

## 12. Health Check Endpoint

A health check endpoint is the minimum viable observability surface — load balancers, uptime monitors, and `/pre-deploy` checks all use it.

```typescript
// src/routes/health.ts
import { Hono } from "hono";
import { prisma } from "../db/client";
import { logger } from "../lib/logger";

const health = new Hono();

health.get("/health", async (c) => {
  const checks: Record<string, "ok" | "fail"> = {};
  let status = 200;

  // Database
  try {
    await prisma.$queryRaw`SELECT 1`;
    checks.database = "ok";
  } catch (err) {
    logger.error({ err }, "Health check: database failed");
    checks.database = "fail";
    status = 503;
  }

  // Add further checks (Redis, external APIs) as needed
  // try { await redis.ping(); checks.redis = "ok"; } catch { ... }

  return c.json(
    {
      status: status === 200 ? "ok" : "degraded",
      checks,
      uptime: process.uptime(),
      timestamp: new Date().toISOString(),
    },
    status
  );
});

export { health };
```

```typescript
// Next.js equivalent — app/api/health/route.ts
import { NextResponse } from "next/server";
import { prisma } from "@/lib/db";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    await prisma.$queryRaw`SELECT 1`;
    return NextResponse.json({ status: "ok", timestamp: new Date().toISOString() });
  } catch {
    return NextResponse.json({ status: "degraded", checks: { database: "fail" } }, { status: 503 });
  }
}
```

## 13. Local Dev Setup (Docker)

Run the full observability stack locally with one command.

```yaml
# docker-compose.observability.yml
services:
  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "16686:16686"   # Jaeger UI
      - "4318:4318"     # OTLP HTTP receiver
    environment:
      COLLECTOR_OTLP_ENABLED: "true"

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3333:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: "admin"
    depends_on:
      - prometheus
```

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: "app"
    static_configs:
      - targets: ["host.docker.internal:3001"]  # your app's metrics endpoint
```

```bash
# Start observability stack
docker compose -f docker-compose.observability.yml up -d

# Access
# Jaeger traces:  http://localhost:16686
# Prometheus:     http://localhost:9090
# Grafana:        http://localhost:3333  (admin/admin)
```

Point your app at the local Jaeger collector:

```bash
# .env.local
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318/v1/traces
OTEL_SERVICE_NAME=my-app
```

## Setup Checklist

- [ ] Structured logging with Pino (not console.log)
- [ ] Request correlation IDs propagated through middleware
- [ ] OpenTelemetry instrumentation enabled with sampling strategy
- [ ] Context propagation working across service boundaries (W3C traceparent)
- [ ] Database spans instrumented (slow query threshold + named spans)
- [ ] Error tracking configured (Sentry or equivalent)
- [ ] Health check endpoint at `/health` (DB + dependencies)
- [ ] Key business metrics tracked (orders, signups, payments)
- [ ] P95 latency and error rate alerts configured
- [ ] Log sanitization — no PII or secrets in logs
- [ ] Log levels appropriate (info in prod, debug in dev)
- [ ] Dashboard with request rate, error rate, latency, DB pool
- [ ] Local dev Docker stack for Jaeger + Prometheus (optional but recommended)
