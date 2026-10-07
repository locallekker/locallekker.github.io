// Scheduled Payment Reconciliation Worker
//
// Safety net for members who genuinely paid on Paystack but whose activation
// was never recorded locally (app killed before verify AND webhook missed/
// failed for that one transaction — see /memories/repo/pending_activation_audit_2026-09.md).
// Runs periodically via pg_cron, finds candidates (accepted terms, has a
// Paystack customer code, but no active subscription row), asks Paystack
// directly for that customer's transaction history, and auto-activates using
// the exact same logic as paystack-webhook's recoverSubscriptionPayment /
// recoverIntroCampaignPayment. Ambiguous cases are flagged for manual review
// instead of guessed at.
//
// Invocation: HTTP POST from pg_cron via net.http_post, or manually.
// Auth: x-cron-secret header (reuses CRON_SECRET secret already configured
// for scheduled-renewal-worker — Supabase edge function secrets are shared
// project-wide).
//
// Environment variables required:
//   SUPABASE_URL              – auto-set by Supabase
//   SUPABASE_SERVICE_ROLE_KEY – auto-set by Supabase
//   PAYSTACK_SECRET_KEY       – Paystack live secret key
//   CRON_SECRET               – shared secret to authorise cron invocations

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
}

interface Candidate {
  user_id: string
  email: string
  name: string | null
  surname: string | null
  paystack_customer_code: string
}

type ActionResult =
  | { user_id: string; email: string; action: "activated_subscription"; reference: string }
  | { user_id: string; email: string; action: "activated_intro"; reference: string }
  | { user_id: string; email: string; action: "flagged_review"; detail: string }
  | { user_id: string; email: string; action: "no_payment_found" }
  | { user_id: string; email: string; action: "error"; detail: string }

// ── Date helpers (mirror SubscriptionService / paystack-webhook) ──────
function oneCalendarMonthFrom(from: Date): Date {
  const year = from.getFullYear()
  const month = from.getMonth()
  const day = from.getDate()
  const maxDay = new Date(year, month + 2, 0).getDate()
  const clampedDay = day > maxDay ? maxDay : day
  return new Date(year, month + 1, clampedDay, from.getHours(), from.getMinutes(), from.getSeconds())
}

