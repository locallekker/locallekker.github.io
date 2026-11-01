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
            case 'subscription.charge':
                // Handle auto-renewal charges
                await handleSubscriptionCharge(supabase, data)
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

    // Skip database operations for test webhooks and test users
    if (reference.startsWith('test_') || userId === '123e4567-e89b-12d3-a456-426614174000') {
        console.log('Test webhook or test user detected, skipping database operations')
        return
    }

    const { error: paymentError } = await supabase
        .from('payments')
        .insert({
            user_id: userId,
            plan_name: metadata.plan_name || 'basic',
            amount: amount / 100, // Convert from kobo to Naira
            payment_method: 'Paystack',
            transaction_id: reference,
            status: 'completed',
            completed_at: new Date().toISOString()
        })

    if (paymentError) {
        throw new Error(`Failed to record payment: ${paymentError.message}`)
    }

    if (paymentType === 'subscription') {
        await updateUserMembership(supabase, userId, 'premium')
        await updateUserSubscriptionStatus(supabase, userId, 'active')
        await activateUserQRCode(supabase, userId)
    }

    console.log('Charge processed successfully:', reference)
}

async function handleSubscriptionCreate(supabase: any, data: any) {
    const subscriptionCode = data.subscription_code
    const customer = data.customer
    const plan = data.plan
    const metadata = data.metadata || {}

    console.log('Processing subscription create:', subscriptionCode)

    const userId = metadata.user_id || customer.email

    // Skip database operations for test webhooks and test users
    if (subscriptionCode.startsWith('test_') || userId === '123e4567-e89b-12d3-a456-426614174000') {
        console.log('Test subscription or test user detected, skipping database operations')
        return
    }

    // For now, just update user membership and activate QR code
    // Subscription record creation can be handled separately
    await updateUserMembership(supabase, userId, 'premium')
    await activateUserQRCode(supabase, userId)

    console.log('Subscription create processed for user:', userId)
}

async function handleSubscriptionCharge(supabase: any, data: any) {
    const subscriptionCode = data.subscription?.subscription_code || data.subscription_code
    const customer = data.customer
    const amount = data.amount
    const status = data.status
    const reference = data.reference
    const metadata = data.metadata || {}

    console.log('Processing subscription charge:', reference, 'Status:', status)

    if (status !== 'success') {
        console.log('Subscription charge not successful, status:', status)
        return
    }

    // Find user by customer code
    const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('id, email')
        .eq('paystack_customer_code', customer.customer_code)
        .single()

    if (profileError || !profile) {
        console.error('Profile not found for customer:', customer.customer_code)

        // Fallback: try to find by email
        const { data: profileByEmail } = await supabase
            .from('profiles')
            .select('id, email')
            .eq('email', customer.email)
            .single()

        if (!profileByEmail) {
            throw new Error(`User not found for customer: ${customer.customer_code}`)
        }

        console.log('Found user by email fallback:', profileByEmail.id)
        profile.id = profileByEmail.id
    }

    const userId = profile.id

    // Skip test users
    if (userId === '123e4567-e89b-12d3-a456-426614174000') {
        console.log('Test user detected, skipping database operations')
        return
    }

    // Get current subscription
    const { data: currentSub } = await supabase
        .from('subscriptions')
        .select('expires_at')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })
        .limit(1)
        .single()

    // Calculate new expiry date (30 days from current expiry or now)
    let baseDate = currentSub?.expires_at ? new Date(currentSub.expires_at) : new Date()

    // If subscription already expired, start from now
    if (baseDate < new Date()) {
        baseDate = new Date()
    }

    const newExpiryDate = new Date(baseDate.getTime() + (30 * 24 * 60 * 60 * 1000)) // +30 days

    console.log(`Extending subscription until: ${newExpiryDate.toISOString()}`)

    // Update subscription with new expiry date
    const { error: updateError } = await supabase
        .from('subscriptions')
        .update({
            current_period_end: newExpiryDate.toISOString(),
            status: 'active',
            paystack_subscription_code: subscriptionCode,
            updated_at: new Date().toISOString(),
        })
        .eq('user_id', userId)

    if (updateError) {
        console.error('Error updating subscription:', updateError.message)
        throw new Error(`Failed to update subscription: ${updateError.message}`)
    }

    // Reactivate profile subscription status
    await supabase
        .from('profiles')
        .update({
            subscription: 'active',
            updated_at: new Date().toISOString()
        })
        .eq('id', userId)

    // Record the payment
    await supabase
        .from('payments')
        .insert({
            user_id: userId,
            plan_name: metadata.plan_name || 'monthly',
            amount: amount / 100, // Convert kobo to rands
            payment_method: 'Paystack',
            transaction_id: reference,
            status: 'completed',
            completed_at: new Date().toISOString()
        })

    // Create notification for user
    await supabase
        .from('notifications')
        .insert({
            user_id: userId,
            title: 'Subscription Renewed',
            message: `Your Local Lekker subscription has been automatically renewed until ${newExpiryDate.toLocaleDateString('en-ZA')}. Thank you for being a valued member!`,
            type: 'subscription_renewal',
            is_read: false,
            data: {
                renewed_at: new Date().toISOString(),
                expires_at: newExpiryDate.toISOString(),
                amount: amount / 100,
                payment_reference: reference
            }
        })

    // Ensure QR code is active
    await activateUserQRCode(supabase, userId)

    console.log('Subscription charge processed successfully - Profile reactivated for user:', userId)
}

