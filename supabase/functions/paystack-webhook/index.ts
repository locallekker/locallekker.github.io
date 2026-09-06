// Paystack Webhook Handler
// Handles: charge.success (subscriptions + deals), subscription.charge (auto-renewal),
//          invoice.payment_failed, subscription.disable
//
// SECURITY: Verifies webhook signatures using HMAC SHA-512 with the Paystack secret key.
// RECOVERY: Acts as a safety net when the app is killed mid-payment.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-paystack-signature',
}

// ── HMAC SHA-512 signature verification ──────────────────────────────
async function verifySignature(
    rawBody: string,
    signature: string,
    secretKey: string,
): Promise<boolean> {
    const encoder = new TextEncoder()
    const key = await crypto.subtle.importKey(
        'raw',
        encoder.encode(secretKey),
        { name: 'HMAC', hash: 'SHA-512' },
        false,
        ['sign'],
    )
    const sig = await crypto.subtle.sign('HMAC', key, encoder.encode(rawBody))
    const hashHex = Array.from(new Uint8Array(sig))
        .map(b => b.toString(16).padStart(2, '0'))
        .join('')
    return hashHex === signature
}

// ── Date helpers (mirror Dart SubscriptionService logic) ─────────────
// Adds one calendar month, clamping the day (e.g. Jan 31 → Feb 28). Mirrors
// SubscriptionService.oneCalendarMonthFrom so webhook-activated periods match
// app-activated periods exactly.
function oneCalendarMonthFrom(from: Date): Date {
    const year = from.getFullYear()
    const month = from.getMonth() // 0-based
    const day = from.getDate()
    // Last day of the target month (month + 1), used to clamp overflow.
    const maxDay = new Date(year, month + 2, 0).getDate()
    const clampedDay = day > maxDay ? maxDay : day
    return new Date(
        year, month + 1, clampedDay,
        from.getHours(), from.getMinutes(), from.getSeconds(), from.getMilliseconds(),
    )
}

// Adds N calendar months using native rollover. Mirrors the intro-campaign
// free-period calc in the app: DateTime(year, month + freeMonths, day).
function addMonths(from: Date, months: number): Date {
    return new Date(
        from.getFullYear(), from.getMonth() + months, from.getDate(),
        from.getHours(), from.getMinutes(), from.getSeconds(), from.getMilliseconds(),
    )
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    // Read the raw body BEFORE parsing JSON (needed for signature verification)
    const rawBody = await req.text()

    try {
        const supabaseUrl = Deno.env.get('SUPABASE_URL')!
        const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
        const paystackSecretKeyRaw = Deno.env.get('PAYSTACK_SECRET_KEY') ?? ''
        const paystackSecretKey = paystackSecretKeyRaw.trim()

        // ── Signature verification ────────────────────────────
        const signature = req.headers.get('x-paystack-signature')

        if (!signature) {
            console.error('REJECTED: Missing x-paystack-signature header')
            return new Response(JSON.stringify({ error: 'Missing signature' }), {
                status: 401,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            })
        }

        if (!paystackSecretKey) {
            console.error('REJECTED: PAYSTACK_SECRET_KEY not configured')
            return new Response(JSON.stringify({ error: 'Server misconfigured' }), {
                status: 500,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            })
        }

        const isValid = await verifySignature(rawBody, signature, paystackSecretKey)
        if (!isValid) {
            console.error('REJECTED: Invalid HMAC signature')
            return new Response(JSON.stringify({ error: 'Invalid signature' }), {
                status: 401,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            })
        }

        // ── Parse & dispatch ──────────────────────────────────
        const supabase = createClient(supabaseUrl, supabaseServiceKey)
        const webhookData = JSON.parse(rawBody)
        const event = webhookData.event
        const data = webhookData.data

        console.log(`Webhook OK: ${event} ref=${data?.reference ?? 'n/a'}`)

        if (!data) {
            return new Response(JSON.stringify({ error: 'No data' }), {
                status: 400,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            })
        }

        switch (event) {
            case 'charge.success':
                await handleChargeSuccess(supabase, data)
                break
            case 'subscription.create':
                await handleSubscriptionCreate(supabase, data)
                break
            case 'subscription.charge':
                await handleSubscriptionCharge(supabase, data)
                break
            case 'invoice.payment_failed':
                await handlePaymentFailed(supabase, data)
                break
            case 'subscription.disable':
                await handleSubscriptionDisable(supabase, data)
                break
            case 'transfer.failed':
            case 'transfer.reversed':
                await handleTransferFailed(supabase, data, event)
                break
            default:
                console.log('Unhandled event:', event)
        }

        return new Response(JSON.stringify({ status: 'success' }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        })
    } catch (error) {
        console.error('Webhook error:', error)
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 400,
        })
    }
})

