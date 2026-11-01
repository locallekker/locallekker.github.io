// Scheduled Deal Expiry Worker
//
// Runs daily via pg_cron (see add_deal_expiry_management.sql).
// 1. Finds deals expiring tomorrow → emails the trusted partner + admin
//    so the partner has time to publish a replacement deal.
// 2. Finds deals that have already expired (and are still flagged
//    is_active=true) → emails the partner + admin, then deactivates
//    them so they disappear from member-facing listings.
//
// All sends are idempotent — a row in `deal_expiry_notifications`
// (unique on deal_id + notification_type + recipient_role) prevents
// re-sending if the worker runs more than once on the same day.
//
// Auth: x-cron-secret header (set CRON_SECRET in edge function secrets).
//
// Environment variables:
//   SUPABASE_URL              – auto-set by Supabase
//   SUPABASE_SERVICE_ROLE_KEY – auto-set by Supabase
//   CRON_SECRET               – shared secret with pg_cron job
//   ADMIN_NOTIFY_EMAIL        – admin recipient (default: admin@locallekkerclub.co.za)
//   SMTP_HOST                 – default: smtp.gmail.com
//   SMTP_PORT                 – default: 465
//   SMTP_USER                 – Gmail address used to send
//   SMTP_PASS                 – Gmail app password

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts"
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
}

type NotificationType = "expiring_tomorrow" | "expired"
type RecipientRole = "trusted_partner" | "admin"

interface DealRow {
  deal_id: string
  deal_name: string | null
  owner_user_id: string | null
  business_id: string | null
  deal_category: string | null
  city: string | null
  end_date: string | null
  business_name: string | null
  business_email: string | null
  owner_email: string | null
  owner_name: string | null
}

interface SendResult {
  deal_id: string
  recipient_role: RecipientRole
  recipient_email: string | null
  email_sent: boolean
  skipped_reason?: string
  error?: string
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  // ── Auth ────────────────────────────────────────────────────────
  const cronSecret = Deno.env.get("CRON_SECRET")
  if (cronSecret) {
    if (req.headers.get("x-cron-secret") !== cronSecret) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }
  } else {
    console.warn("CRON_SECRET not set — running in unsecured mode")
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  const adminEmail =
    Deno.env.get("ADMIN_NOTIFY_EMAIL") ?? "admin@locallekkerclub.co.za"

  const supabase = createClient(supabaseUrl, serviceRoleKey)

  // ── SMTP setup ──────────────────────────────────────────────────
  const smtpHost = Deno.env.get("SMTP_HOST") ?? "smtp.gmail.com"
  const smtpPort = parseInt(Deno.env.get("SMTP_PORT") ?? "465")
  const smtpUser = Deno.env.get("SMTP_USER") ?? ""
  const smtpPass = Deno.env.get("SMTP_PASS") ?? ""
  const smtpConfigured = !!(smtpUser && smtpPass)
  if (!smtpConfigured) {
    console.warn("SMTP credentials not configured — emails will be skipped")
  }

  const smtp = smtpConfigured
    ? new SMTPClient({
        connection: {
          hostname: smtpHost,
          port: smtpPort,
          tls: true,
          auth: { username: smtpUser, password: smtpPass },
        },
      })
    : null

  const allResults: SendResult[] = []

  try {
    // ── 1. EXPIRING TOMORROW ────────────────────────────────────────
    const { data: expiringRows, error: expiringErr } = await supabase
      .from("tp_deals_expiring_tomorrow")
      .select("*")

    if (expiringErr) {
      console.error("Failed to fetch expiring deals:", expiringErr.message)
    } else {
      const expiring = (expiringRows ?? []) as DealRow[]
      console.log(`Found ${expiring.length} deal(s) expiring tomorrow`)
      for (const deal of expiring) {
        allResults.push(
          ...(await handleDeal({
            deal,
            type: "expiring_tomorrow",
            adminEmail,
            smtp,
            smtpUser,
            supabase,
          })),
        )
      }
    }

    // ── 2. EXPIRED (still active) ───────────────────────────────────
    const { data: expiredRows, error: expiredErr } = await supabase
      .from("tp_deals_expired_today")
      .select("*")

    if (expiredErr) {
      console.error("Failed to fetch expired deals:", expiredErr.message)
    } else {
      const expired = (expiredRows ?? []) as DealRow[]
      console.log(`Found ${expired.length} deal(s) that have expired`)
      for (const deal of expired) {
        allResults.push(
          ...(await handleDeal({
            deal,
            type: "expired",
            adminEmail,
            smtp,
            smtpUser,
            supabase,
          })),
        )
      }
    }

    // ── 3. Deactivate overdue deals ─────────────────────────────────
    // Done AFTER sending so the partner is emailed before the deal
    // disappears from member-facing listings.
    const { data: deactivated, error: deactivateErr } = await supabase.rpc(
      "expire_overdue_deals",
    )
    if (deactivateErr) {
      console.error("Failed to deactivate overdue deals:", deactivateErr.message)
    } else {
      console.log(
        `Deactivated ${Array.isArray(deactivated) ? deactivated.length : 0} overdue deal(s)`,
      )
    }
  } finally {
    if (smtp) {
      try {
        await smtp.close()
      } catch (_) {
        /* ignore */
      }
    }
  }

  const summary = {
    total: allResults.length,
    sent: allResults.filter((r) => r.email_sent).length,
    skipped: allResults.filter((r) => r.skipped_reason).length,
    failed: allResults.filter((r) => r.error).length,
  }

  return new Response(
    JSON.stringify({ success: true, summary, results: allResults }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  )
})

