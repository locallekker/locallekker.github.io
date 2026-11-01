// Send Payment Success Email to Trusted Partner
//
// This edge function is called from the Flutter app after a member completes
// a deal payment. It sends an email to the trusted partner notifying them
// that payment has been received and a receipt has been generated.
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
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const {
      trusted_partner_id,
      member_name,
      deal_name,
      amount,
      receipt_number,
      business_name,
      deal_authorization_id,
    } = await req.json()

    // Validate required fields
    if (!trusted_partner_id || !deal_name) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields (trusted_partner_id, deal_name)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Look up the TP's email address from profiles
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabase = createClient(supabaseUrl, serviceRoleKey)

    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('email, name, surname')
      .eq('id', trusted_partner_id)
      .maybeSingle()

    if (profileError) {
      console.error('Error fetching TP profile:', profileError)
      return new Response(
        JSON.stringify({ error: 'Failed to fetch trusted partner profile' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const tpEmail = profile?.email
    if (!tpEmail) {
      console.log(`No email found for trusted partner ${trusted_partner_id} – skipping email`)
      return new Response(
        JSON.stringify({ message: 'No email for TP – email skipped' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const tpName = [profile?.name, profile?.surname].filter(Boolean).join(' ') || 'Trusted Partner'
    const formattedAmount = `R${Number(amount || 0).toFixed(2)}`
    const businessLabel = business_name || 'Your Business'
    const memberLabel = member_name || 'A member'

    // Send email via SMTP
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
          auth: {
            username: smtpUser,
            password: smtpPass,
          },
        },
      })

      const emailBody = `
Hi ${tpName},

Great news! You have received a payment on Local Lekker.

Payment Details:
  Deal: ${deal_name}
  Amount: ${formattedAmount}
  Paid by: ${memberLabel}
  Business: ${businessLabel}
  Receipt Number: ${receipt_number || 'N/A'}

A receipt has been generated and is available in the Local Lekker app under your transaction history.

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
        to: tpEmail,
        subject: `💰 Payment Received – ${deal_name} (${formattedAmount})`,
        content: emailBody,
        html: htmlBody,
      })

      await client.close()
      emailSent = true
      console.log(`Payment success email sent to ${tpEmail} for deal: ${deal_name}, receipt: ${receipt_number}`)
    } catch (emailError) {
      console.error('Email send failed:', emailError)
      return new Response(
        JSON.stringify({ success: false, email_sent: false, error: emailError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ success: true, email_sent: emailSent }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('send-payment-success-email error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