// ═══════════════════════════════════════════════════════════════════════
// charge.success — dispatches to subscription OR deal payment recovery
// ═══════════════════════════════════════════════════════════════════════
async function handleChargeSuccess(supabase: any, data: any) {
    const reference = data.reference
    const amount = data.amount
    const metadata = data.metadata || {}
    const userId = metadata.user_id
    const paymentType = metadata.payment_type || 'unknown'

    console.log(`charge.success ref=${reference} type=${paymentType} user=${userId}`)

    if (!userId) {
        console.warn('charge.success: no user_id in metadata, skipping')
        return
    }

    // ── Subscription payment ──────────────────────────────
    if (paymentType === 'subscription') {
        await recoverSubscriptionPayment(supabase, userId, reference, amount, metadata)
        return
    }

    // ── Intro campaign (R1) entry-offer payment ───────────
    if (paymentType === 'promotion_intro') {
        await recoverIntroCampaignPayment(supabase, userId, reference, amount, metadata)
        return
    }

    // ── Deal / one-time payment ───────────────────────────
    if (paymentType === 'one_time_payment') {
        await recoverDealPayment(supabase, userId, reference, amount, metadata)
        return
    }

    // ── Saved card setup ────────────────────────────────────────────
    // Web checkout returns by reloading the PWA, so the client-side WebView
    // callback cannot be relied upon to store the new reusable authorization.
    if (paymentType === 'payment_method_setup') {
        await recoverPaymentMethodSetup(supabase, userId, data)
        return
    }

    console.log(`charge.success: unrecognized payment_type "${paymentType}", skipping`)
}

async function recoverPaymentMethodSetup(supabase: any, userId: string, data: any) {
    const authorization = data.authorization ?? {}
    const authorizationCode = authorization.authorization_code

    if (!authorizationCode || authorization.reusable !== true) {
        console.warn(`payment_method_setup: no reusable authorization for user ${userId}`)
        return
    }

    const cardPayload = {
        card_type: authorization.card_type ?? 'card',
        last4: authorization.last4 ?? '****',
        exp_month: authorization.exp_month ?? null,
        exp_year: authorization.exp_year ?? null,
        bank: authorization.bank ?? null,
        brand: authorization.brand ?? null,
        is_active: true,
        updated_at: new Date().toISOString(),
    }

    const { data: existing, error: lookupError } = await supabase
        .from('members_card_details')
        .select('id')
        .eq('user_id', userId)
        .eq('authorization_code', authorizationCode)
        .maybeSingle()

    if (lookupError) {
        console.error('payment_method_setup: card lookup failed:', lookupError.message)
        return
    }

    if (existing) {
        const { error } = await supabase
            .from('members_card_details')
            .update(cardPayload)
            .eq('id', existing.id)
        if (error) console.error('payment_method_setup: card refresh failed:', error.message)
        return
    }

    const { data: activeCards, error: countError } = await supabase
        .from('members_card_details')
        .select('id')
        .eq('user_id', userId)
        .eq('is_active', true)

    if (countError || (activeCards?.length ?? 0) >= 3) {
        console.error('payment_method_setup: card limit check failed or limit reached')
        return
    }

    const { error } = await supabase.from('members_card_details').insert({
        user_id: userId,
        authorization_code: authorizationCode,
        ...cardPayload,
        is_primary: (activeCards?.length ?? 0) === 0,
        created_at: new Date().toISOString(),
    })
    if (error) console.error('payment_method_setup: card insert failed:', error.message)
}