function addMonths(from: Date, months: number): Date {
  return new Date(from.getFullYear(), from.getMonth() + months, from.getDate(), from.getHours(), from.getMinutes(), from.getSeconds())
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  const cronSecret = Deno.env.get("CRON_SECRET")
  const paystackSecretKey = (Deno.env.get("PAYSTACK_SECRET_KEY") ?? "").trim()
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!

  if (cronSecret) {
    if (req.headers.get("x-cron-secret") !== cronSecret) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }
  } else {
    console.warn("CRON_SECRET not set — running in unsecured mode (configure for production)")
  }

  if (!paystackSecretKey) {
    console.error("PAYSTACK_SECRET_KEY not configured")
    return new Response(JSON.stringify({ error: "Payment service not configured" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  }

  const supabase = createClient(supabaseUrl, supabaseServiceKey)

  const { data: candidateRows, error: fetchError } = await supabase
    .from("pending_payment_reconciliation_candidates")
    .select("*")

  if (fetchError) {
    console.error("Failed to fetch candidates:", fetchError.message)
    return new Response(JSON.stringify({ error: fetchError.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  }

  const candidates = (candidateRows ?? []) as Candidate[]
  console.log(`Found ${candidates.length} pending-payment reconciliation candidate(s)`)

  const results: ActionResult[] = []
  for (const candidate of candidates) {
    try {
      const result = await reconcileCandidate(supabase, paystackSecretKey, candidate)
      results.push(result)
      await logResult(supabase, candidate, result)
    } catch (err: any) {
      console.error(`Error reconciling ${candidate.email}:`, err.message)
      const errorResult: ActionResult = { user_id: candidate.user_id, email: candidate.email, action: "error", detail: err.message }
      results.push(errorResult)
      await logResult(supabase, candidate, errorResult)
    }
  }

  const activated = results.filter((r) => r.action === "activated_subscription" || r.action === "activated_intro")
  const flagged = results.filter((r) => r.action === "flagged_review" || r.action === "error")

  if (activated.length > 0 || flagged.length > 0) {
    await notifyAdmins(supabase, activated, flagged)
  }

  console.log(`Reconciliation run complete: ${activated.length} activated, ${flagged.length} flagged, ${results.length - activated.length - flagged.length} no payment found`)

  return new Response(
    JSON.stringify({ processed: candidates.length, activated: activated.length, flagged: flagged.length, results }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  )
})

// ── Reconcile a single candidate against Paystack's transaction history ──
async function reconcileCandidate(supabase: any, paystackSecretKey: string, candidate: Candidate): Promise<ActionResult> {
  const { user_id: userId, email, paystack_customer_code: customerCode } = candidate

  const resp = await fetch(
    `https://api.paystack.co/transaction?customer=${encodeURIComponent(customerCode)}&status=success&perPage=5`,
    { headers: { Authorization: `Bearer ${paystackSecretKey}` } },
  )
  const body = await resp.json()

  if (!resp.ok || !Array.isArray(body?.data)) {
    return { user_id: userId, email, action: "error", detail: body?.message ?? `Paystack list-transactions failed (${resp.status})` }
  }

  const successfulTx = body.data.find((tx: any) => tx.status === "success")
  if (!successfulTx) {
    return { user_id: userId, email, action: "no_payment_found" }
  }

  const metadata = successfulTx.metadata ?? {}
  const reference = successfulTx.reference as string
  const amount = successfulTx.amount as number
  const paymentType = metadata.payment_type

  if (paymentType === "subscription") {
    await activateStandardSubscription(supabase, userId, reference, metadata)
    return { user_id: userId, email, action: "activated_subscription", reference }
  }

  if (paymentType === "promotion_intro" && metadata.promotion_id && metadata.participant_id) {
    await activateIntroSubscription(supabase, userId, reference, amount, metadata)
    return { user_id: userId, email, action: "activated_intro", reference }
  }

  // Legacy/no-metadata standard R99 charge — only auto-activate the plain
  // subscription path; never guess at an intro-campaign promo linkage.
  if (!paymentType && amount === 9900) {
    await activateStandardSubscription(supabase, userId, reference, {})
    return { user_id: userId, email, action: "activated_subscription", reference }
  }

  return {
    user_id: userId,
    email,
    action: "flagged_review",
    detail: `Successful Paystack tx ${reference} (amount=${amount}, payment_type=${paymentType ?? "none"}) could not be auto-matched — needs manual review`,
  }
}

// ── Mirrors paystack-webhook recoverSubscriptionPayment ────────────────
async function activateStandardSubscription(supabase: any, userId: string, reference: string, metadata: any) {
  const { data: existingSub } = await supabase
    .from("subscriptions")
    .select("id, status, current_period_end")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle()

  if (existingSub?.status === "active") return // already handled elsewhere

  const now = new Date()
  let baseDate = now
  if (existingSub?.current_period_end) {
    const existing = new Date(existingSub.current_period_end)
    if (existing > now) baseDate = existing
  }
  const newExpiry = oneCalendarMonthFrom(baseDate)
  const renewalChargeCents = Number(metadata.renewal_charge_cents ?? 9900)

  if (existingSub) {
    await supabase
      .from("subscriptions")
      .update({
        status: "active",
        plan_type: "subscription",
        current_period_start: now.toISOString(),
        current_period_end: newExpiry.toISOString(),
        auto_renew: true,
        renewal_charge_cents: renewalChargeCents,
        updated_at: now.toISOString(),
      })
      .eq("id", existingSub.id)
  } else {
    await supabase.from("subscriptions").insert({
      user_id: userId,
      status: "active",
      plan_type: "subscription",
      current_period_start: now.toISOString(),
      current_period_end: newExpiry.toISOString(),
      auto_renew: true,
      renewal_charge_cents: renewalChargeCents,
      created_at: now.toISOString(),
      updated_at: now.toISOString(),
    })
  }

  await supabase
    .from("profiles")
    .update({ subscription: "active", is_deactivated: false, deactivation_reason: null, deactivated_at: null, updated_at: now.toISOString() })
    .eq("id", userId)

  await ensureActiveQRCode(supabase, userId, newExpiry)

  await supabase.from("notifications").insert({
    user_id: userId,
    title: "Subscription Activated",
    message: `Your Local Lekker subscription is active until ${newExpiry.toLocaleDateString("en-ZA")}.`,
    type: "subscription_renewal",
    is_read: false,
    data: { reference, expires_at: newExpiry.toISOString(), source: "scheduled_reconciliation" },
  })
}

// ── Mirrors paystack-webhook recoverIntroCampaignPayment ───────────────
async function activateIntroSubscription(supabase: any, userId: string, reference: string, amount: number, metadata: any) {
  const promotionId = metadata.promotion_id
  const participantId = metadata.participant_id

  const { data: existingSub } = await supabase
    .from("subscriptions")
    .select("id, status")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle()

  if (existingSub?.status === "active") return

  let isLifetime = false
  let effectiveFreeMonths = Number(metadata.free_months ?? 0)
  const { data: promoRow } = await supabase.from("promotions").select("free_months").eq("id", promotionId).maybeSingle()
  if (promoRow) {
    if (promoRow.free_months === null || promoRow.free_months === undefined) {
      isLifetime = true
    } else {
      effectiveFreeMonths = Number(promoRow.free_months)
    }
  }

  const now = new Date()
  const monthsToGrant = isLifetime ? 1200 : (effectiveFreeMonths > 0 ? effectiveFreeMonths : 1)
  const freePeriodEnd = addMonths(now, monthsToGrant)
  const initialChargeCents = Number(metadata.initial_charge_cents ?? amount ?? 100)
  const renewalChargeCents = Number(metadata.renewal_charge_cents ?? 9900)

  await ensureActiveQRCode(supabase, userId, freePeriodEnd)

  const subscriptionData: Record<string, unknown> = {
    user_id: userId,
    plan_type: "promotion_intro",
    promotion_id: promotionId,
    promo_participant_id: participantId,
    current_period_start: now.toISOString(),
    current_period_end: freePeriodEnd.toISOString(),
    free_period_end: freePeriodEnd.toISOString(),
    initial_charge_cents: initialChargeCents,
    renewal_charge_cents: renewalChargeCents,
    intro_charge_reference: reference,
    intro_charge_paid_at: now.toISOString(),
    status: "active",
    auto_renew: true,
    updated_at: now.toISOString(),
  }

  if (existingSub) {
    await supabase.from("subscriptions").update(subscriptionData).eq("id", existingSub.id)
  } else {
    subscriptionData.created_at = now.toISOString()
    await supabase.from("subscriptions").insert(subscriptionData)
  }

  await supabase
    .from("profiles")
    .update({ subscription: "active", is_deactivated: false, deactivation_reason: null, deactivated_at: null, updated_at: now.toISOString() })
    .eq("id", userId)

  await supabase
    .from("promotion_participant_emails")
    .update({ is_claimed: true, claimed_by: userId, claimed_at: now.toISOString() })
    .eq("id", participantId)

  await supabase.from("notifications").insert({
    user_id: userId,
    title: "Entry Offer Activated",
    message: isLifetime
      ? "Welcome to Local Lekker! Your lifetime membership is now active."
      : `Welcome to Local Lekker! Enjoy ${effectiveFreeMonths} month(s) free until ${freePeriodEnd.toLocaleDateString("en-ZA")}.`,
    type: "subscription_renewal",
    is_read: false,
    data: { reference, expires_at: freePeriodEnd.toISOString(), source: "scheduled_reconciliation" },
  })
}

async function ensureActiveQRCode(supabase: any, userId: string, expiresAt: Date) {
  const { data: existingQR } = await supabase.from("user_qr_codes").select("id").eq("user_id", userId).eq("is_active", true).maybeSingle()
  if (existingQR) return

  const { data: profile } = await supabase.from("profiles").select("name, surname").eq("id", userId).maybeSingle()
  const now = new Date()
  await supabase.from("user_qr_codes").insert({
    user_id: userId,
    qr_code: `QR_${userId}_${now.getTime()}`,
    name: profile?.name ?? "Unknown",
    surname: profile?.surname ?? "Unknown",
    is_active: true,
    expires_at: expiresAt.toISOString(),
    created_at: now.toISOString(),
    updated_at: now.toISOString(),
  })
}

async function logResult(supabase: any, candidate: Candidate, result: ActionResult) {
  await supabase.from("payment_reconciliation_log").insert({
    user_id: candidate.user_id,
    email: candidate.email,
    action: result.action,
    paystack_reference: "reference" in result ? result.reference : null,
    detail: "detail" in result ? result.detail : null,
  })
}

async function notifyAdmins(supabase: any, activated: ActionResult[], flagged: ActionResult[]) {
  const { data: admins } = await supabase.from("profiles").select("id").eq("role", "admin")
  if (!admins || admins.length === 0) return

  const lines: string[] = []
  if (activated.length > 0) {
    lines.push(`Auto-activated ${activated.length} member(s): ${activated.map((r) => r.email).join(", ")}`)
  }
  if (flagged.length > 0) {
    lines.push(`${flagged.length} member(s) need manual review: ${flagged.map((r) => r.email).join(", ")}`)
  }
  const message = lines.join(" ")

  const notifications = admins.map((admin: any) => ({
    user_id: admin.id,
    title: "Payment Reconciliation Report",
    message,
    type: "payment_reconciliation",
    is_read: false,
    data: { activated: activated.map((r) => r.email), flagged: flagged.map((r) => r.email) },
  }))

  await supabase.from("notifications").insert(notifications)
}
