// Send onboarding credentials to a trusted partner created by an admin.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const jsonHeaders = { ...corsHeaders, 'Content-Type': 'application/json' }

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authorization = req.headers.get('Authorization')
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

    if (!authorization || !serviceRoleKey) {
      return new Response(JSON.stringify({ error: 'Missing authorization or Supabase configuration' }), {
        status: 401,
        headers: jsonHeaders,
      })
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey)
    const accessToken = authorization.replace(/^Bearer\s+/i, '').trim()
    const { data: { user: caller }, error: callerError } = await adminClient.auth.getUser(accessToken)
    if (callerError || !caller) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: jsonHeaders,
      })
    }

    const [{ data: profile }, { data: membership }] = await Promise.all([
      adminClient.from('profiles').select('role').eq('id', caller.id).maybeSingle(),
      adminClient.from('memberships').select('role').eq('user_id', caller.id).eq('role', 'admin').maybeSingle(),
    ])
    if (profile?.role !== 'admin' && !membership) {
      return new Response(JSON.stringify({ error: 'Admin access required' }), {
        status: 403,
        headers: jsonHeaders,
      })
    }

    const {
      email,
      name,
      surname,
      business_name,
      category,
      password,
    } = await req.json()

    if (!email || !password) {
      return new Response(JSON.stringify({ error: 'Missing required fields (email, password)' }), {
        status: 400,
        headers: jsonHeaders,
      })
    }

    const smtpUser = Deno.env.get('SMTP_USER') ?? ''
    const smtpPass = Deno.env.get('SMTP_PASS') ?? ''
    if (!smtpUser || !smtpPass) {
      console.error('Admin TP onboarding email skipped: SMTP credentials are not configured')
      return new Response(JSON.stringify({ success: false, email_sent: false, reason: 'SMTP not configured' }), {
        headers: jsonHeaders,
      })
    }

    const smtpHost = Deno.env.get('SMTP_HOST') ?? 'smtp.gmail.com'
    const smtpPort = parseInt(Deno.env.get('SMTP_PORT') ?? '465')
    const client = new SMTPClient({
      connection: {
        hostname: smtpHost,
        port: smtpPort,
        tls: true,
        auth: { username: smtpUser, password: smtpPass },
      },
    })

    const displayName = [name, surname].filter(Boolean).join(' ') || 'Trusted Partner'
    const businessLabel = business_name || 'your business'
    const categoryLabel = category || 'Not specified'
    const textBody = [
      `Hi ${displayName},`,
      '',
      'Your Local Lekker Trusted Partner account has been created.',
      '',
      'Sign-in details:',
      `  Email: ${email}`,
      `  Temporary password: ${password}`,
      `  Business: ${businessLabel}`,
      `  Category: ${categoryLabel}`,
      '',
      'Please sign in to the Local Lekker app and change your password as soon as possible.',
      'You can then complete or update your business profile.',
      '',
      '---',
      'This is an automated notification from the Local Lekker app.',
      'If you have any questions, contact us at support@locallekker.co.za',
    ].join('\\r\\n')

    const escapeHtml = (value: string) => value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;')
    const htmlBody = `<!DOCTYPE html><html><body style="font-family:Arial,sans-serif;color:#222;line-height:1.5;"><p>Hi ${escapeHtml(displayName)},</p><p>Your Local Lekker Trusted Partner account has been created.</p><p><strong>Sign-in details:</strong></p><ul><li><strong>Email:</strong> ${escapeHtml(email)}</li><li><strong>Temporary password:</strong> ${escapeHtml(password)}</li><li><strong>Business:</strong> ${escapeHtml(businessLabel)}</li><li><strong>Category:</strong> ${escapeHtml(categoryLabel)}</li></ul><p>Please sign in to the Local Lekker app and change your password as soon as possible.</p><p>You can then complete or update your business profile.</p><hr /><p style="font-size:12px;color:#666;">This is an automated notification from the Local Lekker app.<br />If you have any questions, contact us at <a href="mailto:support@locallekker.co.za">support@locallekker.co.za</a></p></body></html>`

    try {
      await client.send({
        from: smtpUser,
        to: email,
        subject: 'Your Local Lekker Trusted Partner Account',
        content: textBody,
        html: htmlBody,
      })
      await client.close()
      console.log(`Admin-created TP onboarding email sent to ${email}`)
      return new Response(JSON.stringify({ success: true, email_sent: true }), { headers: jsonHeaders })
    } catch (emailError) {
      console.error('Admin-created TP onboarding email failed:', emailError)
      try { await client.close() } catch (_) { /* Best effort cleanup. */ }
      return new Response(JSON.stringify({ success: false, email_sent: false, error: String(emailError) }), {
        status: 500,
        headers: jsonHeaders,
      })
    }
  } catch (error) {
    console.error('send-admin-created-tp-email error:', error)
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: jsonHeaders,
    })
  }
})