// ── Subscription payment recovery ─────────────────────────────────────
async function recoverSubscriptionPayment(
    supabase: any,
    userId: string,
    reference: string,
    amount: number,
    metadata: any,
) {
    console.log(`Recovering subscription payment for user ${userId}`)

    // Check if already processed (idempotent)
    const { data: existingSub } = await supabase
        .from('subscriptions')
        .select('id, status, expires_at, current_period_end')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })
        .limit(1)
        .single()

    // If subscription is already active, this was handled by the app
    if (existingSub?.status === 'active') {
        console.log('Subscription already active, skipping')
        return
    }

    // Calculate expiry: 30 days from now (or from current expiry if still valid)
    const now = new Date()
    let baseDate = now
    const expiresAt = existingSub?.expires_at || existingSub?.current_period_end
    if (expiresAt) {
        const existing = new Date(expiresAt)
        if (existing > now) baseDate = existing
    }
    const newExpiry = oneCalendarMonthFrom(baseDate)
    const renewalChargeCents = Number(metadata.renewal_charge_cents ?? 9900)

    // Update subscription
    if (existingSub) {
        await supabase
            .from('subscriptions')
            .update({
                status: 'active',
                plan_type: 'subscription',
                current_period_start: now.toISOString(),
                current_period_end: newExpiry.toISOString(),
                auto_renew: true,
                renewal_charge_cents: renewalChargeCents,
                updated_at: now.toISOString(),
            })
            .eq('id', existingSub.id)
    } else {
        // Create new subscription
        await supabase.from('subscriptions').insert({
            user_id: userId,
            status: 'active',
            plan_type: 'subscription',
            current_period_start: now.toISOString(),
            current_period_end: newExpiry.toISOString(),
            auto_renew: true,
            renewal_charge_cents: renewalChargeCents,
            created_at: now.toISOString(),
            updated_at: now.toISOString(),
        })
    }

    // Activate profile
    await supabase
        .from('profiles')
        .update({
            subscription: 'active',
            subscription_status: 'active',
            updated_at: now.toISOString(),
        })
        .eq('id', userId)

    // Ensure user has an active QR code
    await ensureActiveQRCode(supabase, userId)

    // Notification
    await supabase.from('notifications').insert({
        user_id: userId,
        title: 'Subscription Activated',
        message: `Your Local Lekker subscription is active until ${newExpiry.toLocaleDateString('en-ZA')}.`,
        type: 'subscription_renewal',
        is_read: false,
        data: {
            reference,
            expires_at: newExpiry.toISOString(),
            amount: amount / 100,
            source: 'webhook',
        },
    })

    console.log(`Subscription activated for ${userId} until ${newExpiry.toISOString()}`)
}

