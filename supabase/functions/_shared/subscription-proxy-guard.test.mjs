import test from "node:test"
import assert from "node:assert/strict"
import { blocksLegacySubscriptionSubmission as blocked } from "./subscription-proxy-guard.ts"

test("legacy membership submissions cannot bypass the billing ledger", () => {
  for (const payment_type of ["subscription", "subscription_renewal", "promotion_intro"]) {
    for (const path of ["/transaction/initialize", "/transaction/initialize?test=1", "/transaction/charge_authorization/", "/charge"]) {
      assert.equal(blocked(path, "POST", { metadata: { payment_type } }), true)
    }
  }
  assert.equal(blocked("/transaction/initialize", "POST", { plan: "PLN_test", metadata: { payment_type: "one_time_payment" } }), true)
  assert.equal(blocked("/subscription", "POST", {}), true)
  assert.equal(blocked("/subscription/enable", "POST", {}), true)
  assert.equal(blocked("/plan", "POST", {}), true)
})

test("deal payments preserve settlement parameters and card setup stays available", () => {
  const deal = {
    amount: 35000, authorization_code: "AUTH_test", subaccount: "ACCT_partner", bearer: "account",
    metadata: { payment_type: "one_time_payment", deal_authorization_id: "deal-1" },
  }
  const original = JSON.stringify(deal)
  assert.equal(blocked("/transaction/charge_authorization", "POST", deal), false)
  assert.equal(blocked("/transaction/initialize", "POST", deal), false)
  assert.equal(JSON.stringify(deal), original)
  assert.equal(blocked("/transaction/initialize", "POST", { metadata: { payment_type: "payment_method_setup" } }), false)
})

test("provider cancellation and read-only recovery remain available", () => {
  assert.equal(blocked("/subscription/disable", "POST", { code: "SUB_test", token: "fixture" }), false)
  assert.equal(blocked("/subscription/SUB_test", "GET", undefined), false)
  assert.equal(blocked("/transaction/verify/fixture", "GET", undefined), false)
  assert.equal(blocked("/__health", "POST", {}), false)
})
