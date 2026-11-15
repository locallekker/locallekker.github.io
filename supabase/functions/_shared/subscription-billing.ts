export interface BillingCycle {
  id: string
  subscription_id: string
  user_id: string
  reference: string
  amount_cents: number
  currency: string
  purpose: string
  state: string
  authorization_url: string | null
  promotion_id: string | null
  participant_id: string | null
}

export interface BillingContext {
  email: string
  customerCode: string | null
  owner: string | null
  name?: string | null
  surname?: string | null
}

export interface BillingStore {
  context(userId: string): Promise<BillingContext>
  saveCustomer(userId: string, customerCode: string): Promise<void>
  prepare(userId: string, automatic: boolean, promotionId?: string, participantId?: string): Promise<BillingCycle>
  find(reference: string, userId?: string): Promise<BillingCycle | null>
  claim(cycleId: string, automatic: boolean): Promise<boolean>
  retry(cycle: BillingCycle, transactionId: string): Promise<BillingCycle>
  card(userId: string, authorizationCode?: string): Promise<string>
  outcome(reference: string, state: "pending" | "unknown" | "failed", detail: string, url?: string): Promise<void>
  finalise(cycle: BillingCycle, transaction: VerifiedTransaction): Promise<void>
}

export interface VerifiedTransaction {
  id: string | number
  reference: string
  status: string
  amount: number
  currency: string
  paid_at: string | null
  metadata: Record<string, unknown> | null
  authorization?: Record<string, unknown>
  customer?: Record<string, unknown>
}

export interface BillingProvider {
  ensureCustomer(email: string, customerCode: string | null, name?: string | null, surname?: string | null): Promise<string>
  assertNoRecurringSubscription(customerCode: string): Promise<void>
  submit(path: string, body: Record<string, unknown>): Promise<Record<string, unknown>>
  verify(reference: string): Promise<VerifiedTransaction | null>
}

export interface BillingRequest {
  userId: string
  action: "charge" | "checkout" | "verify"
  automatic?: boolean
  authorizationCode?: string
  cvv?: string
  reference?: string
  callbackUrl?: string
  promotionId?: string
  participantId?: string
  useCustomerCode?: boolean
}

export interface BillingResult {
  state: string
  reference: string
  authorization_url?: string
  transaction?: VerifiedTransaction
  message?: string
}

export async function reconcileBilling(
  store: BillingStore,
  provider: BillingProvider,
  cycle: BillingCycle,
): Promise<BillingResult> {
  const transaction = await provider.verify(cycle.reference)
  if (!transaction) {
    return { state: cycle.state === "paid" ? "paid" : "unknown", reference: cycle.reference,
      message: "Payment status is being checked. Do not start another payment." }
  }
  if (transaction.reference !== cycle.reference ||
    transaction.amount !== cycle.amount_cents || transaction.currency !== cycle.currency ||
    transaction.metadata?.user_id !== cycle.user_id ||
    transaction.metadata?.payment_type !== cycle.purpose ||
    transaction.metadata?.billing_cycle_id !== cycle.id) {
    throw new Error("Verified payment does not match the billing obligation")
  }
  if (transaction.status === "success") {
    await store.finalise(cycle, transaction)
    return { state: "paid", reference: cycle.reference, transaction }
  }
  // Abandoned checkouts and missing references can still be completed later.
  if (transaction.status === "failed") {
    await store.outcome(cycle.reference, "failed", "Paystack verified this attempt failed")
    return { state: "failed", reference: cycle.reference, transaction,
      message: "Payment failed. You may try again; the previous failure will be verified before another attempt." }
  }
  await store.outcome(cycle.reference, "pending", `Verified provider status: ${transaction.status}`)
  return { state: "pending", reference: cycle.reference,
    ...(cycle.authorization_url ? { authorization_url: cycle.authorization_url } : {}) }
}

export async function runSubscriptionBilling(
  store: BillingStore,
  provider: BillingProvider,
  request: BillingRequest,
): Promise<BillingResult> {
  if (request.action === "verify") {
    if (!request.reference) throw new Error("Payment reference is required")
    const cycle = await store.find(request.reference, request.userId)
    if (!cycle) throw new Error("Subscription payment was not found for this account")
    return await reconcileBilling(store, provider, cycle)
  }

  const context = await store.context(request.userId)
  if (context.owner !== null && context.owner !== "server") {
    throw new Error("billing_migration_required: Your membership billing must be reconciled before another payment")
  }
  const customerCode = await provider.ensureCustomer(context.email, context.customerCode, context.name, context.surname)
  // Check Paystack, not merely the locally stored SUB code, before every new submission.
  await provider.assertNoRecurringSubscription(customerCode)
  await store.saveCustomer(request.userId, customerCode)
  let cycle = await store.prepare(request.userId, request.automatic === true,
    request.promotionId, request.participantId)
  if (cycle.state === "failed" && request.automatic !== true) {
    const previous = await reconcileBilling(store, provider, cycle)
    if (previous.state !== "failed" || !previous.transaction) return previous
    cycle = await store.retry(cycle, String(previous.transaction.id))
  }
  if (cycle.state !== "ready") {
    if (cycle.state === "cancelled") throw new Error("This payment was cancelled; contact support")
    return await reconcileBilling(store, provider, cycle)
  }

  // Validate inputs before the irreversible submission claim.
  const authorizationCode = request.action === "charge"
    ? await store.card(request.userId, request.authorizationCode) : undefined
  if (request.action === "checkout" && !request.callbackUrl) throw new Error("Checkout callback is not configured")
  if (!await store.claim(cycle.id, request.automatic === true)) {
    const current = await store.find(cycle.reference, request.userId)
    if (!current) throw new Error("Billing obligation disappeared")
    return await reconcileBilling(store, provider, current)
  }
  const metadata = {
    user_id: cycle.user_id,
    payment_type: cycle.purpose,
    billing_cycle_id: cycle.id,
    subscription_id: cycle.subscription_id,
    promotion_id: cycle.promotion_id,
    participant_id: cycle.participant_id,
  }
  let response: Record<string, unknown>
  try {
    response = await provider.submit(
      request.action === "checkout" ? "/transaction/initialize" : "/transaction/charge_authorization",
      {
        email: context.email,
        ...(request.useCustomerCode !== false ? { customer: customerCode } : {}),
        amount: cycle.amount_cents, currency: cycle.currency,
        reference: cycle.reference, metadata,
        ...(authorizationCode ? { authorization_code: authorizationCode } : {}),
        ...(request.cvv ? { cvv: request.cvv } : {}),
        ...(request.action === "checkout" ? { callback_url: request.callbackUrl, channels: ["card"] } : {}),
      },
    )
  } catch (error) {
    console.error(`Subscription submission outcome unknown ref=${cycle.reference}`, error)
    await store.outcome(cycle.reference, "unknown", "Submission interrupted; verify before any retry")
    return { state: "unknown", reference: cycle.reference,
      message: "Payment status is being checked. Do not start another payment." }
  }
  if (request.action === "checkout" && typeof response.authorization_url === "string") {
    await store.outcome(cycle.reference, "pending", "Hosted checkout created", response.authorization_url)
    return { state: "pending", reference: cycle.reference, authorization_url: response.authorization_url }
  }
  // A charge response is not finalisation. Verify the provider's recorded transaction.
  return await reconcileBilling(store, provider, cycle)
}
