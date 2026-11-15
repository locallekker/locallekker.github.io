import test from "node:test"
import assert from "node:assert/strict"
import { reconcileBilling, runSubscriptionBilling } from "./subscription-billing.ts"

function fixture() {
  const cycle = {
    id: "cycle-1", subscription_id: "sub-1", user_id: "member-1",
    reference: "ll-sub-cycle-1", amount_cents: 9900, currency: "ZAR",
    purpose: "subscription_renewal", state: "ready", authorization_url: null,
    promotion_id: null, participant_id: null,
  }
  const state = { submissions: [], finalisations: 0, owner: "server", cancelled: false,
    inventoryBlocked: false, timeout: false, failFinalise: false, transaction: null }
  const store = {
    async context() { return { email: "member@example.test", customerCode: "CUS_test", owner: state.owner } },
    async saveCustomer() {},
    async prepare() { return { ...cycle } },
    async find(reference, userId) { return reference === cycle.reference && (!userId || userId === cycle.user_id) ? { ...cycle } : null },
    async claim() {
      if (cycle.state !== "ready" || state.cancelled) return false
      cycle.state = "submitting"
      return true
    },
    async card() { return "AUTH_owned" },
    async retry(previous) {
      if (cycle.state === "failed" && cycle.reference === previous.reference) {
        cycle.reference = "ll-sub-retry-1"
        cycle.state = "ready"
      }
      return { ...cycle }
    },
    async outcome(reference, status, detail, url) {
      if (cycle.state !== "paid") cycle.state = status
      if (url) cycle.authorization_url = url
    },
    async finalise() {
      if (state.failFinalise) throw new Error("database interrupted")
      if (cycle.state !== "paid") state.finalisations++
      cycle.state = "paid"
    },
  }
  const successfulTransaction = () => ({
    id: "txn-1", reference: cycle.reference, amount: 9900, currency: "ZAR",
    status: "success", paid_at: "2026-11-04T10:00:00Z",
    metadata: { user_id: cycle.user_id, billing_cycle_id: cycle.id, payment_type: cycle.purpose },
  })
  const provider = {
    async ensureCustomer() { return "CUS_test" },
    async assertNoRecurringSubscription() { if (state.inventoryBlocked) throw new Error("active provider subscription") },
    async submit(path, body) {
      state.submissions.push({ path, body })
      if (state.timeout) throw new Error("network timeout after debit")
      if (path === "/transaction/initialize") return { authorization_url: "https://checkout.paystack.com/test" }
      state.transaction = successfulTransaction()
      return { status: "success" }
    },
    async verify() { return state.transaction },
  }
  const request = { userId: cycle.user_id, action: "charge", automatic: true }
  return { cycle, state, store, provider, request, successfulTransaction }
}

test("20 concurrent renewals submit one provider charge", async () => {
  const f = fixture()
  await Promise.all(Array.from({ length: 20 }, () => runSubscriptionBilling(f.store, f.provider, f.request)))
  assert.equal(f.state.submissions.length, 1)
  assert.equal(f.state.finalisations, 1)
  assert.equal(f.state.submissions[0].body.amount, 9900)
  assert.equal(f.state.submissions[0].body.currency, "ZAR")
  assert.equal(f.state.submissions[0].body.plan, undefined)
})

test("manual saved card and scheduler share one obligation", async () => {
  const f = fixture()
  await Promise.all([
    runSubscriptionBilling(f.store, f.provider, f.request),
    runSubscriptionBilling(f.store, f.provider, { ...f.request, automatic: false }),
  ])
  assert.equal(f.state.submissions.length, 1)
  assert.equal(f.state.finalisations, 1)
})

test("hosted checkout racing a scheduler never creates two payment routes", async () => {
  const f = fixture()
  await Promise.all([
    runSubscriptionBilling(f.store, f.provider, { ...f.request, action: "checkout", callbackUrl: "https://example.test/return" }),
    runSubscriptionBilling(f.store, f.provider, f.request),
  ])
  assert.equal(f.state.submissions.length, 1)
})

test("timeout after a debit blocks fresh submissions and recovers by verification", async () => {
  const f = fixture()
  f.state.timeout = true
  assert.equal((await runSubscriptionBilling(f.store, f.provider, f.request)).state, "unknown")
  await runSubscriptionBilling(f.store, f.provider, f.request)
  assert.equal(f.state.submissions.length, 1)
  f.state.transaction = f.successfulTransaction()
  await runSubscriptionBilling(f.store, f.provider, f.request)
  assert.equal(f.state.finalisations, 1)
  assert.equal(f.state.submissions.length, 1)
})

