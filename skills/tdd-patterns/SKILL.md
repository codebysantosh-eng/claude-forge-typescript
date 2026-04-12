---
name: tdd-patterns
description: Deep reference for test-driven development — unit, integration, E2E patterns, mocking strategies, test data factories, contract testing, snapshot testing, CI integration, and common mistakes.
---

# TDD Patterns Reference

Deep reference for the **tdd-developer** and **e2e-runner** agents. Patterns, not workflow.

Coverage targets are defined in `rules/testing.md` (authoritative source).

## Unit Test Patterns

### Function Testing (Vitest/Jest)

```typescript
describe("calculateDiscount", () => {
  it("applies percentage discount to subtotal", () => {
    expect(calculateDiscount(10000, { type: "percent", value: 15 })).toBe(8500);
  });

  it("applies fixed discount without going negative", () => {
    expect(calculateDiscount(500, { type: "fixed", value: 1000 })).toBe(0);
  });

  it("throws on negative amount", () => {
    expect(() => calculateDiscount(-1, { type: "percent", value: 10 }))
      .toThrow("Amount must be non-negative");
  });
});
```

### React Component Testing

```tsx
import { render, screen, fireEvent, waitFor } from "@testing-library/react";

describe("UserCard", () => {
  const mockUser = { id: "1", name: "Alice", email: "alice@test.com" };

  it("renders user name and email", () => {
    render(<UserCard user={mockUser} />);
    expect(screen.getByText("Alice")).toBeInTheDocument();
    expect(screen.getByText("alice@test.com")).toBeInTheDocument();
  });

  it("calls onSelect with user ID when clicked", () => {
    const onSelect = vi.fn();
    render(<UserCard user={mockUser} onSelect={onSelect} />);
    fireEvent.click(screen.getByRole("button"));
    expect(onSelect).toHaveBeenCalledWith("1");
  });
});
```

### Custom Hook Testing

```typescript
import { renderHook, act } from "@testing-library/react";

describe("useDebounce", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("debounces value changes", () => {
    const { result, rerender } = renderHook(
      ({ value }) => useDebounce(value, 500),
      { initialProps: { value: "hello" } }
    );
    rerender({ value: "world" });
    expect(result.current).toBe("hello");
    act(() => vi.advanceTimersByTime(500));
    expect(result.current).toBe("world");
  });
});
```

### Server Component Testing

```typescript
// Server Components are async — test them differently
import { render } from "@testing-library/react";

// Mock next/headers
vi.mock("next/headers", () => ({
  cookies: () => ({ get: vi.fn().mockReturnValue({ value: "session-id" }) }),
  headers: () => new Map([["x-request-id", "test-123"]]),
}));

// Mock next/navigation
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), back: vi.fn(), refresh: vi.fn() }),
  useSearchParams: () => new URLSearchParams("q=test"),
  usePathname: () => "/dashboard",
  redirect: vi.fn(),
  notFound: vi.fn(),
}));

describe("DashboardPage", () => {
  it("renders user data from server", async () => {
    // Server Components are async functions
    const page = await DashboardPage({ params: { id: "1" } });
    const { getByText } = render(page);
    expect(getByText("Dashboard")).toBeInTheDocument();
  });
});
```

### Server Action Testing

```typescript
describe("createOrder Server Action", () => {
  it("creates order and revalidates path", async () => {
    const formData = new FormData();
    formData.set("productId", "prod_123");
    formData.set("quantity", "2");

    const result = await createOrder(formData);

    expect(result.success).toBe(true);
    expect(revalidatePath).toHaveBeenCalledWith("/orders");
  });

  it("returns error for invalid input", async () => {
    const formData = new FormData();
    const result = await createOrder(formData);
    expect(result.error).toBeDefined();
  });
});
```

## Integration Test Patterns

### API Endpoint (Next.js Route Handlers)