// ── Per-deal handler ──────────────────────────────────────────────
async function handleDeal(args: {
  deal: DealRow
  type: NotificationType
  adminEmail: string
  smtp: SMTPClient | null
  smtpUser: string
  supabase: SupabaseClient
}): Promise<SendResult[]> {
  const { deal, type, adminEmail, smtp, smtpUser, supabase } = args
  const out: SendResult[] = []

  const partnerEmail =
    (deal.business_email && deal.business_email.trim()) ||
    (deal.owner_email && deal.owner_email.trim()) ||
    null

  // Partner notification
  out.push(
    await sendIfNotSent({
      supabase,
      smtp,
      smtpUser,
      deal,
      type,
      role: "trusted_partner",
      to: partnerEmail,
      subject: subjectFor(type, deal, "trusted_partner"),
      body: bodyFor(type, deal, "trusted_partner"),
    }),
  )

  // Admin notification
  out.push(
    await sendIfNotSent({
      supabase,
      smtp,
      smtpUser,
      deal,
      type,
      role: "admin",
      to: adminEmail,
      subject: subjectFor(type, deal, "admin"),
      body: bodyFor(type, deal, "admin"),
    }),
  )

  return out
}

// ── Idempotent send + logging ─────────────────────────────────────
async function sendIfNotSent(args: {
  supabase: SupabaseClient
  smtp: SMTPClient | null
  smtpUser: string
  deal: DealRow
  type: NotificationType
  role: RecipientRole
  to: string | null
  subject: string
  body: string
}): Promise<SendResult> {
  const { supabase, smtp, smtpUser, deal, type, role, to, subject, body } = args

  // Already sent? (UNIQUE constraint on deal_id + type + role)
  const { data: existing, error: lookupErr } = await supabase
    .from("deal_expiry_notifications")
    .select("id, email_sent")
    .eq("deal_id", deal.deal_id)
    .eq("notification_type", type)
    .eq("recipient_role", role)
    .maybeSingle()

  if (lookupErr) {
    console.error("Lookup failed:", lookupErr.message)
  }
  if (existing) {
    return {
      deal_id: deal.deal_id,
      recipient_role: role,
      recipient_email: to,
      email_sent: false,
      skipped_reason: "already_sent",
    }
  }

  if (!to) {
    await supabase.from("deal_expiry_notifications").insert({
      deal_id: deal.deal_id,
      notification_type: type,
      recipient_role: role,
      recipient_email: null,
      email_sent: false,
      error_message: "no_recipient_email",
    })
    return {
      deal_id: deal.deal_id,
      recipient_role: role,
      recipient_email: null,
      email_sent: false,
      skipped_reason: "no_recipient_email",
    }
  }

  if (!smtp) {
    await supabase.from("deal_expiry_notifications").insert({
      deal_id: deal.deal_id,
      notification_type: type,
      recipient_role: role,
      recipient_email: to,
      email_sent: false,
      error_message: "smtp_not_configured",
    })
    return {
      deal_id: deal.deal_id,
      recipient_role: role,
      recipient_email: to,
      email_sent: false,
      skipped_reason: "smtp_not_configured",
    }
  }

  try {
    const escapeHtml = (s: string) => s
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;")
    const htmlBody = `<!DOCTYPE html><html><body style="font-family:Arial,sans-serif;color:#222;"><pre style="font-family:Arial,sans-serif;white-space:pre-wrap;margin:0;">${escapeHtml(body)}</pre></body></html>`
    await smtp.send({ from: smtpUser, to, subject, content: body, html: htmlBody })
    await supabase.from("deal_expiry_notifications").insert({
      deal_id: deal.deal_id,
      notification_type: type,
      recipient_role: role,
      recipient_email: to,
      email_sent: true,
    })
    return {
      deal_id: deal.deal_id,
      recipient_role: role,
      recipient_email: to,
      email_sent: true,
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    console.error(`Email send failed for deal ${deal.deal_id} → ${to}:`, msg)
    await supabase.from("deal_expiry_notifications").insert({
      deal_id: deal.deal_id,
      notification_type: type,
      recipient_role: role,
      recipient_email: to,
      email_sent: false,
      error_message: msg,
    })
    return {
      deal_id: deal.deal_id,
      recipient_role: role,
      recipient_email: to,
      email_sent: false,
      error: msg,
    }
  }
}

// ── Email content ─────────────────────────────────────────────────
function subjectFor(
  type: NotificationType,
  deal: DealRow,
  role: RecipientRole,
): string {
  const biz = deal.business_name ?? "Local Business"
  const name = deal.deal_name ?? "Deal"
  if (type === "expiring_tomorrow") {
    return role === "admin"
      ? `[Local Lekker] Deal expiring tomorrow – ${name} (${biz})`
      : `Your Local Lekker deal "${name}" expires tomorrow`
  }
  return role === "admin"
    ? `[Local Lekker] Deal expired – ${name} (${biz})`
    : `Your Local Lekker deal "${name}" has expired`
}

function bodyFor(
  type: NotificationType,
  deal: DealRow,
  role: RecipientRole,
): string {
  const biz = deal.business_name ?? "Local Business"
  const name = deal.deal_name ?? "Deal"
  const owner = deal.owner_name ?? "Partner"
  const endDate = deal.end_date ?? "unknown"
  const city = deal.city ?? "—"
  const category = deal.deal_category ?? "—"

  if (type === "expiring_tomorrow" && role === "trusted_partner") {
    return `Hi ${owner},

Heads up – your Local Lekker deal is scheduled to expire tomorrow.

Deal: ${name}
Business: ${biz}
Category: ${category}
City: ${city}
Expiry date: ${endDate}

To stay visible to members, please log into the Local Lekker app and either:
  • Extend / update this deal, or
  • Publish a replacement deal.

Once the deal expires it will no longer be shown to members until a new
active deal is published.

—
Local Lekker
support@locallekker.co.za
`
  }

  if (type === "expiring_tomorrow" && role === "admin") {
    return `Admin notice – a trusted partner deal is expiring tomorrow.

Partner: ${owner}
Business: ${biz}
Deal: ${name}
Category: ${category}
City: ${city}
Expiry date: ${endDate}
Partner email: ${deal.business_email ?? deal.owner_email ?? "(none)"}

The partner has been notified. Reach out if they need help publishing a
replacement deal.

—
Local Lekker Admin Notifications
`
  }

  if (type === "expired" && role === "trusted_partner") {
    return `Hi ${owner},

Your Local Lekker deal has expired and is no longer visible to members.

Deal: ${name}
Business: ${biz}
Category: ${category}
City: ${city}
Expiry date: ${endDate}

Your business will not appear in member listings until you publish a
new active deal. Log into the Local Lekker app to add or extend a deal.

—
Local Lekker
support@locallekker.co.za
`
  }

  // expired + admin
  return `Admin notice – a trusted partner deal has expired.

Partner: ${owner}
Business: ${biz}
Deal: ${name}
Category: ${category}
City: ${city}
Expiry date: ${endDate}
Partner email: ${deal.business_email ?? deal.owner_email ?? "(none)"}

The deal has been deactivated and the business is no longer shown to
members until a new deal is published. The partner has been notified –
please follow up if they need assistance.

—
Local Lekker Admin Notifications
`
}