// ── Intro campaign payment recovery ───────────────────────────────────
// Safety net: if the app was killed after Paystack charged the R1 intro fee
// but before activateIntroCampaignSubscription ran, this activates the
// promotional subscription server-side so the member isn't charged but stuck.
// Mirrors SubscriptionService.activateIntroCampaignSubscription.
async function recoverIntroCampaignPayment(
    supabase: any,
    userId: string,
    reference: string,
    amount: number,
    metadata: any,
) {
    console.log(`Recovering intro campaign payment for user ${userId}`)

    const promotionId = metadata.promotion_id
    const participantId = metadata.participant_id
    const initialChargeCents = Number(metadata.initial_charge_cents ?? 100)
    const renewalChargeCents = Number(metadata.renewal_charge_cents ?? 9900)

    if (!promotionId || !participantId) {
        console.warn('promotion_intro: missing promotion_id/participant_id in metadata, skipping')
        return
    }

    // Idempotent: if a subscription is already active, the app handled it.
    const { data: existingSub } = await supabase
        .from('subscriptions')
        .select('id, status')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })
        .limit(1)
        .single()

    if (existingSub?.status === 'active') {
        console.log('Intro subscription already active, skipping')
        return
    }

    // Authoritative free-month lookup. promotions.free_months IS NULL means a
    // lifetime membership (never expires) — see confirm_promo_signup(). Metadata
    // coerces NULL -> 0, which would create an already-expired subscription and
    // block the member from requesting deals after paying the R1 intro fee.
    let isLifetime = false
    let effectiveFreeMonths = Number(metadata.free_months ?? 0)
    {
        const { data: promoRow } = await supabase
            .from('promotions')
            .select('free_months')
            .eq('id', promotionId)
            .maybeSingle()
        if (promoRow) {
            if (promoRow.free_months === null || promoRow.free_months === undefined) {
                isLifetime = true
            } else {
                effectiveFreeMonths = Number(promoRow.free_months)
            }
        }
    }

    const now = new Date()
    // Never create an already-expired subscription. Lifetime → 100 years;
    // otherwise grant the free months, with a one-month floor so the R1 payment
    // always buys at least the first billing period before R99.
    const monthsToGrant = isLifetime ? 1200 : (effectiveFreeMonths > 0 ? effectiveFreeMonths : 1)
    const freePeriodEnd = addMonths(now, monthsToGrant)

    // Deactivate old QR codes, then issue a fresh one valid for the free period.
    await supabase.from('user_qr_codes').update({ is_active: false }).eq('user_id', userId)

    const { data: profile } = await supabase
        .from('profiles')
        .select('name, surname')
        .eq('id', userId)
        .single()

    await supabase.from('user_qr_codes').insert({
        user_id: userId,
        qr_code: `QR_${userId}_${now.getTime()}`,
        name: profile?.name ?? 'Unknown',
        surname: profile?.surname ?? 'Unknown',
        is_active: true,
        expires_at: freePeriodEnd.toISOString(),
        created_at: now.toISOString(),
        updated_at: now.toISOString(),
    })

    const subscriptionData: Record<string, unknown> = {
        user_id: userId,
        plan_type: 'promotion_intro',
        promotion_id: promotionId,
        promo_participant_id: participantId,
        current_period_start: now.toISOString(),
        current_period_end: freePeriodEnd.toISOString(),
        free_period_end: freePeriodEnd.toISOString(),
        initial_charge_cents: initialChargeCents,
        renewal_charge_cents: renewalChargeCents,
        intro_charge_reference: reference,
        intro_charge_paid_at: now.toISOString(),
        status: 'active',
        auto_renew: true,
        updated_at: now.toISOString(),
    }

    if (existingSub) {
        await supabase.from('subscriptions').update(subscriptionData).eq('id', existingSub.id)
    } else {
        subscriptionData.created_at = now.toISOString()
        await supabase.from('subscriptions').insert(subscriptionData)
    }

    // Activate profile
    await supabase
        .from('profiles')
        .update({
            subscription: 'active',
            subscription_status: 'active',
            updated_at: now.toISOString(),
        })
        .eq('id', userId)

    // Mark the promo participant as claimed
    await supabase
        .from('promotion_participant_emails')
        .update({
            is_claimed: true,
            claimed_by: userId,
            claimed_at: now.toISOString(),
        })
        .eq('id', participantId)

    // Notification
    await supabase.from('notifications').insert({
        user_id: userId,
        title: 'Entry Offer Activated',
        message: isLifetime
            ? `Welcome to Local Lekker! Your lifetime membership is now active.`
            : effectiveFreeMonths > 0
                ? `Welcome to Local Lekker! Enjoy ${effectiveFreeMonths} month(s) free until ${freePeriodEnd.toLocaleDateString('en-ZA')}.`
                : `Welcome to Local Lekker! Your membership is active until ${freePeriodEnd.toLocaleDateString('en-ZA')}.`,
        type: 'subscription_renewal',
        is_read: false,
        data: {
            reference,
            expires_at: freePeriodEnd.toISOString(),
            amount: amount / 100,
            promotion_id: promotionId,
            free_months: effectiveFreeMonths,
            lifetime: isLifetime,
            source: 'webhook',
        },
    })

    console.log(`Intro campaign activated for ${userId} until ${freePeriodEnd.toISOString()}`)
}

