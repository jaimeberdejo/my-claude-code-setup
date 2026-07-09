# When to mock

Support file for the `tdd` skill. Mock at **system boundaries** only:

- External APIs (payment, email, …)
- Databases (sometimes — prefer a test DB)
- Time / randomness
- File system (sometimes)

Don't mock: your own classes/modules · internal collaborators · anything you control · and
NEVER the subject under test (that's on the evaluator's fakery list).

## Designing for mockability

At system boundaries, design interfaces that are easy to mock:

**1. Use dependency injection** — pass external dependencies in rather than creating them inside:

```typescript
// easy to mock
function processPayment(order, paymentClient) {
  return paymentClient.charge(order.total);
}

// hard to mock
function processPayment(order) {
  const client = new StripeClient(process.env.STRIPE_KEY);
  return client.charge(order.total);
}
```

**2. Prefer SDK-style interfaces over generic fetchers** — one specific function per external
operation instead of a generic function with conditional logic:

```typescript
// GOOD: each function is independently mockable
const api = {
  getUser: (id) => fetch(`/users/${id}`),
  getOrders: (userId) => fetch(`/users/${userId}/orders`),
  createOrder: (data) => fetch("/orders", { method: "POST", body: data }),
};

// BAD: mocking requires conditional logic inside the mock
const api = {
  fetch: (endpoint, options) => fetch(endpoint, options),
};
```

The SDK approach: each mock returns one specific shape · no conditional logic in test setup ·
you can see which endpoints a test exercises · type safety per endpoint.

If a seam needs a mock but the code creates its dependencies internally, that's a design finding
for the plan (or the `design-twice` skill) — not a reason to reach inside with a patching
framework.

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
