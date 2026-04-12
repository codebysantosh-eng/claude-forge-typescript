---
name: prisma-patterns
description: Deep reference for Prisma ORM — schema design, migrations, client usage, performance, testing, and Next.js integration patterns.
---

# Prisma Patterns Reference

Deep reference for the **architect** and **tdd-developer** agents. Schema design, migrations, performance, and serverless patterns.

## Schema Design

```prisma
// prisma/schema.prisma

generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

// ✓ Model naming: PascalCase, singular
model User {
  id        String   @id @default(cuid())
  email     String   @unique
  name      String
  role      Role     @default(USER)
  posts     Post[]
  orders    Order[]
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  @@map("users") // Snake-case table name in DB
}

model Post {
  id        String   @id @default(cuid())
  title     String
  content   String
  published Boolean  @default(false)
  author    User     @relation(fields: [authorId], references: [id])
  authorId  String
  tags      Tag[]
  metadata  Json?    // Flexible JSON field
  createdAt DateTime @default(now())

  @@index([authorId])
  @@index([published, createdAt(sort: Desc)])
  @@map("posts")
}

// Many-to-many (implicit)
model Tag {
  id    String @id @default(cuid())
  name  String @unique
  posts Post[]

  @@map("tags")
}

// Enums
enum Role {
  USER
  ADMIN
  MODERATOR
}

// Self-relation
model Category {
  id       String     @id @default(cuid())
  name     String
  parent   Category?  @relation("CategoryTree", fields: [parentId], references: [id])
  parentId String?
  children Category[] @relation("CategoryTree")

  @@map("categories")
}
```

### Schema Rules

- Model names: PascalCase singular (`User`, not `Users`)
- Use `@map`/`@@map` for snake_case DB table/column names
- Always add `createdAt` and `updatedAt`
- Use `cuid()` or `uuid()` for IDs (not auto-increment for distributed systems)
- Add `@@index` for frequently queried fields
- Use enums for fixed sets of values
- Use `Json` fields sparingly — validate with Zod at the application layer

### Zod Validation for Json Fields

```typescript
import { z } from "zod";

const MetadataSchema = z.object({
  source: z.enum(["web", "mobile", "api"]),
  version: z.string(),
  features: z.array(z.string()).optional(),
});

type Metadata = z.infer<typeof MetadataSchema>;

// Validate before saving
const metadata = MetadataSchema.parse(input);
await prisma.post.create({ data: { ...postData, metadata } });
```

## Migrations

### Development Workflow

```bash
# 1. Edit prisma/schema.prisma
# 2. Create migration
npx prisma migrate dev --name add_posts_table

# 3. Apply + generate client
# (migrate dev does both automatically)

# View migration SQL before applying
npx prisma migrate dev --create-only
```

### When to Use What

| Command | When | Effect |
|---------|------|--------|
| `prisma migrate dev` | Development — schema changes | Creates migration, applies, generates client |
| `prisma db push` | Prototyping — no migration history needed | Applies schema directly, no migration file |
| `prisma migrate deploy` | Production / CI | Applies pending migrations (no generation) |
| `prisma migrate reset` | Dev — fresh start | Drops DB, re-applies all migrations, runs seed |

### Handling Breaking Changes (Expand-Contract Pattern)

Zero-downtime migrations require the **expand-contract** pattern: deploy migrations BEFORE new code, never in the same release.

```sql
-- PHASE 1 (deploy migration only — old code still running):
-- Expand: Add new column as NULLABLE (no table lock)
ALTER TABLE "users" ADD COLUMN "full_name" TEXT;
-- Backfill in batches (not one giant UPDATE — avoids long locks)
UPDATE "users" SET "full_name" = "name" WHERE "full_name" IS NULL LIMIT 10000;

-- PHASE 2 (deploy new code that writes to both columns)

-- PHASE 3 (deploy migration to clean up):
-- Contract: Drop old column
ALTER TABLE "users" DROP COLUMN "name";
```

**Migration Safety Rules:**

| Operation | Risk | Safe Alternative |
|-----------|------|-----------------|
| `ADD COLUMN ... NOT NULL` (no default) | **Locks table** on PG <11 | Add as NULLABLE, backfill, then add NOT NULL |
| `CREATE INDEX` | **Locks table** for writes | `CREATE INDEX CONCURRENTLY` |
| `ALTER COLUMN TYPE` | **Rewrites table** | Add new column, backfill, drop old |
| `DROP COLUMN` | Breaks old code still running | Drop in separate deploy after code stops referencing it |
| Large `UPDATE` | Long lock, blocks writes | Batch in chunks of 10K rows |