// ── Deal payment recovery ─────────────────────────────────────────────
// Safety net: if the app was killed after Paystack charged the card but
// before _handlePaymentSuccess ran, the deal stays in 'approved' state.
// This webhook marks it 'completed' so the member isn't charged but stuck.
async function recoverDealPayment(
    supabase: any,
    userId: string,
    reference: string,
    amount: number,
    metadata: any,
) {
    const dealAuthId = metadata.deal_authorization_id
    console.log(`Recovering deal payment user=${userId} deal=${dealAuthId ?? 'unknown'} ref=${reference}`)

    let deal: any = null

    // Strategy 1: Use deal_authorization_id from metadata (preferred)
    if (dealAuthId) {
        const { data } = await supabase
            .from('deal_authorizations')
            .select('id, status, payment_completed_at')
            .eq('id', dealAuthId)
            .single()
        deal = data
    }

    // Strategy 2: Find the most recent non-completed deal for this user
    if (!deal) {
        const { data } = await supabase
            .from('deal_authorizations')
            .select('id, status, payment_completed_at')
            .eq('member_id', userId)
            .in('status', ['approved', 'pending_payment'])
            .is('payment_completed_at', null)
            .order('created_at', { ascending: false })
            .limit(1)
            .single()
        deal = data
    }

    if (!deal) {
        console.log('No pending deal found for this payment (app probably handled it)')
        return
    }

    // Already completed? Skip (idempotent)
    if (deal.status === 'completed' && deal.payment_completed_at) {
        console.log(`Deal ${deal.id} already completed, skipping`)
        return
    }

    const now = new Date().toISOString()

    // Mark deal as completed
    const { error } = await supabase
        .from('deal_authorizations')
        .update({
            status: 'completed',
            payment_completed_at: now,
            payment_reference: reference,
            updated_at: now,
        })
        .eq('id', deal.id)

    if (error) {
        console.error(`Failed to complete deal ${deal.id}:`, error.message)
        return
    }

    // ── Fetch deal details for receipt generation ─────────────────────
    const { data: dealFull } = await supabase
        .from('deal_authorizations')
        .select(`
            *,
            trusted_partner_discounts(*, businesses(*)),
            profiles(*)
        `)
        .eq('id', deal.id)
        .single()

    const discountData = dealFull?.trusted_partner_discounts
    const businessData = discountData?.businesses
    const memberData = dealFull?.profiles
    const businessId = discountData?.business_id ?? dealFull?.business_id ?? null
    const trustedPartnerId = discountData?.trusted_partner_id ?? businessData?.owner_member_id ?? null
    const memberName = [memberData?.name, memberData?.surname].filter(Boolean).join(' ') || 'Member'
    const businessName = businessData?.name ?? 'Business'
    const dealName = discountData?.name ?? 'Deal'
    const dealAmount = (dealFull?.amount ?? amount / 100) as number

    // ── Generate receipt number ───────────────────────────────────────
    let receiptNumber = `RCP-${Date.now()}`
    if (businessId) {
        try {
            const { data: rpcResult } = await supabase.rpc('get_next_receipt_number', {
                p_business_id: businessId,
            })
            if (rpcResult) receiptNumber = rpcResult as string
        } catch (e) {
            console.warn('get_next_receipt_number failed, using fallback:', e)
        }
    }

    const qrCode = `RECEIPT:${deal.id}:${receiptNumber}`
    const transactionDate = new Date().toISOString()

    // ── Insert virtual_receipts ───────────────────────────────────────
    if (businessId) {
        const receiptData = {
            receipt_number: receiptNumber,
            deal_authorization_id: deal.id,
            business_name: businessName,
            business_id: businessId,
            member_name: memberName,
            member_email: memberData?.email ?? 'N/A',
            discount_name: dealName,
            amount: dealAmount,
            payment_method: 'in_app',
            transaction_date: transactionDate,
            status: 'completed',
        }

        const { error: vrError } = await supabase
            .from('virtual_receipts')
            .insert({
                deal_authorization_id: deal.id,
                receipt_number: receiptNumber,
                receipt_data: receiptData,
                qr_code: qrCode,
            })

        if (vrError) {
            console.error('Failed to insert virtual_receipt (webhook recovery):', vrError.message)
        } else {
            console.log(`virtual_receipt created for deal ${deal.id}: ${receiptNumber}`)
        }

        // ── Insert deal_receipts ──────────────────────────────────────
        const { error: drError } = await supabase
            .from('deal_receipts')
            .insert({
                member_id: memberData?.id ?? userId,
                trusted_partner_id: trustedPartnerId,
                business_id: businessId,
                deal_authorization_id: deal.id,
                receipt_number: receiptNumber,
                amount: dealAmount,
                business_name: businessName,
                discount_name: dealName,
                member_name: memberName,
                member_email: memberData?.email,
                payment_method: 'in_app',
            })

        if (drError) {
            console.error('Failed to insert deal_receipt (webhook recovery):', drError.message)
        } else {
            console.log(`deal_receipt created for deal ${deal.id}: ${receiptNumber}`)
        }
    }

    // ── Notify member ─────────────────────────────────────────────────
    await supabase.from('notifications').insert({
        user_id: userId,
        title: 'Payment Confirmed',
        message: `Your payment of R${dealAmount.toFixed(2)} to ${businessName} for ${dealName} was confirmed. Receipt #${receiptNumber} generated.`,
        type: 'payment_success',
        is_read: false,
        data: {
            deal_authorization_id: deal.id,
            reference,
            amount: dealAmount,
            receipt_number: receiptNumber,
            business_name: businessName,
            source: 'webhook',
        },
    })

    // ── Notify trusted partner ────────────────────────────────────────
    if (trustedPartnerId) {
        await supabase.from('notifications').insert({
            user_id: trustedPartnerId,
            title: '💰 Payment Received',
            message: `${memberName} paid R${dealAmount.toFixed(2)} for ${dealName}. Receipt #${receiptNumber} generated.`,
            type: 'payment_received',
            is_read: false,
            data: {
                deal_authorization_id: deal.id,
                member_id: userId,
                member_name: memberName,
                deal_name: dealName,
                amount: dealAmount,
                receipt_number: receiptNumber,
                business_name: businessName,
                source: 'webhook',
            },
        })
    }

    console.log(`Deal ${deal.id} recovered and marked completed, receipt: ${receiptNumber}`)
}

