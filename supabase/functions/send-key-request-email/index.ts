// Send Key Request Email to Admin
//
// Called when a TP requests a new promo key from the app.
// Sends an email notification to admin@locallekkerclub.co.za

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const ADMIN_EMAIL = 'admin@locallekkerclub.co.za'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { business_name, email, tp_user_id } = await req.json()

    if (!business_name || !email) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

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
            auth: { username: smtpUser, password: smtpPass },
          },
        })

        const emailBody = `
New Promo Key Request

A Trusted Partner has requested a new promo key.

Business: ${business_name}
Email: ${email}
User ID: ${tp_user_id || 'N/A'}

Their current key has been used. Please go to the admin app,
find this partner, and click "Generate New Key" to issue a new one.

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
          subject: `Promo Key Request - ${business_name}`,
          content: emailBody,
          html: htmlBody,
        })

        await client.close()
        emailSent = true
        console.log(`Key request email sent for ${business_name}`)
      }
    } catch (emailError) {
      console.error('Email send failed:', emailError)
    }

    return new Response(
      JSON.stringify({ success: true, email_sent: emailSent }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
