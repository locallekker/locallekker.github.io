// Send TP Inquiry Email + Push Notification to Admin
//
// This edge function is called from the Flutter app when a potential
// trusted partner submits their interest form. It:
// 1. Sends an email to admin@locallekkerclub.co.za via Gmail SMTP
// 2. Creates push notifications for all admin users via the notifications table

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const ADMIN_EMAIL = 'admin@locallekkerclub.co.za'

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const {
      name,
      surname,
      city,
      business_name,
      business_type,
      email,
      contact_number,
      sells_fresh_produce,
      sells_alcohol,
      offers_sports_activities,
    } = await req.json()

    // Validate required fields
    if (!name || !surname || !email || !business_name) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // --- 1. Send email via Gmail SMTP ---
    let emailSent = false
    try {
      const smtpHost = Deno.env.get('SMTP_HOST') ?? 'smtp.gmail.com'
      const smtpPort = parseInt(Deno.env.get('SMTP_PORT') ?? '465')
      const smtpUser = Deno.env.get('SMTP_USER') ?? ''
      const smtpPass = Deno.env.get('SMTP_PASS') ?? ''

      if (smtpUser && smtpPass) {
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
New Trusted Partner Inquiry

A potential trusted partner has submitted their interest to join Local Lekker.

Contact Details:
  Name: ${name} ${surname}
  Email: ${email}
  Contact Number: ${contact_number || 'Not provided'}

Business Details:
  Business Name: ${business_name}
  Business Type: ${business_type || 'Not specified'}
  City: ${city || 'Not specified'}
  Fresh & Local Produce: ${sells_fresh_produce ? 'YES - wants to sell fresh produce' : 'No'}
  Local Sips (alcohol): ${sells_alcohol ? 'YES - liquor licence documents required' : 'No'}
  Locally Active (sport/fitness): ${offers_sports_activities ? 'YES - offers sport/fitness activities' : 'No'}

Please contact them to finalise their signup and onboarding.

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
          to: ADMIN_EMAIL,
          subject: `New Trusted Partner Inquiry - ${business_name}`,
          content: emailBody,
          html: htmlBody,
        })

        await client.close()
        emailSent = true
        console.log(`TP inquiry email sent to ${ADMIN_EMAIL} for ${business_name}`)
      } else {
        console.warn('SMTP credentials not configured, skipping email')
      }
    } catch (emailError) {
      console.error('Email send failed (will still create push notification):', emailError)
    }

    // --- 2. Create push notification for all admins ---
    let pushSent = false
    try {
      const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
      const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      const supabase = createClient(supabaseUrl, serviceRoleKey)

      const { data: admins, error: adminError } = await supabase
        .from('profiles')
        .select('id')
        .eq('role', 'admin')

      if (adminError) {
        console.error('Failed to fetch admin users:', adminError)
      } else if (admins && admins.length > 0) {
        const notifications = admins.map((admin: { id: string }) => ({
          user_id: admin.id,
          title: 'New Trusted Partner Inquiry',
          message: `${name} ${surname} (${business_name}) wants to become a Trusted Partner${sells_fresh_produce ? ' - Fresh & Local produce' : ''}${sells_alcohol ? ' - Local Sips (alcohol)' : ''}${offers_sports_activities ? ' - Locally Active (sport/fitness)' : ''}`,
          type: 'tp_inquiry',
          data: {
            business_name,
            business_type: business_type || 'Not specified',
            email,
            contact_number: contact_number || 'Not provided',
            city: city || 'Not specified',
            sells_fresh_produce: sells_fresh_produce === true,
            sells_alcohol: sells_alcohol === true,
            offers_sports_activities: offers_sports_activities === true,
          },
          is_read: false,
        }))

        const { error: insertError } = await supabase
          .from('notifications')
          .insert(notifications)

        if (insertError) {
          console.error('Failed to create notifications:', insertError)
        } else {
          pushSent = true
          console.log(`Push notification created for ${admins.length} admin(s)`)
        }
      }
    } catch (pushError) {
      console.error('Push notification failed:', pushError)
    }

    return new Response(
      JSON.stringify({ success: true, email_sent: emailSent, push_sent: pushSent }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error processing TP inquiry notification:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