// ═══════════════════════════════════════════════════════════════════════
// subscription.create — Paystack created a subscription after plan payment
// Saves the subscription_code to the subscriptions table for webhook matching
// ═══════════════════════════════════════════════════════════════════════
async function handleSubscriptionCreate(supabase: any, data: any) {
    const subscriptionCode = data.subscription_code
    const customer = data.customer
    const plan = data.plan
    const status = data.status

    console.log(`subscription.create sub=${subscriptionCode} status=${status}`)

    if (!subscriptionCode) {
        console.warn('subscription.create: no subscription_code, skipping')
        return
    }

    // Find user by customer_code or email
    let userId: string | null = null

    if (customer?.customer_code) {
        const { data: profileByCode } = await supabase
            .from('profiles')
            .select('id')
            .eq('paystack_customer_code', customer.customer_code)
            .single()

        if (profileByCode) {
            userId = profileByCode.id
        }
    }

    if (!userId && customer?.email) {
        const { data: profileByEmail } = await supabase
            .from('profiles')
            .select('id')
            .eq('email', customer.email)
            .single()
        userId = profileByEmail?.id
    }

    if (!userId) {
        console.error(`subscription.create: User not found for customer: ${customer?.customer_code} / ${customer?.email}`)
        return
    }

    // Find the user's most recent subscription and save the Paystack subscription code
    const { data: existingSub } = await supabase
        .from('subscriptions')
        .select('id, paystack_subscription_code')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })
        .limit(1)
        .single()

    if (existingSub) {
        // Only update if not already set (avoid overwriting with stale data)
        if (!existingSub.paystack_subscription_code) {
            await supabase
                .from('subscriptions')
                .update({
                    paystack_subscription_code: subscriptionCode,
                    updated_at: new Date().toISOString(),
                })
                .eq('id', existingSub.id)

            console.log(`Saved subscription_code ${subscriptionCode} for user ${userId}`)
        } else {
            console.log(`Subscription already has code ${existingSub.paystack_subscription_code}, skipping`)
        }
    } else {
        console.warn(`No subscription record found for user ${userId} to attach subscription_code`)
    }
}

