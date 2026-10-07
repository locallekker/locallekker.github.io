// Scheduled Renewal Worker
// Charges all active subscriptions whose current_period_end has passed
// and auto_renew is enabled. Uses Paystack charge_authorization to charge
// the member's saved primary card, then extends the subscription period.
//
// Invocation: HTTP POST from pg_cron via net.http_post, or manually.
// Auth: x-cron-secret header (set CRON_SECRET in Edge Function secrets).
//
// Environment variables required:
//   SUPABASE_URL             â€“ auto-set by Supabase
//   SUPABASE_SERVICE_ROLE_KEY â€“ auto-set by Supabase
//   PAYSTACK_SECRET_KEY      â€“ Paystack live secret key
//   CRON_SECRET              â€“ shared secret to authorise cron invocations

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
}

// â”€â”€ Types â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
interface DueSubscription {
  subscription_id: string
  user_id: string
  plan_type: string
  renewal_charge_cents: number
  current_period_end: string
  email: string
  paystack_customer_code: string | null
  authorization_code: string | null
  card_type: string | null
  last4: string | null
  card_email: string | null
}

interface RenewalResult {
  user_id: string
  subscription_id: string
  status: "success" | "failed" | "skipped"
  reason?: string
  reference?: string
  amount_cents?: number
}