test("database failure after debit is recovered without another charge", async () => {
  const f = fixture()
  f.state.failFinalise = true
  await assert.rejects(runSubscriptionBilling(f.store, f.provider, f.request), /database interrupted/)
  f.state.failFinalise = false
  await runSubscriptionBilling(f.store, f.provider, f.request)
  assert.equal(f.state.submissions.length, 1)
  assert.equal(f.state.finalisations, 1)
})

test("replayed callbacks and webhooks apply membership once", async () => {
  const f = fixture()
  await runSubscriptionBilling(f.store, f.provider, f.request)
  await Promise.all(Array.from({ length: 20 }, () => reconcileBilling(f.store, f.provider, f.cycle)))
  assert.equal(f.state.finalisations, 1)
})

test("pending and abandoned attempts never become new charges", async () => {
  for (const status of ["pending", "ongoing", "abandoned", "reversed"]) {
    const f = fixture()
    f.cycle.state = "unknown"
    f.state.transaction = { ...f.successfulTransaction(), status }
    await runSubscriptionBilling(f.store, f.provider, f.request)
    assert.equal(f.state.submissions.length, 0)
    assert.equal(f.state.finalisations, 0)
  }
})

test("a confirmed failed attempt does not automatically retry", async () => {
  const f = fixture()
  f.cycle.state = "unknown"
  f.state.transaction = { ...f.successfulTransaction(), status: "failed" }
  assert.equal((await runSubscriptionBilling(f.store, f.provider, f.request)).state, "failed")
  await runSubscriptionBilling(f.store, f.provider, f.request)
  assert.equal(f.state.submissions.length, 0)
})

test("manual retry requires a freshly verified terminal failure", async () => {
  const f = fixture()
  f.cycle.state = "failed"
  f.state.transaction = { ...f.successfulTransaction(), status: "failed" }
  await Promise.all([
    runSubscriptionBilling(f.store, f.provider, { ...f.request, automatic: false }),
    runSubscriptionBilling(f.store, f.provider, { ...f.request, automatic: false }),
  ])
  assert.equal(f.state.submissions.length, 1)
  assert.equal(f.state.submissions[0].body.reference, "ll-sub-retry-1")
  assert.equal(f.state.finalisations, 1)
})

test("missing ownership or provider inventory blocks charging", async () => {
  for (const owner of ["migration_pending", "paystack", "manual"]) {
    const f = fixture()
    f.state.owner = owner
    await assert.rejects(runSubscriptionBilling(f.store, f.provider, f.request), /billing_migration_required/)
    assert.equal(f.state.submissions.length, 0)
  }
  const f = fixture()
  f.state.inventoryBlocked = true
  await assert.rejects(runSubscriptionBilling(f.store, f.provider, f.request), /active provider subscription/)
  assert.equal(f.state.submissions.length, 0)
})

test("cancellation before claim blocks submission", async () => {
  const f = fixture()
  f.state.cancelled = true
  await runSubscriptionBilling(f.store, f.provider, f.request)
  assert.equal(f.state.submissions.length, 0)
})

test("another member cannot verify the obligation", async () => {
  const f = fixture()
  await assert.rejects(runSubscriptionBilling(f.store, f.provider, {
    userId: "other-member", action: "verify", reference: f.cycle.reference,
  }), /not found/)
})

test("mismatched amount, currency, member, purpose or cycle is not fulfilled", async () => {
  const invalid = [
    { amount: 100 }, { currency: "NGN" }, { reference: "another-reference" },
    { metadata: { user_id: "other-member" } },
    { metadata: { user_id: "member-1", billing_cycle_id: "cycle-1", payment_type: "one_time_payment" } },
    { metadata: { user_id: "member-1", billing_cycle_id: "other-cycle", payment_type: "subscription_renewal" } },
  ]
  for (const fields of invalid) {
    const f = fixture()
    f.state.transaction = { ...f.successfulTransaction(), ...fields }
    await assert.rejects(reconcileBilling(f.store, f.provider, f.cycle), /does not match/)
    assert.equal(f.state.finalisations, 0)
  }
})