// ═══════════════════════════════════════════════════════════════════════
// subscription.charge — auto-renewal after initial subscription
// ═══════════════════════════════════════════════════════════════════════
async function handleSubscriptionCharge(supabase: any, data: any) {
    const subscriptionCode = data.subscription?.subscription_code || data.subscription_code
    const customer = data.customer
    const amount = data.amount
    const status = data.status
    const reference = data.reference

    console.log(`subscription.charge ref=${reference} status=${status}`)

    if (status !== 'success') {
        console.log('Charge not successful, skipping')
        return
    }

    // Find user by customer code, fallback to email
    let userId: string | null = null

    if (customer?.customer_code) {
        const { data: profileByCode } = await supabase
            .from('profiles')
            .select('id')
            .eq('paystack_customer_code', customer.customer_code)
            .single()

        if (profileByCode) {
            userId = profileByCode.id
        }
    }

    if (!userId && customer?.email) {
        const { data: profileByEmail } = await supabase
            .from('profiles')
            .select('id')
            .eq('email', customer.email)
            .single()
        userId = profileByEmail?.id
    }

    if (!userId) {
        console.error(`User not found for customer: ${customer?.customer_code} / ${customer?.email}`)
        return
    }

    // Get current subscription to compute new expiry
    const { data: currentSub } = await supabase
        .from('subscriptions')
        .select('id, expires_at, current_period_end')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })
        .limit(1)
        .single()

    const now = new Date()
    let baseDate = now
    const expiresAt = currentSub?.expires_at || currentSub?.current_period_end
    if (expiresAt) {
        const existing = new Date(expiresAt)
        if (existing > now) baseDate = existing
    }

    const newExpiry = oneCalendarMonthFrom(baseDate)

    // Update subscription
    if (currentSub) {
        await supabase
            .from('subscriptions')
            .update({
                status: 'active',
                current_period_end: newExpiry.toISOString(),
                paystack_subscription_code: subscriptionCode,
                updated_at: now.toISOString(),
            })
            .eq('id', currentSub.id)
    }

    // Reactivate profile
    await supabase
        .from('profiles')
        .update({
            subscription: 'active',
            subscription_status: 'active',
            updated_at: now.toISOString(),
        })
        .eq('id', userId)

    // Ensure QR code is active
    await ensureActiveQRCode(supabase, userId)

    // Notification
    await supabase.from('notifications').insert({
        user_id: userId,
        title: 'Subscription Renewed',
        message: `Your subscription has been automatically renewed until ${newExpiry.toLocaleDateString('en-ZA')}.`,
        type: 'subscription_renewal',
        is_read: false,
        data: {
            reference,
            expires_at: newExpiry.toISOString(),
            amount: amount / 100,
            subscription_code: subscriptionCode,
            source: 'webhook',
        },
    })

    console.log(`Subscription renewal processed for ${userId} until ${newExpiry.toISOString()}`)
}

// ═══════════════════════════════════════════════════════════════════════
// invoice.payment_failed
// ═══════════════════════════════════════════════════════════════════════
async function handlePaymentFailed(supabase: any, data: any) {
    const subscriptionCode = data.subscription_code
    console.log(`payment_failed sub=${subscriptionCode}`)

    // Find user by subscription code
    const { data: subscription } = await supabase
        .from('subscriptions')
        .select('user_id')
        .eq('paystack_subscription_code', subscriptionCode)
        .single()

    if (!subscription) {
        console.error('Subscription not found:', subscriptionCode)
        return
    }

    const userId = subscription.user_id
    const now = new Date().toISOString()

    // Mark subscription as payment_failed
    await supabase
        .from('subscriptions')
        .update({ status: 'payment_failed', updated_at: now })
        .eq('paystack_subscription_code', subscriptionCode)

    // Deactivate QR codes
    await supabase
        .from('user_qr_codes')
        .update({ is_active: false, updated_at: now })
        .eq('user_id', userId)
        .eq('is_active', true)

    // Update profile
    await supabase
        .from('profiles')
        .update({ subscription: 'payment_failed', updated_at: now })
        .eq('id', userId)

    // Notification
    await supabase.from('notifications').insert({
        user_id: userId,
        title: 'Payment Failed',
        message: 'Your subscription payment failed. Please update your payment method to keep enjoying Local Lekker benefits.',
        type: 'payment_failure',
        is_read: false,
        data: {
            subscription_code: subscriptionCode,
            failed_at: now,
            action_required: 'update_payment_method',
            source: 'webhook',
        },
    })

    console.log(`Payment failed handled for ${userId}`)
}

// ═══════════════════════════════════════════════════════════════════════
// subscription.disable — voluntary cancellation
// ═══════════════════════════════════════════════════════════════════════
async function handleSubscriptionDisable(supabase: any, data: any) {
    const subscriptionCode = data.subscription_code
    console.log(`subscription.disable sub=${subscriptionCode}`)

    // Find subscription
    const { data: subscription } = await supabase
        .from('subscriptions')
        .select('user_id')
        .eq('paystack_subscription_code', subscriptionCode)
        .single()

    if (!subscription) {
        console.error('Subscription not found:', subscriptionCode)
        return
    }

    const userId = subscription.user_id
    const now = new Date().toISOString()

    await supabase
        .from('subscriptions')
        .update({ status: 'cancelled', updated_at: now })
        .eq('paystack_subscription_code', subscriptionCode)

    // Don't deactivate QR right away — let current period expire naturally
    // The app's checkAndHandleExpiredSubscription() handles expiry

    console.log(`Subscription cancelled for ${userId}`)
}

