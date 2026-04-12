---
name: nextjs-app-router
description: Deep reference for Next.js App Router — Server/Client components, Server Actions, data fetching, caching, middleware, metadata, and performance patterns.
---

# Next.js App Router Reference

Deep reference for the **code-inspector** and **performance-profiler** agents. Patterns for Next.js 14+ App Router.

## Server vs Client Components

### Server Components (Default)

Every component in `app/` is a Server Component by default. They run on the server only.

```tsx
// app/dashboard/page.tsx — Server Component (no directive needed)
import { prisma } from "@/lib/db";

export default async function DashboardPage() {
  const users = await prisma.user.findMany({ take: 10 });

  return (
    <div>
      <h1>Dashboard</h1>
      <UserList users={users} />
    </div>
  );
}
```

**Can do**: `async/await`, direct DB access, access filesystem, use secrets, zero client JS
**Cannot**: `useState`, `useEffect`, `useCallback`, event handlers, browser APIs

### Client Components

Add `"use client"` at the top when you need interactivity.

```tsx
"use client";
// app/components/counter.tsx — Client Component

import { useState } from "react";

export function Counter() {
  const [count, setCount] = useState(0);
  return <button onClick={() => setCount(count + 1)}>Count: {count}</button>;
}
```

**Must use `"use client"` when**: `useState`, `useEffect`, `useCallback`, `useRef`, event handlers (`onClick`, `onChange`), browser APIs (`window`, `document`, `localStorage`), third-party client libraries.

### Boundary Rules

```tsx
// ✓ Server Component wrapping Client Component — pass data as props
export default async function Page() {
  const data = await fetchData(); // Server-side
  return <InteractiveChart data={data} />; // Client Component receives serialized data
}

// ✗ DO NOT: Import Server Component into Client Component
"use client";
import { ServerThing } from "./ServerThing"; // This won't work as expected

// ✓ DO: Pass Server Components as children
"use client";
export function ClientWrapper({ children }: { children: React.ReactNode }) {
  const [isOpen, setIsOpen] = useState(false);
  return <div>{isOpen && children}</div>; // children can be Server Components
}
```

### Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `useState` without `"use client"` | Build error | Add `"use client"` or lift state to Client Component |
| `async` Client Component | Build error | Only Server Components can be `async` |
| Importing server-only code in Client | Secret leaks | Use `server-only` package, keep in separate file |
| Passing non-serializable props | Runtime error | Only pass JSON-serializable data to Client Components |
| Passing `Date` objects to Client Components | Serialized as string, loses type | Use `.toISOString()` and `new Date()` on client |

### Serialization Boundary

```tsx
// ✗ Date objects lose their type across the boundary
export default async function Page() {
  const post = await prisma.post.findFirst();
  return <PostCard createdAt={post.createdAt} />; // Client gets a string, not a Date
}

// ✓ Explicit serialization
export default async function Page() {
  const post = await prisma.post.findFirst();
  return <PostCard createdAt={post.createdAt.toISOString()} />;
}

// Client Component reconstructs
function PostCard({ createdAt }: { createdAt: string }) {
  const date = new Date(createdAt);
  return <time dateTime={createdAt}>{date.toLocaleDateString()}</time>;
}
```

## Server Actions

```tsx
// app/actions.ts
"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

const CreatePostSchema = z.object({
  title: z.string().min(1).max(200),
  content: z.string().min(1),
});

export async function createPost(
  prevState: { error?: Record<string, string[]> } | null,
  formData: FormData
) {
  // 1. Auth check — ALWAYS first. Return error object, don't throw.
  // Throwing in a Server Action bubbles to error.tsx, NOT back to the form.
  const session = await getSession();
  if (!session) {
    return { error: { _form: ["You must be logged in."] } };
  }

  // 2. Validate input with Zod
  const parsed = CreatePostSchema.safeParse({
    title: formData.get("title"),
    content: formData.get("content"),
  });

  if (!parsed.success) {
    return { error: parsed.error.flatten().fieldErrors };
  }

  // 3. Mutate data
  await prisma.post.create({
    data: { ...parsed.data, authorId: session.userId },
  });

  // 4. Revalidate and redirect
  // redirect() throws internally — call AFTER all other work is done
  revalidatePath("/posts");
  redirect("/posts");
}

// KEY RULES for Server Actions:
// - Return error objects for expected failures (validation, auth) — the form can display them
// - throw only for unexpected errors — they bubble to error.tsx and the form loses state
// - redirect() throws internally — always call it LAST, never inside try/catch
// - prevState parameter is required when using useActionState
```

### Using with Forms

