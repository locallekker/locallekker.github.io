import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { reconcileBilling, runSubscriptionBilling } from "../_shared/subscription-billing.ts"
import { SupabaseBillingStore } from "../_shared/subscription-billing-store.ts"
import { PaystackBillingProvider } from "../_shared/subscription-billing-provider.ts"

const headers = { "Content-Type": "application/json" }

serve(async req => {
  const secret = Deno.env.get("CRON_SECRET")
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers })
  }
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers })
  try {
    const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)
    const store = new SupabaseBillingStore(client)
    const provider = new PaystackBillingProvider((Deno.env.get("PAYSTACK_SECRET_KEY") ?? "").trim())
    const input = await req.text()
    const body = input ? JSON.parse(input) : {}
    if (body.user_id !== undefined && typeof body.user_id !== "string") throw new Error("Invalid member filter")
    const userId: string | undefined = body.user_id

    // Unknown outcomes are reconciled even if the member has since cancelled.
    let unresolvedQuery = client.from("subscription_billing_cycles").select("*")
      .in("state", ["submitting", "pending", "unknown"])
    if (userId) unresolvedQuery = unresolvedQuery.eq("user_id", userId)
    const { data: unresolved, error: unresolvedError } = await unresolvedQuery
    if (unresolvedError) throw unresolvedError
    const results: { user_id: string; state: string; reference?: string; error?: string }[] = []
    for (const cycle of unresolved ?? []) {
      try {
        const result = await reconcileBilling(store, provider, cycle)
        results.push({ user_id: cycle.user_id, state: result.state, reference: result.reference })
      } catch (error) {
        console.error(`Billing reconciliation failed cycle=${cycle.id}`, error)
        results.push({ user_id: cycle.user_id, state: "error", error: error instanceof Error ? error.message : "Reconciliation failed" })
      }
    }

    let dueQuery = client.from("server_subscriptions_due_for_renewal").select("user_id")
    if (userId) dueQuery = dueQuery.eq("user_id", userId)
    const { data: due, error: dueError } = await dueQuery
    if (dueError) throw dueError
    for (const memberId of new Set<string>((due ?? []).map(row => row.user_id))) {
      try {
        const result = await runSubscriptionBilling(store, provider, {
          userId: memberId, action: "charge", automatic: true,
        })
        results.push({ user_id: memberId, state: result.state, reference: result.reference })
      } catch (error) {
        console.error(`Subscription renewal blocked user=${memberId}`, error)
        results.push({ user_id: memberId, state: "error", error: error instanceof Error ? error.message : "Renewal failed" })
      }
    }
    const { error: expiryError } = await client.rpc("expire_server_subscription_access", { p_user_id: userId ?? null })
    if (expiryError) throw expiryError
    return new Response(JSON.stringify({ processed: results.length, results }), { headers })
  } catch (error) {
    console.error("Scheduled subscription billing failed", error)
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : "Billing worker failed" }),
      { status: 500, headers })
  }
})