// ═══════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════
async function ensureActiveQRCode(supabase: any, userId: string) {
    const { data: existingQR } = await supabase
        .from('user_qr_codes')
        .select('id')
        .eq('user_id', userId)
        .eq('is_active', true)
        .single()

    if (existingQR) {
        console.log('User already has active QR code')
        return
    }

    const now = new Date()
    const expiresAt = oneCalendarMonthFrom(now)

    await supabase.from('user_qr_codes').insert({
        user_id: userId,
        qr_code: `QR_${userId}_${now.getTime()}`,
        is_active: true,
        expires_at: expiresAt.toISOString(),
        created_at: now.toISOString(),
        updated_at: now.toISOString(),
    })

    console.log(`Created QR code for ${userId}`)
}

// ═══════════════════════════════════════════════════════════════════════
// transfer.failed / transfer.reversed
// Fires when Paystack cannot settle funds to a subaccount's bank account.
// This is the server-side signal for the "pending 24h then failed" pattern
// caused by unverifiable ZAR bank accounts on subaccounts.
// ═══════════════════════════════════════════════════════════════════════
async function handleTransferFailed(supabase: any, data: any, event: string) {
    const transferCode = data.transfer_code ?? data.reference ?? 'unknown'
    const recipient = data.recipient
    const subaccountCode = recipient?.details?.account_number
        ? `ACCT_${recipient?.code ?? 'unknown'}`
        : recipient?.code ?? 'unknown'
    const amount = (data.amount ?? 0) / 100
    const reason = data.reason ?? data.gateway_response ?? 'Unknown reason'
    const now = new Date().toISOString()

    console.error(`${event}: transfer_code=${transferCode} subaccount=${subaccountCode} amount=R${amount} reason=${reason}`)

    // Find the trusted partner linked to this subaccount so we can notify them
    const { data: bankingRow } = await supabase
        .from('trusted_partner_bank_accounts')
        .select('user_id, bank_name, account_holder_name')
        .eq('subaccount_code', subaccountCode)
        .maybeSingle()

    if (bankingRow) {
        const partnerId = bankingRow.user_id

        // Notify the trusted partner that their settlement failed
        await supabase.from('notifications').insert({
            user_id: partnerId,
            title: '⚠️ Settlement Failed',
            message: `A payment settlement of R${amount.toFixed(2)} to your bank account failed. Please verify your banking details in your Business Profile to avoid future payment issues.`,
            type: 'settlement_failed',
            is_read: false,
            data: {
                transfer_code: transferCode,
                subaccount_code: subaccountCode,
                amount,
                reason,
                event,
                failed_at: now,
                action_required: 'update_banking_details',
            },
        })

        console.log(`Settlement failure notification sent to partner ${partnerId}`)
    } else {
        // Subaccount not matched in DB — log for manual investigation
        console.error(`transfer.failed: No DB record for subaccount=${subaccountCode}. Manual investigation required. Amount: R${amount}`)
    }

    // Notify all admin users so they can investigate and manually refund/reroute
    const { data: admins } = await supabase
        .from('profiles')
        .select('id')
        .eq('role', 'admin')

    if (admins && admins.length > 0) {
        const adminNotifications = admins.map((admin: any) => ({
            user_id: admin.id,
            title: '🚨 Partner Settlement Failed',
            message: `Settlement of R${amount.toFixed(2)} to subaccount ${subaccountCode} failed (${reason}). Manual action required.`,
            type: 'admin_settlement_failed',
            is_read: false,
            data: {
                transfer_code: transferCode,
                subaccount_code: subaccountCode,
                amount,
                reason,
                event,
                failed_at: now,
                partner_user_id: bankingRow?.user_id ?? null,
            },
        }))
        await supabase.from('notifications').insert(adminNotifications)
        console.log(`Admin settlement failure alert sent to ${admins.length} admin(s)`)
    }
}
