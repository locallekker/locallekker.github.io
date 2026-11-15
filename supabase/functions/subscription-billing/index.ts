import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { runSubscriptionBilling } from "../_shared/subscription-billing.ts"
import { SupabaseBillingStore } from "../_shared/subscription-billing-store.ts"
import { PaystackBillingProvider } from "../_shared/subscription-billing-provider.ts"

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Content-Type": "application/json",
}

serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers })
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers })
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "")
  if (!token) return new Response(JSON.stringify({ error: "Sign in required" }), { status: 401, headers })
  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user) return new Response(JSON.stringify({ error: "Session expired" }), { status: 401, headers })
  try {
    const input = await req.json()
    if (!["charge", "checkout", "verify"].includes(input.action)) {
      return new Response(JSON.stringify({ error: "Invalid billing action" }), { status: 400, headers })
    }
    const callbackUrl = Deno.env.get("SUBSCRIPTION_CHECKOUT_CALLBACK_URL")
    const result = await runSubscriptionBilling(
      new SupabaseBillingStore(supabase),
      new PaystackBillingProvider((Deno.env.get("PAYSTACK_SECRET_KEY") ?? "").trim()),
      {
        userId: user.id, action: input.action, callbackUrl,
        useCustomerCode: input.use_customer_code !== false,
        reference: typeof input.reference === "string" ? input.reference : undefined,
        authorizationCode: typeof input.authorization_code === "string" ? input.authorization_code : undefined,
        cvv: typeof input.cvv === "string" ? input.cvv : undefined,
        promotionId: typeof input.promotion_id === "string" ? input.promotion_id : undefined,
        participantId: typeof input.participant_id === "string" ? input.participant_id : undefined,
      },
    )
    return new Response(JSON.stringify(result), { headers })
  } catch (error) {
    console.error("Subscription billing request failed", error)
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : "Subscription billing failed" }),
      { status: 409, headers })
  }
})