```typescript
describe("POST /api/orders", () => {
  beforeEach(async () => {
    await prisma.order.deleteMany();
  });

  it("creates order and returns 201", async () => {
    const res = await app.request("/api/orders", {
      method: "POST",
      headers: { Authorization: `Bearer ${validToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ items: [{ sku: "W-1", qty: 2 }] }),
    });
    expect(res.status).toBe(201);
    const body = await res.json();
    expect(body.data).toHaveProperty("orderId");
  });

  it("returns 401 without authentication", async () => {
    const res = await app.request("/api/orders", { method: "POST" });
    expect(res.status).toBe(401);
  });
});
```

### Database Operations (Prisma)

```typescript
describe("UserRepository", () => {
  beforeEach(async () => {
    await prisma.user.deleteMany();
  });

  it("creates user and returns with ID", async () => {
    const user = await prisma.user.create({
      data: { email: "test@example.com", name: "Test" },
    });
    expect(user.id).toBeDefined();
    expect(user.email).toBe("test@example.com");
  });

  it("throws on duplicate email", async () => {
    await prisma.user.create({ data: { email: "test@example.com", name: "First" } });
    await expect(
      prisma.user.create({ data: { email: "test@example.com", name: "Second" } })
    ).rejects.toThrow();
  });
});
```

## Test Data Factories

Inline test data becomes a maintenance burden. Use factories for consistent, realistic data.

```typescript
// test/factories.ts
import { faker } from "@faker-js/faker";

export function createTestUser(overrides: Partial<User> = {}): User {
  return {
    id: faker.string.uuid(),
    name: faker.person.fullName(),
    email: faker.internet.email(),
    role: "user",
    createdAt: new Date(),
    ...overrides,
  };
}

export function createTestOrder(overrides: Partial<Order> = {}): Order {
  return {
    id: faker.string.uuid(),
    userId: faker.string.uuid(),
    items: [{ sku: faker.string.alphanumeric(6), quantity: faker.number.int({ min: 1, max: 5 }), price: faker.number.int({ min: 100, max: 10000 }) }],
    status: "pending",
    total: 0,
    createdAt: new Date(),
    ...overrides,
  };
}

// Usage in tests
it("calculates total for order", () => {
  const order = createTestOrder({ items: [{ sku: "A", quantity: 2, price: 5000 }] });
  expect(calculateTotal(order)).toBe(10000);
});

// Composition for complex scenarios
it("admin can view any user order", async () => {
  const admin = createTestUser({ role: "admin" });
  const customer = createTestUser();
  const order = createTestOrder({ userId: customer.id });
  // ...test admin access to customer's order
});
```

## Contract Testing

For services calling external APIs (Stripe, Supabase, etc.), contract tests verify the boundary stays stable.

```typescript
// test/contracts/stripe.contract.test.ts
import { Pact } from "@pact-foundation/pact";

const provider = new Pact({
  consumer: "MyApp",
  provider: "StripeAPI",
  port: 4000,
});

describe("Stripe Payment Contract", () => {
  beforeAll(() => provider.setup());
  afterAll(() => provider.finalize());

  it("creates a checkout session", async () => {
    await provider.addInteraction({
      state: "a product exists",
      uponReceiving: "a request to create checkout session",
      withRequest: {
        method: "POST",
        path: "/v1/checkout/sessions",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
      },
      willRespondWith: {
        status: 200,
        body: { id: Matchers.like("cs_test_123"), url: Matchers.like("https://checkout.stripe.com/...") },
      },
    });

    const result = await createCheckoutSession("price_123");
    expect(result.id).toBeDefined();
    expect(result.url).toContain("checkout.stripe.com");
  });
});
```

## Snapshot Testing

**When to use**: Serialized output, error messages, API response shapes.
**When to avoid**: UI components (snapshots become rubber-stamped noise).

```typescript
// ✓ Good: API response shape
it("returns expected user shape", async () => {
  const user = await fetchUser("1");
  expect(user).toMatchInlineSnapshot(`
    {
      "email": "alice@test.com",
      "id": "1",
      "name": "Alice",
      "role": "user",
    }
  `);
});

// ✓ Good: Error message format
it("formats validation errors consistently", () => {
  const result = validateOrder({});
  expect(result.errors).toMatchInlineSnapshot(`
    [
      { "field": "items", "message": "At least one item required" },
    ]
  `);
});

// ✗ Bad: DOM snapshot of component (breaks on any CSS/structure change)
it("renders user card", () => {
  const { container } = render(<UserCard user={mockUser} />);
  expect(container).toMatchSnapshot(); // Don't do this
});
```

## Test Isolation in CI

```typescript
// globalSetup.ts — provision test database
export async function setup() {
  const dbName = `test_${process.env.VITEST_POOL_ID || "0"}`;
  await createDatabase(dbName);
  await runMigrations(dbName);
  process.env.DATABASE_URL = `postgresql://localhost:5432/${dbName}`;
}

