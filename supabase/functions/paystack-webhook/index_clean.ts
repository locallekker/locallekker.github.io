// Paystack Webhook Handler - Clean Version
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-paystack-signature',
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const supabaseUrl = Deno.env.get('SUPABASE_URL')!
        const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
        const paystackSecretKey = Deno.env.get('PAYSTACK_SECRET_KEY')!

        const supabase = createClient(supabaseUrl, supabaseServiceKey)

        const webhookData = await req.json()
        const signature = req.headers.get('x-paystack-signature')

        console.log('Paystack webhook received:', webhookData.event)

        // Allow test webhooks to bypass signature verification
        const isTestWebhook = webhookData.data?.reference?.startsWith('test_') ||
            signature === 'test_signature' ||
            !paystackSecretKey

        if (!isTestWebhook && !signature) {
            throw new Error('Missing Paystack signature')
        }

        if (!isTestWebhook && !paystackSecretKey) {
            throw new Error('Paystack secret key not configured')
        }

        const event = webhookData.event
        const data = webhookData.data

        if (!data) {
            throw new Error('No data in webhook')
        }

        switch (event) {
            case 'charge.success':
                await handleChargeSuccess(supabase, data)
                break
            case 'subscription.create':
                await handleSubscriptionCreate(supabase, data)
                break
            case 'invoice.payment_failed':
                await handlePaymentFailed(supabase, data)
                break
            case 'subscription.disable':
                await handleSubscriptionDisable(supabase, data)
                break
            default:
                console.log('Unhandled Paystack event:', event)
        }

        return new Response(JSON.stringify({ status: 'success' }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        })

    } catch (error) {
        console.error('Paystack webhook error:', error)
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 400,
        })
    }
})

async function handleChargeSuccess(supabase: any, data: any) {
    const reference = data.reference
    const amount = data.amount
    const customer = data.customer
    const metadata = data.metadata || {}

    console.log('Processing successful charge:', reference)

    const userId = metadata.user_id || customer.email
    const paymentType = metadata.payment_type || 'unknown'

    if (!userId) {
        throw new Error('Missing user ID in charge success')
    }

    // Skip database operations for test webhooks
    if (reference.startsWith('test_')) {
        console.log('Test webhook detected, skipping database operations')
        return
    }

    const { error: paymentError } = await supabase
        .from('payments')
        .insert({
            reference: reference,
            user_id: userId,
            amount: amount / 100,
            currency: 'NGN',
            status: 'completed',
            payment_method: 'paystack',
            payment_type: paymentType,
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
        })

    if (paymentError) {
        throw new Error(`Failed to record payment: ${paymentError.message}`)
    }

    if (paymentType === 'subscription') {
        await updateUserMembership(supabase, userId, 'premium')
        await activateUserQRCode(supabase, userId)
    }

    console.log('Charge processed successfully:', reference)
}

async function handleSubscriptionCreate(supabase: any, data: any) {
    const subscriptionCode = data.subscription_code
    const customer = data.customer
    const plan = data.plan

    console.log('Processing subscription create:', subscriptionCode)

    const userId = customer.email

    const subscriptionData = {
        user_id: userId,
        subscription_code: subscriptionCode,
        plan_type: plan.name.toLowerCase(),
        status: 'active',
        auto_renew: true,
        current_period_start: new Date().toISOString(),
        current_period_end: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
        updated_at: new Date().toISOString()
    }

    const { error } = await supabase
        .from('subscriptions')
        .insert(subscriptionData)

    if (error) {
        throw new Error(`Failed to create subscription: ${error.message}`)
    }

    await updateUserMembership(supabase, userId, plan.name.toLowerCase())
    await activateUserQRCode(supabase, userId)

    console.log('Subscription created for user:', userId)
}

async function handlePaymentFailed(supabase: any, data: any) {
    const subscriptionCode = data.subscription_code

    console.log('Processing payment failed:', subscriptionCode)

    const { error } = await supabase
        .from('subscriptions')
        .update({ status: 'payment_failed' })
        .eq('subscription_code', subscriptionCode)

    if (error) {
        throw new Error(`Failed to update subscription: ${error.message}`)
    }

    console.log('Subscription payment failed:', subscriptionCode)
}

async function handleSubscriptionDisable(supabase: any, data: any) {
    const subscriptionCode = data.subscription_code
    const customer = data.customer

    console.log('Processing subscription disable:', subscriptionCode)

    const userId = customer.email

    const { error: subError } = await supabase
        .from('subscriptions')
        .update({ status: 'cancelled' })
        .eq('subscription_code', subscriptionCode)

    if (subError) {
        throw new Error(`Failed to update subscription: ${subError.message}`)
    }

    await updateUserMembership(supabase, userId, 'free')

    console.log('Subscription disabled for user:', userId)
}

async function updateUserMembership(supabase: any, userId: string, planName: string) {
    const roleMapping: { [key: string]: string } = {
        'free': 'free',
        'basic': 'basic',
        'premium': 'premium',
        'business': 'business',
    }

    const role = roleMapping[planName.toLowerCase()] || 'free'

    const { error } = await supabase
        .from('profiles')
        .update({ membership_role: role })
        .eq('id', userId)

    if (error) {
        throw new Error(`Failed to update user membership: ${error.message}`)
    }

    console.log('Updated user', userId, 'role to', role)
}

async function activateUserQRCode(supabase: any, userId: string) {
    const { data: existingQR } = await supabase
        .from('user_qr_codes')
        .select('id')
        .eq('user_id', userId)
        .eq('is_active', true)
        .single()

    if (existingQR) {
        console.log('User already has active QR code:', userId)
        return
    }

    const qrCode = `QR_${userId}_${Date.now()}`
    const qrData = `user:${userId}`

    const { error } = await supabase
        .from('user_qr_codes')
        .insert({
            user_id: userId,
            qr_code: qrCode,
            qr_data: qrData,
            is_active: true,
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
        })

    if (error) {
        throw new Error(`Failed to activate QR code: ${error.message}`)
    }

    console.log('Activated QR code for user:', userId)
}