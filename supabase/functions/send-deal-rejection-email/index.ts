// Send Deal Rejection Email to Member
//
// This edge function is called from the Flutter app when a trusted partner
// rejects a member's deal request. It sends an email to the member notifying
// them that their deal has been declined along with the reason.
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
      business_name,
      deal_name,
      rejection_reason,
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
    const reasonText = rejection_reason || 'No reason provided'

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
Hi ${memberName},

Unfortunately, your deal request on Local Lekker has been declined.

Deal Details:
  Deal: ${deal_name}
  Business: ${business_name || 'Local Business'}

Reason: ${reasonText}

You can browse other deals in the Local Lekker app or contact the business directly for more information.

---
This is an automated notification from the Local Lekker app.
If you have any questions, contact us at support@locallekker.co.za
`

      await client.send({
        from: smtpUser,
        to: memberEmail,
        subject: `Deal Declined – ${deal_name} at ${business_name || 'Local Business'}`,
        content: emailBody,
      })

      await client.close()
      emailSent = true
      console.log(`Deal rejection email sent to ${memberEmail} for deal: ${deal_name}`)
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
    console.error('send-deal-rejection-email error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