export async function teardown() {
  await dropDatabase(process.env.DATABASE_URL!);
}
```

**Rules for CI isolation**:
- Each test worker gets its own database (use `VITEST_POOL_ID` / `jest --shard`)
- Reset state in `beforeEach`, not `afterEach` (handles crashes)
- Mock external services (Stripe, email, etc.) — never hit real APIs in CI
- Use `globalSetup`/`globalTeardown` for DB provisioning

## Mocking Strategies

### Prisma Client

```typescript
import { mockDeep, DeepMockProxy } from "jest-mock-extended";
import { PrismaClient } from "@prisma/client";

const prisma = mockDeep<PrismaClient>();

prisma.user.findUnique.mockResolvedValue({
  id: "1", name: "Alice", email: "alice@test.com", role: "user",
});
```

### HTTP API (fetch)

```typescript
vi.mock("./api-client", () => ({
  fetchUser: vi.fn().mockResolvedValue({ id: "1", name: "Test" }),
}));

// Dynamic mock per test
const mockFetchUser = fetchUser as Mock;
it("handles API error", async () => {
  mockFetchUser.mockRejectedValueOnce(new Error("Network error"));
});
```

### Time/Date

```typescript
beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());
```

### Environment Variables

```typescript
const originalEnv = process.env;
beforeEach(() => { process.env = { ...originalEnv, STRIPE_KEY: "sk_test_123" }; });
afterEach(() => { process.env = originalEnv; });
```

## E2E Test Patterns (Playwright)

```typescript
test.describe("Authentication", () => {
  test("signup → login → dashboard", async ({ page }) => {
    await page.goto("/signup");
    await page.getByLabel("Email").fill("new@example.com");
    await page.getByLabel("Password").fill("SecurePass123!");
    await page.getByRole("button", { name: "Sign Up" }).click();
    await expect(page.getByText("Welcome")).toBeVisible();
  });
});
```

## File Organization

```
src/
├── lib/
│   ├── pricing.ts
│   └── pricing.test.ts              # Unit — next to source
├── app/api/orders/
│   ├── route.ts
│   └── route.test.ts                # Integration — next to route
├── components/UserCard/
│   ├── UserCard.tsx
│   └── UserCard.test.tsx             # Component — next to component
└── e2e/                               # E2E — dedicated folder
    ├── pages/                         # Page Objects
    ├── auth.spec.ts
    └── checkout.spec.ts
```

## Coverage Configuration (Vitest)

```typescript
export default defineConfig({
  test: {
    coverage: {
      provider: "v8",
      include: ["src/**/*.{ts,tsx}"],
      exclude: ["src/**/*.d.ts", "src/**/index.ts"],
      // Thresholds defined in rules/testing.md
    },
  },
});
```

## Mutation Testing

Mutation testing verifies that your tests actually catch bugs — not just that they run. A mutation testing tool makes small changes to your source code (mutants) and checks if your tests fail. If a mutant survives (tests still pass), your tests have a gap.

```bash
# Stryker for TypeScript/JavaScript
npx stryker init
npx stryker run
```

```typescript
// stryker.config.mjs
export default {
  mutator: "typescript",
  packageManager: "npm",
  testRunner: "vitest",
  reporters: ["html", "clear-text", "progress"],
  coverageAnalysis: "perTest",
  mutate: ["src/**/*.ts", "!src/**/*.test.ts", "!src/**/*.d.ts"],
};
```

**When to use**: After reaching 80%+ line coverage, to verify test quality. High coverage with low mutation score means tests execute code but don't assert on outcomes.

**Key metrics**:
| Metric | Target |
|--------|--------|
| Mutation score | > 70% |
| Surviving mutants | Investigate each — missing assertions or unreachable code |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Testing implementation details | Test inputs → outputs |
| One giant test | One assertion per test |
| Tests depend on order | Each test sets up own state |
| Mocking the thing under test | Mock at boundaries only |
| `test("works")` | `test("returns 404 when not found")` |
| Skipping RED phase | Always see it fail first |
| `test.skip()` to fix CI | Fix the test or `test.fixme()` with ticket |
| No cleanup in beforeEach | Reset DB/mocks before each |
| High coverage, low quality | Use mutation testing to find assertion gaps |