// â”€â”€ Entry point â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  const cronSecret = Deno.env.get("CRON_SECRET")
  const paystackSecretKey = (Deno.env.get("PAYSTACK_SECRET_KEY") ?? "").trim()
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!

  // â”€â”€ Auth: require x-cron-secret â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  if (cronSecret) {
    const incomingSecret = req.headers.get("x-cron-secret")
    if (incomingSecret !== cronSecret) {
      console.error("REJECTED: invalid or missing x-cron-secret")
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }
  } else {
    console.warn("CRON_SECRET not set â€” running in unsecured mode (configure for production)")
  }

  if (!paystackSecretKey) {
    console.error("PAYSTACK_SECRET_KEY not configured")
    return new Response(JSON.stringify({ error: "Payment service not configured" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  }

  const supabase = createClient(supabaseUrl, supabaseServiceKey)

  // â”€â”€ Fetch subscriptions due for renewal â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  const { data: dueRows, error: fetchError } = await supabase
    .from("subscriptions_due_for_renewal")
    .select("*")

  if (fetchError) {
    console.error("Failed to fetch due subscriptions:", fetchError.message)
    return new Response(JSON.stringify({ error: fetchError.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  }

  const due = (dueRows ?? []) as DueSubscription[]
  console.log(`Found ${due.length} subscription(s) due for renewal`)

  const results: RenewalResult[] = []

  for (const sub of due) {
    const result = await renewSubscription(supabase, paystackSecretKey, sub)
    results.push(result)
  }

  const succeeded = results.filter((r) => r.status === "success").length
  const failed = results.filter((r) => r.status === "failed").length
  const skipped = results.filter((r) => r.status === "skipped").length

  console.log(`Renewal run complete: ${succeeded} succeeded, ${failed} failed, ${skipped} skipped`)

  return new Response(
    JSON.stringify({ processed: due.length, succeeded, failed, skipped, results }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  )
})

// â”€â”€ Renew a single subscription â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
async function renewSubscription(
  supabase: any,
  paystackSecretKey: string,
  sub: DueSubscription,
): Promise<RenewalResult> {
  const { subscription_id, user_id, email, renewal_charge_cents } = sub

  // Fall back to R99 (9900 cents) for standard subscriptions that predate the intro campaign migration
  const chargeAmountCents = renewal_charge_cents ?? 9900

  console.log(`Processing renewal for user=${user_id} sub=${subscription_id} amount=${chargeAmountCents}`)

  // â”€â”€ Skip if no saved card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  if (!sub.authorization_code) {
    console.warn(`No primary card for user ${user_id} â€” skipping`)
    await logRenewalResult(supabase, {
      user_id,
      subscription_id,
      status: "failed",
      failure_reason: "No saved primary card on file",
      amount_cents: chargeAmountCents,
    })
    await markSubscriptionFailed(supabase, subscription_id, user_id, "No saved primary card on file")
    return { user_id, subscription_id, status: "skipped", reason: "no_card" }
  }

  const { data: claimed, error: claimError } = await supabase.rpc(
    "claim_subscription_renewal",
    { p_subscription_id: subscription_id },
  )
  if (claimError) {
    console.error(`Failed to claim renewal for ${subscription_id}:`, claimError.message)
    return { user_id, subscription_id, status: "failed", reason: "claim_error" }
  }
  if (!claimed) {
    console.log(`Skipping ${subscription_id}: renewal already claimed or completed`)
    return { user_id, subscription_id, status: "skipped", reason: "already_claimed" }
  }

  // The due-subscriptions view is a snapshot. Recheck after claiming so a
  // cancellation committed while this worker was fetching cannot be charged.
  const { data: currentSubscription, error: currentSubscriptionError } = await supabase
    .from("subscriptions")
    .select("status, auto_renew, renewal_in_progress_at")
    .eq("id", subscription_id)
    .maybeSingle()
  if (
    currentSubscriptionError ||
    currentSubscription?.status !== "active" ||
    currentSubscription?.auto_renew !== true ||
    !currentSubscription?.renewal_in_progress_at
  ) {
    await supabase.rpc("release_subscription_renewal_claim", {
      p_subscription_id: subscription_id,
    })
    console.log(`Skipping ${subscription_id}: subscription was cancelled or changed`)
    return { user_id, subscription_id, status: "skipped", reason: "cancelled_or_changed" }
  }

  // â”€â”€ Charge via Paystack charge_authorization â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  const chargeEmail = sub.card_email || email
  const amountKobo = chargeAmountCents // Paystack uses kobo (ZAR cents)
  const reference = `renewal_${subscription_id}_${new Date(sub.current_period_end).getTime()}`

  let paystackResponse: any
  try {
    const resp = await fetch("https://api.paystack.co/transaction/charge_authorization", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${paystackSecretKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        authorization_code: sub.authorization_code,
        email: chargeEmail,
        amount: amountKobo,
        reference,
        metadata: {
          payment_type: "subscription_renewal",
          user_id,
          subscription_id,
          plan_type: sub.plan_type,
        },
      }),
    })
    paystackResponse = await resp.json()
  } catch (networkErr: any) {
    console.error(`Network error charging user ${user_id}:`, networkErr.message)
    await logRenewalResult(supabase, {
      user_id,
      subscription_id,
      status: "failed",
      failure_reason: `Network error: ${networkErr.message}`,
      amount_cents: chargeAmountCents,
    })
    await markSubscriptionFailed(supabase, subscription_id, user_id, "Payment network error")
    return { user_id, subscription_id, status: "failed", reason: "network_error" }
  }

  const chargeStatus = paystackResponse?.data?.status
  const chargeRef = paystackResponse?.data?.reference ?? reference

  console.log(`Paystack charge_authorization: status=${chargeStatus} ref=${chargeRef}`)

  // â”€â”€ Handle success â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  if (chargeStatus === "success") {
    await extendSubscription(supabase, sub, chargeRef)
    await logRenewalResult(supabase, {
      user_id,
      subscription_id,
      status: "success",
      reference: chargeRef,
      amount_cents: chargeAmountCents,
    })
    await notifyUser(supabase, user_id, chargeAmountCents, chargeRef)
    console.log(`Renewal SUCCESS for user ${user_id}`)
    return { user_id, subscription_id, status: "success", reference: chargeRef, amount_cents: chargeAmountCents }
  }

  // â”€â”€ Handle pending (card 3DS / OTP required â€” cannot complete server-side) â”€
  if (chargeStatus === "send_otp" || chargeStatus === "send_birthday" || chargeStatus === "open_url") {
    console.warn(`User ${user_id} card requires interactive auth (${chargeStatus}) â€” cannot auto-renew`)
    await logRenewalResult(supabase, {
      user_id,
      subscription_id,
      status: "failed",
      failure_reason: `Card requires interactive authentication: ${chargeStatus}`,
      amount_cents: chargeAmountCents,
      reference: chargeRef,
    })
    await markSubscriptionFailed(
      supabase,
      subscription_id,
      user_id,
      "Card requires interactive authentication â€” please renew manually in the app",
    )
    return { user_id, subscription_id, status: "failed", reason: chargeStatus }
  }

  // â”€â”€ Handle failure â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  const failureMsg = paystackResponse?.data?.gateway_response
    || paystackResponse?.message
    || "Payment declined"

  console.warn(`Renewal FAILED for user ${user_id}: ${failureMsg}`)
  await logRenewalResult(supabase, {
    user_id,
    subscription_id,
    status: "failed",
    failure_reason: failureMsg,
    amount_cents: chargeAmountCents,
    reference: chargeRef,
  })
  await markSubscriptionFailed(supabase, subscription_id, user_id, failureMsg)
  return { user_id, subscription_id, status: "failed", reason: failureMsg }
}

// â”€â”€ Extend subscription by 30 days and refresh QR code â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
async function extendSubscription(
  supabase: any,
  sub: DueSubscription,
  reference: string,
) {
  const now = new Date()
  const oldEnd = new Date(sub.current_period_end)
  // Extend from expiry date (not from now) to avoid drift
  const baseDate = oldEnd > now ? oldEnd : now
  const newPeriodEnd = new Date(baseDate.getTime() + 30 * 24 * 60 * 60 * 1000)

  // Update subscription
  await supabase
    .from("subscriptions")
    .update({
      status: "active",
      current_period_start: now.toISOString(),
      current_period_end: newPeriodEnd.toISOString(),
      renewal_in_progress_at: null,
      updated_at: now.toISOString(),
    })
    .eq("id", sub.subscription_id)

  // Ensure profile is marked active
  await supabase
    .from("profiles")
    .update({
      subscription: "active",
      updated_at: now.toISOString(),
    })
    .eq("id", sub.user_id)

  // Extend QR code expiry to match new period
  const { data: existingQR } = await supabase
    .from("user_qr_codes")
    .select("id")
    .eq("user_id", sub.user_id)
    .eq("is_active", true)
    .maybeSingle()

  if (existingQR) {
    await supabase
      .from("user_qr_codes")
      .update({
        expires_at: newPeriodEnd.toISOString(),
        updated_at: now.toISOString(),
      })
      .eq("id", existingQR.id)
  } else {
    // Regenerate if missing
    await supabase.from("user_qr_codes").insert({
      user_id: sub.user_id,
      qr_code: `QR_${sub.user_id}_${now.getTime()}`,
      is_active: true,
      expires_at: newPeriodEnd.toISOString(),
      created_at: now.toISOString(),
      updated_at: now.toISOString(),
    })
  }

  console.log(`Extended subscription ${sub.subscription_id} to ${newPeriodEnd.toISOString()}`)
}

// â”€â”€ Mark subscription as payment_failed â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
async function markSubscriptionFailed(
  supabase: any,
  subscriptionId: string,
  userId: string,
  reason: string,
) {
  await supabase.rpc("release_subscription_renewal_claim", {
    p_subscription_id: subscriptionId,
  })

  await supabase
    .from("subscriptions")
    .update({
      status: "payment_failed",
      updated_at: new Date().toISOString(),
    })
    .eq("id", subscriptionId)

  // Update profile subscription field so NavigationService routes to
  // PaymentRequiredScreen on next login instead of MembersHomePage.
  await supabase
    .from("profiles")
    .update({ subscription: "payment_failed", updated_at: new Date().toISOString() })
    .eq("id", userId)

  // Send in-app payment_failure notification so PaymentFailureAlert banner
  // appears in the app on next open.
  await supabase.from("notifications").insert({
    user_id: userId,
    title: "Subscription Payment Failed",
    message: "We couldn't renew your Local Lekker subscription. Please update your payment method in the app to continue enjoying discounts.",
    type: "payment_failure",
    is_read: false,
    data: { reason, source: "scheduled_renewal" },
  })
}

// â”€â”€ Log renewal attempt to subscription_renewals â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
async function logRenewalResult(
  supabase: any,
  params: {
    user_id: string
    subscription_id: string
    status: "success" | "failed"
    reference?: string
    amount_cents?: number
    failure_reason?: string
  },
) {
  await supabase.from("subscription_renewals").insert({
    user_id: params.user_id,
    subscription_id: params.subscription_id,
    payment_method: params.reference ?? null,  // stores Paystack reference
    amount: (params.amount_cents ?? 9900) / 100,  // NOT NULL column, fallback to 99.00
    status: params.status,
    error_message: params.failure_reason ?? null,
    qr_code_updated: params.status === "success",
    renewal_date: new Date().toISOString(),
  })
}

// â”€â”€ Send success notification â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
async function notifyUser(
  supabase: any,
  userId: string,
  amountCents: number,
  reference: string,
) {
  const amountRands = (amountCents / 100).toFixed(2)
  const newExpiry = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)

  await supabase.from("notifications").insert({
    user_id: userId,
    title: "Subscription Renewed",
    message: `Your Local Lekker subscription has been renewed (R${amountRands}). Valid until ${newExpiry.toLocaleDateString("en-ZA")}.`,
    type: "subscription_renewal",
    is_read: false,
    data: {
      reference,
      amount: amountCents / 100,
      expires_at: newExpiry.toISOString(),
      source: "scheduled_renewal",
    },
  })
}
