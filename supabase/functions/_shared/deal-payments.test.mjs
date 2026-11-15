import test from "node:test"
import assert from "node:assert/strict"
import { reconcileDealPayment, runDealPayment } from "./deal-payments.ts"

function fixture() {
  let current = {
    id: "attempt-1", deal_id: "deal-1", user_id: "member-1", reference: "ll-deal-first",
    amount_cents: 12345, currency: "ZAR", subaccount_code: "ACCT_partner",
    state: "ready", authorization_url: null, email: "member@example.test", customer_code: null,
  }
  const state = { submissions: [], finalisations: 0, status: "success", timeout: false, interrupt: false }
  const store = {
    async prepare() { return { ...current } },
    async find() { return { ...current } },
    async claim(payment) {
      if (payment.id !== current.id || current.state !== "ready") return false
      current.state = "submitting"
      return true
    },
    async retry(payment) {
      if (current.id === payment.id) current = { ...current, id: "attempt-2", reference: "ll-deal-second", state: "ready" }
      return { ...current }
    },
    async card() { return "AUTH_owned" },
    async outcome(reference, status, url) {
      if (reference === current.reference && current.state !== "paid") {
        current.state = status
        current.authorization_url = url ?? current.authorization_url
      }
    },
    async finalise() {
      if (state.interrupt) throw new Error("Receipt transaction rolled back")
      if (current.state !== "paid") state.finalisations++
      current.state = "paid"
    },
  }
  const provider = {
    async submit(path, body) {
      state.submissions.push({ path, body })
      if (state.timeout) throw new Error("Connection lost after submission")
      return path.endsWith("initialize") ? { authorization_url: "https://checkout.paystack.com/fixture" } : {}
    },
    async verify(reference) {
      if (state.timeout) return null
      return {
        id: 42, reference, amount: current.amount_cents, currency: "ZAR", status: state.status,
        paid_at: "2026-11-12T12:00:00Z",
        metadata: { user_id: current.user_id, payment_type: "one_time_payment",
          deal_authorization_id: current.deal_id, deal_payment_id: current.id },
      }
    },
  }
  return { store, provider, state, payment: () => ({ ...current }),
    request: { userId: "member-1", dealId: "deal-1", action: "charge", authorizationCode: "AUTH_owned" } }
}

test("concurrent saved-card and checkout requests submit one authoritative deal charge", async () => {
  const f = fixture()
  await Promise.all(Array.from({ length: 12 }, (_, i) => runDealPayment(f.store, f.provider, {
    ...f.request, action: i % 2 ? "checkout" : "charge", callbackUrl: "locallekker://payment/callback",
  })))
  assert.equal(f.state.submissions.length, 1)
  const body = f.state.submissions[0].body
  assert.equal(body.amount, 12345)
  assert.equal(body.currency, "ZAR")
  assert.equal(body.subaccount, "ACCT_partner")
  assert.equal(body.bearer, "account")
  assert.equal(f.state.finalisations, 1)
})

test("timeouts and pending outcomes never allow a second deal debit", async () => {
  for (const status of ["pending", "ongoing", "abandoned", "reversed", "timeout"]) {
    const f = fixture()
    f.state.status = status
    f.state.timeout = status === "timeout"
    await runDealPayment(f.store, f.provider, f.request)
    await runDealPayment(f.store, f.provider, { ...f.request, action: "checkout", callbackUrl: "https://example.test" })
    assert.equal(f.state.submissions.length, 1, status)
    assert.equal(f.state.finalisations, 0, status)
  }
})

test("only a freshly verified terminal failure permits one new manual attempt", async () => {
  const f = fixture()
  f.state.status = "failed"
  await runDealPayment(f.store, f.provider, f.request)
  await Promise.all(Array.from({ length: 10 }, () => runDealPayment(f.store, f.provider, f.request)))
  assert.equal(f.state.submissions.length, 2)
  assert.notEqual(f.state.submissions[0].body.reference, f.state.submissions[1].body.reference)
})

test("mismatched reference, member, deal, attempt, amount or currency cannot complete a deal", async () => {
  const f = fixture()
  const valid = await f.provider.verify(f.payment().reference)
  for (const transaction of [
    { ...valid, reference: "other" }, { ...valid, amount: 1 }, { ...valid, currency: "USD" },
    ...["user_id", "deal_authorization_id", "deal_payment_id", "payment_type"].map(key =>
      ({ ...valid, metadata: { ...valid.metadata, [key]: "other" } })),
  ]) {
    await assert.rejects(reconcileDealPayment(f.store, { ...f.provider, verify: async () => transaction }, f.payment()),
      /does not match/)
  }
  assert.equal(f.state.finalisations, 0)
})

test("receipt failure is recoverable by replay without submitting another charge", async () => {
  const f = fixture()
  f.state.interrupt = true
  await assert.rejects(runDealPayment(f.store, f.provider, f.request), /rolled back/)
  f.state.interrupt = false
  await runDealPayment(f.store, f.provider, f.request)
  await reconcileDealPayment(f.store, f.provider, f.payment())
  assert.equal(f.state.submissions.length, 1)
  assert.equal(f.state.finalisations, 1)
})
