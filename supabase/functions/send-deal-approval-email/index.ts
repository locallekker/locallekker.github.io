// Send Deal Approval Email to Member
//
// This edge function is called from the Flutter app when a trusted partner
// approves a member's deal request. It sends an email to the member notifying
// them that their deal has been approved and they can proceed with payment.
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
      trusted_partner_id,
      business_name,
      business_contact,
      business_email,
      deal_name,
      amount,
      payment_method,
      quantity,
      deal_authorization_id,
    } = await req.json()

    // Validate required fields
    if (!member_id || !deal_name) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields (member_id, deal_name)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Look up the member's email address from profiles
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

    // Resolve the trusted partner's business details. Prefer values passed by
    // the app, but fall back to a businesses lookup so the email is complete.
    let tpBusinessName = business_name ?? ''
    let tpContact = business_contact ?? ''
    let tpEmail = business_email ?? ''

    if (trusted_partner_id && (!tpBusinessName || !tpContact || !tpEmail)) {
      const { data: business, error: businessError } = await supabase
        .from('businesses')
        .select('name, contact_number, contact_email')
        .eq('owner_member_id', trusted_partner_id)
        .maybeSingle()

      if (businessError) {
        console.error('Error fetching business profile:', businessError)
      } else if (business) {
        tpBusinessName = tpBusinessName || (business.name ?? '')
        tpContact = tpContact || (business.contact_number ?? '')
        tpEmail = tpEmail || (business.contact_email ?? '')
      }
    }

    // Format display values
    const formattedAmount = `R${Number(amount || 0).toFixed(2)}`
    const quantityText = quantity && quantity > 1 ? ` (x${quantity})` : ''
    const isPOS = payment_method === 'pos'
    const paymentInstruction = isPOS
      ? 'Please visit the store to complete your payment.'
      : 'Open the Local Lekker app to complete your payment now.'

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

      const businessLabel = tpBusinessName || 'Local Business'
      const paymentLabel = isPOS ? 'In-Store (POS)' : 'In-App Payment'

      const textBody = [
        `Hi ${memberName},`,
        '',
        'Great news! Your deal request has been approved on Local Lekker!',
        '',
        'Deal Details:',
        `  Deal: ${deal_name}${quantityText}`,
        `  Business: ${businessLabel}`,
        `  Amount: ${formattedAmount}`,
        `  Payment Method: ${paymentLabel}`,
        '',
        'Business Contact Details:',
        `  Business: ${businessLabel}`,
        `  Contact: ${tpContact || 'N/A'}`,
        `  Email: ${tpEmail || 'N/A'}`,
        '',
        paymentInstruction,
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
    <p>Hi ${escapeHtml(memberName)},</p>
    <p><strong>Great news!</strong> Your deal request has been approved on Local Lekker!</p>
    <p><strong>Deal Details:</strong></p>
    <ul>
      <li><strong>Deal:</strong> ${escapeHtml(deal_name)}${escapeHtml(quantityText)}</li>
      <li><strong>Business:</strong> ${escapeHtml(businessLabel)}</li>
      <li><strong>Amount:</strong> ${escapeHtml(formattedAmount)}</li>
      <li><strong>Payment Method:</strong> ${escapeHtml(paymentLabel)}</li>
    </ul>
    <p><strong>Business Contact Details:</strong></p>
    <ul>
      <li><strong>Business:</strong> ${escapeHtml(businessLabel)}</li>
      <li><strong>Contact:</strong> ${escapeHtml(tpContact || 'N/A')}</li>
      <li><strong>Email:</strong> ${escapeHtml(tpEmail || 'N/A')}</li>
    </ul>
    <p>${escapeHtml(paymentInstruction)}</p>
    <hr />
    <p style="font-size: 12px; color: #666;">
      This is an automated notification from the Local Lekker app.<br />
      If you have any questions, contact us at
      <a href="mailto:support@locallekker.co.za">support@locallekker.co.za</a>
    </p>
  </body>
</html>`

      await client.send({
        from: smtpUser,
        to: memberEmail,
        subject: `Deal Approved - ${deal_name} at ${businessLabel} (${formattedAmount})`,
        content: textBody,
        html: htmlBody,
      })

      await client.close()
      emailSent = true
      console.log(`Deal approval email sent to ${memberEmail} for deal: ${deal_name}`)
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
    console.error('send-deal-approval-email error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
