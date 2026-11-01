// Send Payment Success Email to Member
//
// This edge function is called from a database trigger (pg_net) whenever a new
// deal_receipt row is inserted. It sends a payment confirmation email to the
// member with their receipt details.
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
      member_id,
      member_email,
      member_name,
      business_name,
      deal_name,
      amount,
      receipt_number,
      payment_method,
      deal_authorization_id,
    } = await req.json()

    // Validate required fields
    if (!member_id && !member_email) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields (member_id or member_email)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Resolve member email/name from profiles if not provided directly
    let resolvedEmail = member_email
    let resolvedName = member_name

    if (!resolvedEmail && member_id) {
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

      resolvedEmail = profile?.email
      if (!resolvedName) {
        resolvedName = [profile?.name, profile?.surname].filter(Boolean).join(' ') || 'Member'
      }
    }

    if (!resolvedEmail) {
      console.log(`No email found for member ${member_id} – skipping email`)
      return new Response(
        JSON.stringify({ message: 'No email for member – email skipped' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const displayName = resolvedName || 'Member'
    const formattedAmount = `R${Number(amount || 0).toFixed(2)}`
    const businessLabel = business_name || 'Local Business'
    const dealLabel = deal_name || 'Deal'
    const receiptLabel = receipt_number || 'N/A'
    const paymentLabel = payment_method === 'pos' ? 'In-Store (POS)' : 'In-App Payment'

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

    const textBody = [
      `Hi ${displayName},`,
      '',
      'Your payment was successful! Thank you for using Local Lekker.',
      '',
      'Payment Details:',
      `  Deal: ${dealLabel}`,
      `  Business: ${businessLabel}`,
      `  Amount Paid: ${formattedAmount}`,
      `  Payment Method: ${paymentLabel}`,
      `  Receipt Number: ${receiptLabel}`,
      '',
      'Keep this email as your payment confirmation.',
      '',
      '---',
      'This is an automated notification from the Local Lekker app.',
      'If you have any questions, contact us at support@locallekker.co.za',
    ].join('\r\n')

    const escapeHtml = (s: string) =>
      s.replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;')

    const htmlBody = `<!DOCTYPE html>
<html>
  <body style="font-family: Arial, sans-serif; color: #222; line-height: 1.5;">
    <p>Hi ${escapeHtml(displayName)},</p>
    <p>Your payment was <strong>successful</strong>! Thank you for using Local Lekker.</p>
    <p><strong>Payment Details:</strong></p>
    <ul>
      <li><strong>Deal:</strong> ${escapeHtml(dealLabel)}</li>
      <li><strong>Business:</strong> ${escapeHtml(businessLabel)}</li>
      <li><strong>Amount Paid:</strong> ${escapeHtml(formattedAmount)}</li>
      <li><strong>Payment Method:</strong> ${escapeHtml(paymentLabel)}</li>
      <li><strong>Receipt Number:</strong> ${escapeHtml(receiptLabel)}</li>
    </ul>
    <p>Keep this email as your payment confirmation.</p>
    <hr />
    <p style="font-size: 12px; color: #666;">
      This is an automated notification from the Local Lekker app.<br />
      If you have any questions, contact us at
      <a href="mailto:support@locallekker.co.za">support@locallekker.co.za</a>
    </p>
  </body>
</html>`

    let emailSent = false
    try {
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

      await client.send({
        from: smtpUser,
        to: resolvedEmail,
        subject: `Payment Confirmed - ${dealLabel} at ${businessLabel} (${formattedAmount}) - Receipt ${receiptLabel}`,
        content: textBody,
        html: htmlBody,
      })

      await client.close()
      emailSent = true
      console.log(`Member payment success email sent to ${resolvedEmail}, receipt: ${receiptLabel}`)
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
    console.error('send-member-payment-success-email error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
