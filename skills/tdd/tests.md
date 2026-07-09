# Good and bad tests

Support file for the `tdd` skill. The examples are TypeScript; the shapes are language-agnostic.

## Good tests

**Integration-style** — test through real interfaces, not mocks of internal parts:

```typescript
// GOOD: tests observable behavior
test("user can checkout with valid cart", async () => {
  const cart = createCart();
  cart.add(product);
  const result = await checkout(cart, paymentMethod);
  expect(result.status).toBe("confirmed");
});
```

Characteristics: tests behavior callers care about · public API only · survives internal
refactors · describes WHAT, not HOW · one logical assertion per test.

## Bad tests

**Implementation-detail tests** — coupled to internal structure:

```typescript
// BAD: asserts on internal wiring
test("checkout calls paymentService.process", async () => {
  const mockPayment = jest.mock(paymentService);
  await checkout(cart, payment);
  expect(mockPayment.process).toHaveBeenCalledWith(cart.total);
});
```

Red flags: mocking internal collaborators · testing private methods · asserting call
counts/order · breaks on refactor without behavior change · name describes HOW not WHAT ·
verifying through external means instead of the interface:

```typescript
// BAD: bypasses the interface to verify
test("createUser saves to database", async () => {
  await createUser({ name: "Alice" });
  const row = await db.query("SELECT * FROM users WHERE name = ?", ["Alice"]);
  expect(row).toBeDefined();
});

// GOOD: verifies through the interface
test("createUser makes user retrievable", async () => {
  const user = await createUser({ name: "Alice" });
  const retrieved = await getUser(user.id);
  expect(retrieved.name).toBe("Alice");
});
```

**Tautological tests** — the expected value restates the implementation, so the test passes by
construction (the evaluator treats this as fakery):

```typescript
// BAD: expected value recomputed the way the code computes it
test("calculateTotal sums line items", () => {
  const items = [{ price: 10 }, { price: 5 }];
  const expected = items.reduce((sum, i) => sum + i.price, 0);
  expect(calculateTotal(items)).toBe(expected);
});

// GOOD: expected value is an independent, known literal
test("calculateTotal sums line items", () => {
  expect(calculateTotal([{ price: 10 }, { price: 5 }])).toBe(15);
});
```

<!-- Adapted from mattpocock/skills (MIT) — https://github.com/mattpocock/skills -->