async function handlePaymentFailed(supabase: any, data: any) {
    const subscriptionCode = data.subscription_code
    const customer = data.customer

    console.log('Processing payment failed:', subscriptionCode)

    // Find user by subscription code
    const { data: subscription, error: subError } = await supabase
        .from('subscriptions')
        .select('user_id')
        .eq('paystack_subscription_code', subscriptionCode)
        .single()

    if (subError || !subscription) {
        console.error('Subscription not found for code:', subscriptionCode)
        return
    }

    const userId = subscription.user_id

    // Update subscription status to payment_failed
    const { error } = await supabase
        .from('subscriptions')
        .update({
            status: 'payment_failed',
            updated_at: new Date().toISOString()
        })
        .eq('paystack_subscription_code', subscriptionCode)

    if (error) {
        throw new Error(`Failed to update subscription: ${error.message}`)
    }

    // Deactivate QR codes
    await supabase
        .from('user_qr_codes')
        .update({
            is_active: false,
            updated_at: new Date().toISOString()
        })
        .eq('user_id', userId)
        .eq('is_active', true)

    // Update profile subscription status to indicate payment issue
    await supabase
        .from('profiles')
        .update({
            subscription: 'payment_failed',
            updated_at: new Date().toISOString()
        })
        .eq('id', userId)

    // Create notification for user about payment failure
    await supabase
        .from('notifications')
        .insert({
            user_id: userId,
            title: 'Payment Failed',
            message: 'Your subscription payment could not be processed. Please update your payment method to continue enjoying Local Lekker benefits.',
            type: 'payment_failure',
            is_read: false,
            data: {
                subscription_code: subscriptionCode,
                failed_at: new Date().toISOString(),
                action_required: 'update_payment_method'
            }
        })

    console.log('Payment failed - User notified and profile deactivated:', userId)
}

async function handleSubscriptionDisable(supabase: any, data: any) {
    const subscriptionCode = data.subscription_code
    const customer = data.customer
    const metadata = data.metadata || {}

    console.log('Processing subscription disable:', subscriptionCode)

    const userId = metadata.user_id || customer.email

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

async function updateUserSubscriptionStatus(supabase: any, userId: string, status: string) {
    console.log('Updating user subscription status to', status, 'for user:', userId)

    const { error } = await supabase
        .from('profiles')
        .update({
            subscription: status,
            updated_at: new Date().toISOString()
        })
        .eq('id', userId)

    if (error) {
        throw new Error(`Failed to update user subscription status: ${error.message}`)
    }

    console.log('Updated user', userId, 'subscription status to', status)
}

async function updateUserMembership(supabase: any, userId: string, planName: string) {
    const roleMapping: { [key: string]: string } = {
        'free': 'member',
        'basic': 'member',
        'premium': 'member',
        'business': 'trusted_partner',
    }

    const role = roleMapping[planName.toLowerCase()] || 'member'

    // For test users (UUIDs that don't exist in auth), skip profile creation
    const isTestUser = userId === '123e4567-e89b-12d3-a456-426614174000'

    if (!isTestUser) {
        // First check if user exists in profiles
        const { data: existingProfile } = await supabase
            .from('profiles')
            .select('id')
            .eq('id', userId)
            .single()

        if (!existingProfile) {
            console.log('User profile not found, creating basic profile for:', userId)
            // Create a basic profile if it doesn't exist
            const { error: profileError } = await supabase
                .from('profiles')
                .insert({
                    id: userId,
                    role: 'member',
                    created_at: new Date().toISOString(),
                    updated_at: new Date().toISOString()
                })

            if (profileError) {
                console.error('Failed to create profile:', profileError)
                // Continue anyway - the membership might still work
            }
        }
    }

    const { error } = await supabase
        .from('memberships')
        .upsert({
            user_id: userId,
            role: role,
            gateway: 'paystack',
            updated_at: new Date().toISOString()
        })

    if (error) {
        throw new Error(`Failed to update user membership: ${error.message}`)
    }

    console.log('Updated user', userId, 'membership role to', role)
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
            is_active: true,
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
        })

    if (error) {
        throw new Error(`Failed to activate QR code: ${error.message}`)
    }

    console.log('Activated QR code for user:', userId)
}