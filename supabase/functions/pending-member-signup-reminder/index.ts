import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type, x-cron-secret",
}

interface PendingSignupReminder {
    user_id: string
    email: string
    member_name: string
    tracking_token: string
}

serve(async (req) => {
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders })
    }

    const cronSecret = Deno.env.get("CRON_SECRET")
    if (cronSecret && req.headers.get("x-cron-secret") !== cronSecret) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), {
            status: 401,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
        })
    }

    const smtpUser = Deno.env.get("SMTP_USER") ?? ""
    const smtpPass = Deno.env.get("SMTP_PASS") ?? ""
    if (!smtpUser || !smtpPass) {
        return new Response(JSON.stringify({ error: "SMTP is not configured" }), {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
        })
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const supabase = createClient(
        supabaseUrl,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )
    const smtp = new SMTPClient({
        connection: {
            hostname: Deno.env.get("SMTP_HOST") ?? "smtp.gmail.com",
            port: parseInt(Deno.env.get("SMTP_PORT") ?? "465"),
            tls: true,
            auth: { username: smtpUser, password: smtpPass },
        },
    })

    try {
        const { data, error } = await supabase.rpc("claim_pending_member_signup_reminders")
        if (error) throw error

        const reminders = (data ?? []) as PendingSignupReminder[]
        let sent = 0
        let failed = 0

        for (const reminder of reminders) {
            const trackingToken = encodeURIComponent(reminder.tracking_token)
            const appOpenUrl = `${supabaseUrl}/functions/v1/open-local-lekker?action=open&token=${trackingToken}`
            const optOutUrl = `${supabaseUrl}/functions/v1/open-local-lekker?action=opt_out&token=${trackingToken}`
            const body = `Hi ${reminder.member_name},

You started your Local Lekker membership signup 24 hours ago, but it is not complete yet.

Complete your subscription to activate your membership and start accessing local deals:
${appOpenUrl}

If you need help, contact support@locallekker.co.za.

To stop receiving signup reminders, opt out here:
${optOutUrl}

Local Lekker
`

            try {
                await smtp.send({
                    from: smtpUser,
                    to: reminder.email,
                    subject: "Complete your Local Lekker signup",
                    content: body,
                      html: buildHtmlEmail(reminder.member_name, appOpenUrl, optOutUrl),
                })
                const { error: updateError } = await supabase
                    .from("member_signup_reminders")
                    .update({ email_sent_at: new Date().toISOString(), last_error: null })
                    .eq("user_id", reminder.user_id)
                    .eq("reminder_type", "signup_completion_24h")
                if (updateError) throw updateError
                sent += 1
            } catch (error) {
                failed += 1
                const message = error instanceof Error ? error.message : String(error)
                console.error(`Could not send signup reminder to ${reminder.user_id}:`, message)
                await supabase
                    .from("member_signup_reminders")
                    .update({ last_error: message })
                    .eq("user_id", reminder.user_id)
                    .eq("reminder_type", "signup_completion_24h")
            }
        }

        return new Response(JSON.stringify({ processed: reminders.length, sent, failed }), {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
        })
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error)
        console.error("pending-member-signup-reminder error:", message)
        return new Response(JSON.stringify({ error: message }), {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
        })
    } finally {
        await smtp.close()
    }
})

function escapeHtml(value: string): string {
    return value
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;")
}

function buildHtmlEmail(memberName: string, appOpenUrl: string, optOutUrl: string): string {
    return `<!DOCTYPE html>
<html>
<body style="font-family:Arial,sans-serif;color:#222;line-height:1.5">
<p>Hi ${escapeHtml(memberName)},</p>
<p>You started your Local Lekker membership signup 24 hours ago, but it is not complete yet.</p>
<p>Complete your subscription to activate your membership and start accessing local deals.</p>
<p><a href="${escapeHtml(appOpenUrl)}" style="display:inline-block;background:#001489;color:#fff;text-decoration:none;padding:12px 20px;border-radius:6px;font-weight:bold">Open Local Lekker</a></p>
<p>If you need help, contact <a href="mailto:support@locallekker.co.za">support@locallekker.co.za</a>.</p>
<p><a href="${escapeHtml(optOutUrl)}" style="display:inline-block;border:1px solid #526079;color:#526079;text-decoration:none;padding:9px 16px;border-radius:6px">Opt out of signup reminders</a></p>
<p>Local Lekker</p>
</body>
</html>`
}