```bash
# Custom migration for data backfill
npx prisma migrate dev --create-only --name rename_name_to_full_name
# Edit the generated SQL file manually — add CONCURRENTLY, batching
# Then apply:
npx prisma migrate dev
```

### Production Deployment

```bash
# In CI/CD pipeline — run migrations BEFORE deploying new code
npx prisma migrate deploy  # Apply pending migrations
npx prisma generate         # Generate client (if not cached)
```

**Deployment order**: migrations first → health check → deploy new code → verify → clean up old columns later

## Client Usage

### CRUD Operations

```typescript
// Create
const user = await prisma.user.create({
  data: { email: "alice@example.com", name: "Alice" },
});

// Read (with relations)
const userWithPosts = await prisma.user.findUnique({
  where: { id: userId },
  include: { posts: { where: { published: true }, orderBy: { createdAt: "desc" } } },
});

// Update
const updated = await prisma.user.update({
  where: { id: userId },
  data: { name: "Alice Smith" },
});

// Delete
await prisma.user.delete({ where: { id: userId } });

// Upsert
const user = await prisma.user.upsert({
  where: { email: "alice@example.com" },
  update: { name: "Alice Updated" },
  create: { email: "alice@example.com", name: "Alice" },
});
```

### Filtering

```typescript
const users = await prisma.user.findMany({
  where: {
    AND: [
      { role: "USER" },
      { email: { contains: "@company.com" } },
      { createdAt: { gte: new Date("2024-01-01") } },
    ],
  },
  orderBy: { createdAt: "desc" },
  take: 20,
  skip: 0,
});
```

### Transactions

```typescript
// Sequential transaction
const [order, payment] = await prisma.$transaction([
  prisma.order.create({ data: orderData }),
  prisma.payment.create({ data: paymentData }),
]);

// Interactive transaction (for dependent operations)
// ALWAYS set timeout and isolation level — defaults (5s, ReadCommitted)
// hold row locks and can cause deadlocks under concurrent writes
const result = await prisma.$transaction(
  async (tx) => {
    const user = await tx.user.findUnique({ where: { id: userId } });
    if (!user) throw new Error("User not found");

    const order = await tx.order.create({
      data: { ...orderData, userId: user.id },
    });

    await tx.user.update({
      where: { id: userId },
      data: { orderCount: { increment: 1 } },
    });

    return order;
  },
  {
    maxWait: 2000,  // Max time to acquire a connection from pool
    timeout: 5000,  // Max time for the transaction to complete
    isolationLevel: "ReadCommitted", // Explicit — avoid Serializable unless needed
  }
);
```

### Select vs Include

```typescript
// ✗ Over-fetching — returns all fields + all post fields
const user = await prisma.user.findUnique({
  where: { id },
  include: { posts: true },
});

// ✓ Select only what you need
const user = await prisma.user.findUnique({
  where: { id },
  select: {
    id: true,
    name: true,
    email: true,
    posts: {
      select: { id: true, title: true },
      where: { published: true },
      take: 5,
    },
  },
});
```

## Performance

### Connection Pooling for Serverless

```typescript
// lib/db.ts — Singleton pattern for Next.js
import { PrismaClient } from "@prisma/client";

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient };

export const prisma = globalForPrisma.prisma ?? new PrismaClient({
  log: process.env.NODE_ENV === "development" ? ["query", "warn", "error"] : ["error"],
});

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.prisma = prisma;
}
```

### Connection Pool Configuration

PostgreSQL defaults to 100 max connections. Prisma defaults to `num_cpus * 2 + 1` connections per instance. With multiple replicas, you can exhaust the pool. **Always configure explicitly.**

```
# Long-running server (e.g., 4 replicas, PG max_connections=100)
# Leave 20 connections for admin/monitoring
DATABASE_URL="postgresql://user:pass@host:5432/db?connection_limit=20&pool_timeout=10&connect_timeout=5"

# Serverless (Vercel, Lambda) — 1 connection per function instance
DATABASE_URL="postgresql://user:pass@pgbouncer-host:6432/db?pgbouncer=true&connection_limit=1"
```

| Deployment | `connection_limit` | Pooler |
|------------|-------------------|--------|
| Single server | `num_cpus * 2 + 1` (default OK) | None needed |
| Multiple replicas | `floor(max_connections / replicas) - buffer` | Optional PgBouncer |
| Serverless (Vercel) | `1` | **Required**: Prisma Accelerate or PgBouncer |
| Edge Runtime | N/A — no TCP | Use Prisma Accelerate or Neon serverless driver |