```tsx
"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { createPost } from "./actions";

function SubmitButton() {
  const { pending } = useFormStatus();
  return <button type="submit" disabled={pending}>{pending ? "Saving..." : "Save"}</button>;
}

export function PostForm() {
  const [state, formAction] = useActionState(createPost, null);

  return (
    <form action={formAction}>
      <input name="title" required />
      {state?.error?.title && <p className="text-red-500">{state.error.title}</p>}
      <textarea name="content" required />
      <SubmitButton />
    </form>
  );
}
```

### Optimistic Updates

```tsx
"use client";

import { useOptimistic } from "react";

export function TodoList({ todos }: { todos: Todo[] }) {
  const [optimisticTodos, addOptimistic] = useOptimistic(
    todos,
    (state, newTodo: Todo) => [...state, newTodo]
  );

  async function handleAdd(formData: FormData) {
    const title = formData.get("title") as string;
    addOptimistic({ id: "temp", title, completed: false });
    await addTodo(formData); // Server Action
  }

  return (
    <form action={handleAdd}>
      <input name="title" />
      <ul>{optimisticTodos.map(t => <li key={t.id}>{t.title}</li>)}</ul>
    </form>
  );
}
```

### React 19 Patterns

```tsx
// use() hook — read promises in Client Components (passed from Server Components)
"use client";
import { use } from "react";

function UserProfile({ userPromise }: { userPromise: Promise<User> }) {
  const user = use(userPromise); // Suspends until resolved
  return <div>{user.name}</div>;
}

// Server Component passes the promise (not the resolved value)
export default function Page() {
  const userPromise = fetchUser("1"); // Don't await — pass the promise
  return (
    <Suspense fallback={<Skeleton />}>
      <UserProfile userPromise={userPromise} />
    </Suspense>
  );
}
```

```tsx
// useActionState — replaces useFormState (deprecated)
"use client";
import { useActionState } from "react";

function LoginForm() {
  const [state, formAction, isPending] = useActionState(loginAction, null);
  // isPending is the third return value — no need for separate useFormStatus
  return (
    <form action={formAction}>
      <input name="email" />
      {state?.error && <p>{state.error}</p>}
      <button disabled={isPending}>{isPending ? "Logging in..." : "Log in"}</button>
    </form>
  );
}
```

## Data Fetching

### In Server Components

```tsx
// ✓ Direct database access (no API needed)
export default async function UsersPage() {
  const users = await prisma.user.findMany();
  return <UserList users={users} />;
}

// ✓ Fetch with caching
async function getProduct(id: string) {
  const res = await fetch(`https://api.example.com/products/${id}`, {
    next: { revalidate: 3600 }, // Cache for 1 hour
  });
  return res.json();
}

// ✓ Parallel data fetching in layouts
export default async function Layout({ children }) {
  const [user, notifications] = await Promise.all([
    getUser(),
    getNotifications(),
  ]);
  return <div><Sidebar user={user} notifications={notifications} />{children}</div>;
}
```

### Caching

```tsx
import { cache } from "react";
import { unstable_cache } from "next/cache";

// ✓ Request-level deduplication (within single render)
export const getUser = cache(async (id: string) => {
  return prisma.user.findUnique({ where: { id } });
});

// ✓ Cross-request caching with tags
// Note: unstable_cache name is legacy — API is stable in Next.js 14+
// but may be renamed in future versions. Wrap in your own function for safety.
export const getProducts = unstable_cache(
  async () => prisma.product.findMany(),
  ["products"],
  { revalidate: 3600, tags: ["products"] }
);

