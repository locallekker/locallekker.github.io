import test from "node:test"
import assert from "node:assert/strict"
import { PaystackBillingProvider } from "./subscription-billing-provider.ts"

test("provider subscription inventory fails closed for active or malformed results", async () => {
  const original = globalThis.fetch
  const provider = new PaystackBillingProvider("fixture-not-a-real-key")
  try {
    for (const data of [{}, { subscriptions: null }, { subscriptions: [{ status: "active" }] },
      { subscriptions: [{ status: "non-renewing" }] }, { subscriptions: [{ status: "attention" }] },
      { subscriptions: [{}] }]) {
      globalThis.fetch = async () => Response.json({ status: true, data })
      await assert.rejects(provider.assertNoRecurringSubscription("CUS_fixture"))
    }
    globalThis.fetch = async () => Response.json({ status: true, data: { subscriptions: [] } })
    await provider.assertNoRecurringSubscription("CUS_fixture")
  } finally { globalThis.fetch = original }
})

test("provider HTTP failures and missing transactions remain unknown, not failed", async () => {
  const original = globalThis.fetch
  const provider = new PaystackBillingProvider("fixture-not-a-real-key")
  try {
    globalThis.fetch = async () => Response.json({ status: false, message: "Transaction reference not found" }, { status: 404 })
    assert.equal(await provider.verify("ll-sub-fixture"), null)
    globalThis.fetch = async () => { throw new Error("connection interrupted") }
    assert.equal(await provider.verify("ll-sub-fixture"), null)
  } finally { globalThis.fetch = original }
})

test("provider verifies the exact reference with GET and preserves its recorded status", async () => {
  const original = globalThis.fetch
  const provider = new PaystackBillingProvider("fixture-not-a-real-key")
  try {
    globalThis.fetch = async (url, options) => {
      assert.equal(url, "https://api.paystack.co/transaction/verify/ll-sub-fixture")
      assert.equal(options.method, "GET")
      return Response.json({ status: true, data: {
        id: 42, reference: "ll-sub-fixture", status: "pending", amount: 9900, currency: "ZAR",
      } })
    }
    assert.equal((await provider.verify("ll-sub-fixture")).status, "pending")
  } finally { globalThis.fetch = original }
})