For production serverless (Vercel):
- Use **Prisma Accelerate** (connection pooling + global edge caching)
- Or **PgBouncer** as an external connection pooler
- Or **Neon** serverless driver (HTTP-based, no connection limits)

### Pagination

```typescript
// Cursor-based (recommended — O(1) regardless of offset)
const posts = await prisma.post.findMany({
  take: 20,
  skip: 1, // Skip the cursor
  cursor: { id: lastPostId },
  orderBy: { createdAt: "desc" },
});

// Offset-based (simpler but slower for deep pages)
const posts = await prisma.post.findMany({
  take: 20,
  skip: page * 20,
  orderBy: { createdAt: "desc" },
});
```

### Batch Operations

```typescript
// Create many
await prisma.user.createMany({
  data: users,
  skipDuplicates: true,
});

// Update many
await prisma.post.updateMany({
  where: { authorId: userId, published: false },
  data: { published: true },
});

// Delete many
await prisma.session.deleteMany({
  where: { expiresAt: { lt: new Date() } },
});
```

### Indexing

```prisma
model Order {
  id        String   @id @default(cuid())
  userId    String
  status    String
  total     Int
  createdAt DateTime @default(now())

  // ✓ Single-column index for filtering
  @@index([userId])

  // ✓ Compound index for combined queries
  @@index([userId, status])

  // ✓ Index for sorting
  @@index([createdAt(sort: Desc)])

  // ✓ Unique constraint (also creates index)
  @@unique([userId, status])
}
```

## Testing

### Database Reset Between Tests

```typescript
// test/helpers.ts
import { prisma } from "@/lib/db";

export async function resetDatabase() {
  // Delete in dependency order
  await prisma.order.deleteMany();
  await prisma.post.deleteMany();
  await prisma.user.deleteMany();
}

// In tests
beforeEach(async () => {
  await resetDatabase();
});
```

### Seed Script

```typescript
// prisma/seed.ts
import { prisma } from "../src/lib/db";

async function seed() {
  const admin = await prisma.user.create({
    data: { email: "admin@example.com", name: "Admin", role: "ADMIN" },
  });

  await prisma.post.createMany({
    data: [
      { title: "First Post", content: "Hello world", authorId: admin.id, published: true },
      { title: "Draft Post", content: "Work in progress", authorId: admin.id },
    ],
  });
}

seed().catch(console.error).finally(() => prisma.$disconnect());
```

```json
// package.json
{ "prisma": { "seed": "tsx prisma/seed.ts" } }
```

### Mocking Prisma in Unit Tests

```typescript
import { mockDeep, DeepMockProxy } from "jest-mock-extended";
import { PrismaClient } from "@prisma/client";

export type MockPrisma = DeepMockProxy<PrismaClient>;

export function createMockPrisma(): MockPrisma {
  return mockDeep<PrismaClient>();
}

// In test
const prisma = createMockPrisma();
prisma.user.findUnique.mockResolvedValue({
  id: "1", email: "test@test.com", name: "Test", role: "USER",
  createdAt: new Date(), updatedAt: new Date(),
});
```

## Next.js Integration

### In Server Components

```tsx
// ✓ Direct Prisma access in Server Components
export default async function UsersPage() {
  const users = await prisma.user.findMany({
    select: { id: true, name: true, email: true },
    orderBy: { createdAt: "desc" },
    take: 50,
  });
  return <UserTable users={users} />;
}
```

### In Server Actions

```tsx
"use server";

export async function updateProfile(formData: FormData) {
  const session = await getSession();
  if (!session) throw new Error("Unauthorized");

  await prisma.user.update({
    where: { id: session.userId },
    data: {
      name: formData.get("name") as string,
      bio: formData.get("bio") as string,
    },
  });

  revalidatePath("/profile");
}
```

### In Route Handlers

```typescript
// app/api/users/route.ts
import { NextRequest, NextResponse } from "next/server";

export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams;
  const page = Number(searchParams.get("page") || "1");

  const users = await prisma.user.findMany({
    take: 20,
    skip: (page - 1) * 20,
    orderBy: { createdAt: "desc" },
  });

  const total = await prisma.user.count();

  return NextResponse.json({ data: users, meta: { total, page, limit: 20 } });
}
```

### CI/CD Pipeline

```yaml
# .github/workflows/deploy.yml
steps:
  - run: npx prisma generate    # Generate client from schema
  - run: npx prisma migrate deploy  # Apply pending migrations
  - run: npm run build           # Build Next.js app
```

**Remember**: Always run `prisma generate` before build in CI. The generated client is NOT committed to git.