// Invalidate cache
import { revalidateTag } from "next/cache";
revalidateTag("products"); // In a Server Action
```

### ISR / SSG / SSR Decision Framework

| Strategy | Config | Use When |
|----------|--------|----------|
| **Static (SSG)** | `dynamic = "force-static"` | Content rarely changes (marketing, docs) |
| **ISR** | `revalidate = 3600` | Content changes occasionally (blog, catalog) |
| **Dynamic (SSR)** | `dynamic = "force-dynamic"` | Personalized, real-time, auth-dependent |
| **Streaming** | `<Suspense>` boundaries | Mix of fast + slow data on same page |

```tsx
// Static generation with known params
export async function generateStaticParams() {
  const products = await prisma.product.findMany({ select: { slug: true } });
  return products.map(p => ({ slug: p.slug }));
}
```

## File Conventions

| File | Purpose |
|------|---------|
| `page.tsx` | Route UI — required for route to be accessible |
| `layout.tsx` | Shared layout wrapper, persists across navigation |
| `loading.tsx` | Instant loading UI (wraps page in `<Suspense>`) |
| `error.tsx` | Error boundary (`"use client"` required) |
| `not-found.tsx` | 404 UI for `notFound()` calls |
| `route.ts` | API route handler (GET, POST, etc.) |
| `template.tsx` | Like layout but re-renders on navigation |
| `default.tsx` | Fallback for parallel routes |
| `middleware.ts` | Request-level middleware (root only) |

### Route Groups, Parallel Routes, and Intercepting Routes

```
app/
├── (marketing)/         # Route group — no URL segment
│   ├── about/page.tsx   # /about
│   └── pricing/page.tsx # /pricing
├── (app)/               # Another group — different layout
│   ├── layout.tsx       # App-specific layout
│   └── dashboard/page.tsx # /dashboard
├── @modal/              # Parallel route (slot)
│   ├── default.tsx      # Required — fallback when slot has no match
│   └── (.)photo/[id]/   # Intercepting route — modal over current page
│       └── page.tsx     # Shows photo in modal (soft navigation)
├── photo/[id]/          # Full photo page (hard navigation / direct URL)
│   └── page.tsx
└── layout.tsx           # Root layout — renders {children} + {modal}
```

**Intercepting Routes** (`(.)`, `(..)`, `(...)`, `(..)(..)`):
```tsx
// app/@modal/(.)photo/[id]/page.tsx — intercepts /photo/[id] and shows as modal
export default function PhotoModal({ params }: { params: { id: string } }) {
  return (
    <Dialog>
      <PhotoDetail id={params.id} />
    </Dialog>
  );
}

// app/photo/[id]/page.tsx — full page for direct URL access or refresh
export default function PhotoPage({ params }: { params: { id: string } }) {
  return <PhotoDetail id={params.id} />;
}
```

Use intercepting routes for: modals over lists, preview panes, share-friendly URLs that work both as modals and standalone pages.

### `notFound()` Pattern

```tsx
import { notFound } from "next/navigation";

export default async function ProductPage({ params }: { params: { id: string } }) {
  const product = await prisma.product.findUnique({ where: { id: params.id } });
  if (!product) notFound(); // Renders closest not-found.tsx

  return <ProductDetail product={product} />;
}
```

## Middleware

```typescript
// middleware.ts (root of project)
import { NextRequest, NextResponse } from "next/server";

export function middleware(request: NextRequest) {
  const session = request.cookies.get("session");

  // Auth redirect
  if (request.nextUrl.pathname.startsWith("/dashboard") && !session) {
    return NextResponse.redirect(new URL("/login", request.url));
  }

  // Add headers
  const response = NextResponse.next();
  response.headers.set("x-request-id", crypto.randomUUID());
  return response;
}

export const config = {
  matcher: ["/dashboard/:path*", "/api/:path*"],
};
```

## Metadata & SEO

```tsx
// Static metadata
export const metadata = {
  title: "My App",
  description: "The best app ever",
  openGraph: { title: "My App", images: ["/og.png"] },
};

// Dynamic metadata
export async function generateMetadata({ params }: { params: { slug: string } }) {
  const product = await getProduct(params.slug);
  return {
    title: product.name,
    description: product.description,
    openGraph: { images: [product.image] },
  };
}
```

## Performance Patterns

```tsx
// ✓ next/image — automatic optimization
import Image from "next/image";
<Image src="/hero.jpg" width={1200} height={600} sizes="100vw" priority placeholder="blur" />

// ✓ next/font — no layout shift
import { Inter } from "next/font/google";
const inter = Inter({ subsets: ["latin"], display: "swap" });

// ✓ Streaming with Suspense + error boundaries
// IMPORTANT: Each Suspense boundary should have a corresponding error.tsx
// at the route segment level, or wrap in an ErrorBoundary component.
// If an async Server Component inside Suspense throws, the error bubbles
// to the nearest error boundary — without one, the whole page fails.
export default async function Page() {
  return (
    <div>
      <h1>Dashboard</h1>
      <Suspense fallback={<StatsSkeleton />}>
        <StatsPanel /> {/* Slow data — streams in */}
      </Suspense>
      <Suspense fallback={<ChartSkeleton />}>
        <RevenueChart /> {/* Another slow section */}
      </Suspense>
    </div>
  );
}
// Ensure app/dashboard/error.tsx exists to catch streaming failures

// ✓ Dynamic imports for heavy client components
import dynamic from "next/dynamic";
const Chart = dynamic(() => import("./Chart"), {
  loading: () => <Skeleton />,
  ssr: false,
});

// ✓ Route segment config
export const revalidate = 3600;        // ISR every hour
export const dynamic = "force-static"; // Full static
export const fetchCache = "force-cache"; // Cache all fetches
```
