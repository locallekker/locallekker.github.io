// Send Promo Confirmation Email to Member
//
// Called when admin confirms a member's promo signup.
// Sends a congratulations email to the member.
//
// Required Supabase secrets:
//   - SUPABASE_URL
//   - SUPABASE_SERVICE_ROLE_KEY
//   - SMTP_HOST (default: smtp.gmail.com)
//   - SMTP_PORT (default: 465)
//   - SMTP_USER (Gmail address used to send)
//   - SMTP_PASS (Gmail app password)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { member_id, promotion_name, free_months } = await req.json()

    if (!member_id || !promotion_name) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields (member_id, promotion_name)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Look up the member's email from profiles
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabase = createClient(supabaseUrl, serviceRoleKey)

    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('email, name, surname')
      .eq('id', member_id)
      .maybeSingle()

    if (profileError) {
      console.error('Error fetching member profile:', profileError)
      return new Response(
        JSON.stringify({ error: 'Failed to fetch member profile' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const memberEmail = profile?.email
    if (!memberEmail) {
      console.log(`No email found for member ${member_id} – skipping email`)
      return new Response(
        JSON.stringify({ message: 'No email for member – email skipped' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const memberName = [profile?.name, profile?.surname].filter(Boolean).join(' ') || 'Member'
    const durationText = free_months ? `${free_months} month(s)` : 'lifetime'

    let emailSent = false
    try {
      const smtpHost = Deno.env.get('SMTP_HOST') ?? 'smtp.gmail.com'
      const smtpPort = parseInt(Deno.env.get('SMTP_PORT') ?? '465')
      const smtpUser = Deno.env.get('SMTP_USER') ?? ''
      const smtpPass = Deno.env.get('SMTP_PASS') ?? ''

      if (!smtpUser || !smtpPass) {
        console.warn('SMTP credentials not configured – skipping email')
        return new Response(
          JSON.stringify({ success: true, email_sent: false, reason: 'SMTP not configured' }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const client = new SMTPClient({
        connection: {
          hostname: smtpHost,
          port: smtpPort,
          tls: true,
          auth: { username: smtpUser, password: smtpPass },
        },
      })

      const emailBody = `
Hi ${memberName},

Congratulations! Your signup for the "${promotion_name}" promotion has been confirmed!

You now have ${durationText} of free access added to your subscription.

Your QR code and subscription have been automatically updated.
Open the Local Lekker app to see your extended subscription.

Enjoy your deals!

---
This is an automated notification from the Local Lekker app.
If you have any questions, contact us at support@locallekker.co.za
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
        to: memberEmail,
        subject: `Promotion Confirmed - ${promotion_name}`,
        content: emailBody,
        html: htmlBody,
      })

      await client.close()
      emailSent = true
      console.log(`Promo confirmation email sent to ${memberEmail} for: ${promotion_name}`)
    } catch (emailError) {
      console.error('Email send failed:', emailError)
    }

    return new Response(
      JSON.stringify({ success: true, email_sent: emailSent }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('send-promo-confirmation-email error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
