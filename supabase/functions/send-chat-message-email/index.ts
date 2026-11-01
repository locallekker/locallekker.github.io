// Send Chat Message Email Notification
//
// This edge function is called from the Flutter app when a user sends a
// chat message. It sends an email to the recipient notifying them of the
// new message so they can open the app to respond.
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
      recipient_id,
      notify_admin,
      sender_name,
      message_preview,
    } = await req.json()

    // Validate required fields
    if ((!recipient_id && !notify_admin) || !sender_name) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields (recipient_id or notify_admin, sender_name)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Look up the recipient's email address from profiles
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabase = createClient(supabaseUrl, serviceRoleKey)

    // Fallback admin email used when DB lookup returns nothing
    const ADMIN_EMAIL = Deno.env.get('ADMIN_EMAIL') ?? 'admin@locallekkerclub.co.za'

    // Build list of recipients: either a single user or all admin users
    type Recipient = { email: string; name: string }
    let recipients: Recipient[] = []

    if (notify_admin) {
      // Support message from member/TP → notify all admin profiles
      // Strategy 1: look up profiles where role = 'admin'
      const { data: adminProfiles, error: adminError } = await supabase
        .from('profiles')
        .select('email, name, surname')
        .eq('role', 'admin')

      if (adminError) {
        console.error('Error fetching admin profiles:', adminError)
      } else {
        recipients = (adminProfiles ?? [])
          .filter((p: any) => !!p.email)
          .map((p: any) => ({
            email: p.email as string,
            name: ([p.name, p.surname].filter(Boolean).join(' ') || 'Admin') as string,
          }))
      }

      // Strategy 2: if profiles.role didn't yield results, try memberships table
      if (recipients.length === 0) {
        console.log('No admin profiles via profiles.role – trying memberships table')
        const { data: adminMemberships, error: membershipError } = await supabase
          .from('memberships')
          .select('user_id')
          .eq('role', 'admin')

        if (!membershipError && adminMemberships && adminMemberships.length > 0) {
          const adminIds = adminMemberships.map((m: any) => m.user_id as string)
          const { data: profilesByIds, error: profilesError } = await supabase
            .from('profiles')
            .select('email, name, surname')
            .in('id', adminIds)

          if (!profilesError && profilesByIds) {
            recipients = profilesByIds
              .filter((p: any) => !!p.email)
              .map((p: any) => ({
                email: p.email as string,
                name: ([p.name, p.surname].filter(Boolean).join(' ') || 'Admin') as string,
              }))
          }
        }
      }

      // Strategy 3: final fallback – use hardcoded admin email constant
      if (recipients.length === 0) {
        console.log('No admin profiles found in DB – falling back to ADMIN_EMAIL')
        recipients = [{ email: ADMIN_EMAIL, name: 'Admin' }]
      }
    } else {
      // Regular or admin-reply notification → single recipient by ID
      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('email, name, surname')
        .eq('id', recipient_id)
        .maybeSingle()

      if (profileError) {
        console.error('Error fetching recipient profile:', profileError)
        return new Response(
          JSON.stringify({ error: 'Failed to fetch recipient profile' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      if (!profile?.email) {
        console.log(`No email found for recipient ${recipient_id} – skipping email`)
        return new Response(
          JSON.stringify({ message: 'No email for recipient – email skipped' }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      recipients = [{
        email: profile.email,
        name: [profile.name, profile.surname].filter(Boolean).join(' ') || 'User',
      }]
    }

    // Truncate message preview for email
    const preview = (message_preview || '').substring(0, 200)
    const truncated = preview.length < (message_preview || '').length ? preview + '...' : preview

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

      for (const recipient of recipients) {
        const emailBody = `
Hi ${recipient.name},

You have a new message from ${sender_name} on Local Lekker:

"${truncated}"

Open the Local Lekker app to view and reply.

---
This is an automated notification from the Local Lekker app.
If you have any questions, contact us at support@locallekker.co.za
`
        await client.send({
          from: smtpUser,
          to: recipient.email,
          subject: `New message from ${sender_name} – Local Lekker`,
          content: emailBody,
        })
        console.log(`Chat email sent to ${recipient.email} from ${sender_name}`)
      }

      await client.close()
      emailSent = true
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
    console.error('send-chat-message-email error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
