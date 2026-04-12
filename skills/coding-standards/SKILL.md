---
name: coding-standards
description: Deep reference for coding standards — naming, immutability, functions, error handling, async, React patterns, API design, file organization, comments, and code smells.
---

# Coding Standards Reference

Deep reference for the **code-inspector** agent. Patterns, thresholds, and examples.

For thresholds and forbidden items, see `rules/code-quality.md` (authoritative source).

## Naming Conventions

| Thing | Convention | Good | Bad |
|-------|-----------|------|-----|
| Variables | camelCase, descriptive | `userEmail`, `orderTotal` | `data`, `tmp`, `x` |
| Functions | verb-noun camelCase | `fetchUser()`, `calculateTotal()` | `process()`, `handle()` |
| Booleans | `is`/`has`/`can`/`should` | `isActive`, `hasPermission` | `active`, `flag` |
| Constants | UPPER_SNAKE_CASE | `MAX_RETRIES`, `API_URL` | `maxRetries` |
| Types/Classes | PascalCase | `UserService`, `OrderItem` | `userService` |
| Interfaces | PascalCase (no I- prefix) | `UserProps`, `ApiResponse` | `IUserProps` |
| Files (utilities) | kebab-case | `user-service.ts` | `UserService.ts` |
| Files (components) | PascalCase | `UserCard.tsx` | `user-card.tsx` |
| Files (tests) | Match source + `.test` | `pricing.test.ts` | `test-pricing.ts` |

```typescript
// ✗ Generic
const data = await fetch("/api/users");
const result = processData(data);

// ✓ Specific
const usersResponse = await fetch("/api/users");
const activeUsers = usersResponse.filter(user => user.active);
```

## Immutability Patterns

```typescript
// ✗ MUTATION
user.role = "admin";
items.push(newItem);
users.sort((a, b) => a.name.localeCompare(b.name)); // sort mutates!

// ✓ IMMUTABLE
const updatedUser = { ...user, role: "admin" };
const withNewItem = [...items, newItem];
const sorted = [...users].sort((a, b) => a.name.localeCompare(b.name));

// ✓ Array operations — always return new array
const filtered = items.filter(item => item.active);
const mapped = items.map(item => ({ ...item, processed: true }));

// ✓ Object updates
const shallow = { ...config, debug: true };
const deep = structuredClone(complexNested);
```

## Functions

```typescript
// ✗ Deep nesting
function processOrder(order) {
  if (order) {
    if (order.items.length > 0) {
      if (order.status === "pending") {
        // logic buried 3 levels deep
      }
    }
  }
}

// ✓ Guard clauses — flat, scannable
function processOrder(order) {
  if (!order) throw new Error("Order is required");
  if (order.items.length === 0) throw new Error("Order has no items");
  if (order.status !== "pending") return;
  // logic at top level
}
```

```typescript
// ✗ Too many params
function createUser(name, email, role, avatar, team, isActive) { ... }

// ✓ Options object
interface CreateUserOptions {
  name: string;
  email: string;
  role: "user" | "admin";
  avatar?: string;
  team?: string;
}
function createUser(options: CreateUserOptions) { ... }
```

## Error Handling

```typescript
// ✓ Custom error types
class NotFoundError extends Error {
  constructor(public resource: string, public id: string) {
    super(`${resource} not found: ${id}`);
    this.name = "NotFoundError";
  }
}

// ✓ Error handling at API boundary
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  if (err instanceof NotFoundError) {
    return res.status(404).json({ error: `${err.resource} not found` });
  }
  if (err instanceof ValidationError) {
    return res.status(400).json({ error: err.message, field: err.field });
  }
  logger.error("Unhandled error", { error: err.message, stack: err.stack });
  return res.status(500).json({ error: "Internal server error" });
});
```

## Async Patterns

```typescript
// ✗ Sequential when independent
const users = await fetchUsers();
const orders = await fetchOrders();

// ✓ Parallel when independent
const [users, orders] = await Promise.all([fetchUsers(), fetchOrders()]);

// ✓ Promise.allSettled when one failure shouldn't cancel all
const results = await Promise.allSettled([fetchCritical(), fetchOptional()]);

// ✓ Retry with backoff
async function withRetry<T>(fn: () => Promise<T>, attempts = 3): Promise<T> {
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (error) {
      if (i === attempts - 1) throw error;
      await new Promise(r => setTimeout(r, Math.pow(2, i) * 1000));
    }
  }
  throw new Error("Unreachable");
}
```

## React Patterns

```tsx
// ✓ Typed props with clear interface
interface UserCardProps {
  user: User;
  onSelect: (userId: string) => void;
  variant?: "compact" | "full";
}

function UserCard({ user, onSelect, variant = "full" }: UserCardProps) {
  const handleClick = useCallback(() => onSelect(user.id), [user.id, onSelect]);
  return (
    <div onClick={handleClick}>
      <h3>{user.name}</h3>
      {variant === "full" && <p>{user.email}</p>}
    </div>
  );
}

// ✓ Custom hooks
function useDebounce<T>(value: T, delay: number): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);
  return debounced;
}
```

For Next.js App Router patterns (Server Components, Server Actions, caching), see `skills/nextjs-app-router/SKILL.md`.

## API Design

### REST Conventions

| Method | Route | Purpose | Response |
|--------|-------|---------|----------|
| GET | `/resources` | List (paginated) | 200 + array |
| GET | `/resources/:id` | Get one | 200 or 404 |
| POST | `/resources` | Create | 201 + created |
| PATCH | `/resources/:id` | Partial update | 200 + updated |
| DELETE | `/resources/:id` | Delete | 204 |

### Input Validation (Zod)

```typescript
import { z } from "zod";

const CreateOrderSchema = z.object({
  items: z.array(z.object({
    sku: z.string().min(1),
    quantity: z.number().int().positive(),
  })).min(1, "At least one item required"),
  customerId: z.string().uuid(),
  notes: z.string().max(500).optional(),
});

type CreateOrderInput = z.infer<typeof CreateOrderSchema>;
```

## File Organization

```
src/
├── app/                        # Next.js App Router
│   ├── api/                   # Route handlers
│   ├── dashboard/page.tsx
│   └── layout.tsx
├── components/
│   ├── ui/                   # Generic (Button, Input, Modal)
│   └── features/             # Domain-specific (OrderForm, UserCard)
├── hooks/                    # Custom React hooks
├── lib/                      # Business logic and utilities
├── types/                    # TypeScript types
└── styles/                   # Global styles
```

## Code Smells

| Smell | Threshold | Action |
|-------|-----------|--------|
| Long function | > 50 lines | Extract helpers |
| Deep nesting | > 4 levels | Guard clauses |
| Magic numbers | Any literal in logic | Named constant |
| Large file | > 800 lines | Split by responsibility |
| Duplicated logic | > 3 occurrences | Extract shared function |
| Boolean params | `fn(true, false)` | Options object |
| Primitive obsession | Strings everywhere | Value objects / types |

## Comments

- Delete commented-out code — use git history
- TODO must have ticket: `// TODO(#123): migrate to v2`
- Don't document the obvious — only explain WHY for non-obvious decisions
