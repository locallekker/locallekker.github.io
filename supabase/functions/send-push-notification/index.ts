// Send Push Notification via Firebase Cloud Messaging (FCM HTTP v1 API)
//
// This edge function is called by a Supabase database webhook trigger
// whenever a new row is inserted into the `notifications` table.
// It looks up the recipient's FCM token from `profiles.fcm_token`
// and sends a push notification via Firebase Cloud Messaging.
//
// Required Supabase secrets:
//   - SUPABASE_URL
//   - SUPABASE_SERVICE_ROLE_KEY
//   - FCM_SERVICE_ACCOUNT_KEY  (JSON string of Firebase service account credentials)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/** Build a Google OAuth2 access token from a service account JSON key. */
async function getAccessToken(serviceAccount: {
  client_email: string
  private_key: string
  token_uri: string
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: serviceAccount.token_uri,
    iat: now,
    exp: now + 3600,
  }

  const encode = (obj: unknown) => {
    const json = JSON.stringify(obj)
    return btoa(json).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  }

  const unsignedToken = `${encode(header)}.${encode(payload)}`

  // Import the RSA private key
  const pemContents = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\n/g, '')
  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0))

  const key = await crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsignedToken),
  )

  const sig = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')

  const jwt = `${unsignedToken}.${sig}`

  // Exchange the JWT for an access token
  const tokenRes = await fetch(serviceAccount.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })

  const tokenData = await tokenRes.json()
  if (!tokenData.access_token) {
    throw new Error(`Failed to get access token: ${JSON.stringify(tokenData)}`)
  }
  return tokenData.access_token
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const fcmKeyRaw = Deno.env.get('FCM_SERVICE_ACCOUNT_KEY')

    if (!fcmKeyRaw) {
      console.error('FCM_SERVICE_ACCOUNT_KEY secret not configured')
      return new Response(
        JSON.stringify({ error: 'FCM not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const serviceAccount = JSON.parse(fcmKeyRaw)
    const projectId = serviceAccount.project_id

    // Parse the incoming webhook payload
    const body = await req.json()
    // Supabase Database Webhooks send { type, table, record, schema, old_record }
    const record = body.record ?? body

    const userId = record.user_id
    const title = record.title ?? 'New Notification'
    const message = record.message ?? 'You have a new notification'
    const notificationType = record.type ?? 'general'

    if (!userId) {
      return new Response(
        JSON.stringify({ error: 'No user_id in notification record' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // Look up the user's FCM token
    const supabase = createClient(supabaseUrl, supabaseServiceKey)
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('fcm_token')
      .eq('id', userId)
      .maybeSingle()

    if (profileError) {
      console.error('Error fetching profile:', profileError)
      return new Response(
        JSON.stringify({ error: 'Failed to fetch user profile' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const fcmToken = profile?.fcm_token
    if (!fcmToken) {
      console.log(`No FCM token for user ${userId} – skipping push`)
      return new Response(
        JSON.stringify({ message: 'No FCM token – push skipped' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // Get an OAuth2 access token for the FCM HTTP v1 API
    const accessToken = await getAccessToken(serviceAccount)

    // Determine priority based on notification type
    const highPriorityTypes = [
      'deal_request',
      'deal_approved',
      'pos_deal_approved',
      'deal_rejected',
      'deal_cancelled',
      'payment_received',
      'payment_success',
      'banking_details_added',
      'subaccount_approval_required',
      'partner_approved',
    ]
    const isHighPriority = highPriorityTypes.includes(notificationType)

    // Send the push notification via FCM HTTP v1 API
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

    // DATA-ONLY message (no top-level `notification` key).
    //
    // Why: When a FCM message includes a `notification` key, Android's OS
    // handles display automatically in the background, but the Dart
    // `onBackgroundMessage` handler may NOT fire on many OEM devices
    // (Samsung, Xiaomi, Huawei, Oppo, OnePlus). If the OEM then also
    // suppresses the system-level display, the notification is silently
    // lost with no fallback.
    //
    // By sending data-only messages with HIGH priority, Android MUST wake
    // the app process and invoke `onBackgroundMessage`, where our Dart
    // code explicitly displays the notification via
    // flutter_local_notifications — giving us full control on every device.
    //
    // iOS is unaffected: the `apns` payload below is sent directly to
    // Apple Push Notification service, independent of the `notification` key.
    const fcmPayload = {
      message: {
        token: fcmToken,
        android: {
          priority: 'HIGH' as const,
          direct_boot_ok: true,
        },
        apns: {
          headers: {
            'apns-priority': '10',
          },
          payload: {
            aps: {
              alert: { title, body: message },
              sound: 'default',
              badge: 1,
              'content-available': 1,
              'mutable-content': 1,
            },
          },
        },
        data: {
          title: title,
          body: message,
          notification_type: notificationType,
          notification_id: record.id ?? '',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
      },
    }

    const fcmRes = await fetch(fcmUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(fcmPayload),
    })

    const fcmResult = await fcmRes.json()

    if (!fcmRes.ok) {
      // If the token is expired/invalid, clear it from the profile
      if (
        fcmResult?.error?.details?.some(
          (d: { errorCode: string }) =>
            d.errorCode === 'UNREGISTERED' || d.errorCode === 'INVALID_ARGUMENT',
        )
      ) {
        console.log(`Clearing stale FCM token for user ${userId}`)
        await supabase
          .from('profiles')
          .update({ fcm_token: null })
          .eq('id', userId)
      }
      console.error('FCM send failed:', JSON.stringify(fcmResult))
      return new Response(
        JSON.stringify({ error: 'FCM send failed', details: fcmResult }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    console.log(`Push sent to user ${userId} (type: ${notificationType})`)
    return new Response(
      JSON.stringify({ success: true, fcm_result: fcmResult }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (error) {
    console.error('send-push-notification error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})

/** Map notification type to Android notification channel ID */
function _getAndroidChannel(type: string): string {
  switch (type) {
    case 'banking_details_added':
    case 'subaccount_approval_required':
    case 'partner_approved':
      return 'admin_alerts'
    case 'deal_request':
      return 'deal_requests'
    case 'deal_approved':
    case 'pos_deal_approved':
    case 'deal_rejected':
    case 'deal_cancelled':
      return 'deal_responses'
    case 'payment_received':
    case 'payment_success':
    case 'payment_failure':
      return 'payment_notifications'
    default:
      return 'deal_notifications'
  }
}
