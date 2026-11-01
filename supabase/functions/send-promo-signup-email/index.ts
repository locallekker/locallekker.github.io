// Send Promo Signup Email to Admin
//
// Called when a member signs up for a promotion.
// Notifies the admin with member details so they can confirm.
//
// Required Supabase secrets:
//   - SMTP_HOST (default: smtp.gmail.com)
//   - SMTP_PORT (default: 465)
//   - SMTP_USER (Gmail address used to send)
//   - SMTP_PASS (Gmail app password)
//   - ADMIN_EMAIL (admin email to notify)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { member_name, member_email, member_contact, promotion_name, free_months } = await req.json()

    if (!member_name || !promotion_name) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields (member_name, promotion_name)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    let emailSent = false
    try {
      const smtpHost = Deno.env.get('SMTP_HOST') ?? 'smtp.gmail.com'
      const smtpPort = parseInt(Deno.env.get('SMTP_PORT') ?? '465')
      const smtpUser = Deno.env.get('SMTP_USER') ?? ''
      const smtpPass = Deno.env.get('SMTP_PASS') ?? ''
      const adminEmail = Deno.env.get('ADMIN_EMAIL') ?? smtpUser

      if (smtpUser && smtpPass) {
        const client = new SMTPClient({
          connection: {
            hostname: smtpHost,
            port: smtpPort,
            tls: true,
            auth: { username: smtpUser, password: smtpPass },
          },
        })

        const durationText = free_months ? `${free_months} month(s) free` : 'free lifetime membership'
        const signupNote = free_months
          ? `Pay R1.00 signup and enjoy ${durationText}.`
          : 'Pay R1.00 signup and enjoy a free lifetime membership.'

        const emailBody = `
Hi Admin,

A new member has signed up for a promotion!

Promotion: ${promotion_name}
Duration: ${durationText}
Note: ${signupNote}

Member Details:
  Name: ${member_name}
  Email: ${member_email || 'Not provided'}
  Contact: ${member_contact || 'Not provided'}

Please log into the Local Lekker admin dashboard to review and confirm this signup.

---
This is an automated notification from the Local Lekker app.
`

        const escapeHtml = (s: string) => s
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;')
          .replace(/"/g, '&quot;')
          .replace(/'/g, '&#39;')
        const htmlBody = `<!DOCTYPE html><html><body style="font-family:Arial,sans-serif;color:#222;"><pre style="font-family:Arial,sans-serif;white-space:pre-wrap;margin:0;">${escapeHtml(emailBody)}</pre></body></html>`

        await client.send({
          from: smtpUser,
          to: adminEmail,
          subject: `New Promo Signup - ${member_name} for ${promotion_name}`,
          content: emailBody,
          html: htmlBody,
        })

        await client.close()
        emailSent = true
        console.log(`Promo signup email sent to admin for member: ${member_name}`)
      }
    } catch (emailError) {
      console.error('Email send failed:', emailError)
    }

    return new Response(
      JSON.stringify({ success: true, email_sent: emailSent }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('send-promo-signup-email error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
