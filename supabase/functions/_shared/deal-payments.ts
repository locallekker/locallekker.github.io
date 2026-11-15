import type { BillingProvider, VerifiedTransaction } from "./subscription-billing.ts"

export interface DealPayment {
  id: string
  deal_id: string
  user_id: string
  reference: string
  amount_cents: number
  currency: string
  subaccount_code: string
  state: string
  authorization_url: string | null
  email: string
  customer_code: string | null
}

export interface DealPaymentStore {
  prepare(userId: string, dealId: string): Promise<DealPayment>
  find(reference: string, userId?: string): Promise<DealPayment | null>
  claim(payment: DealPayment): Promise<boolean>
  retry(payment: DealPayment): Promise<DealPayment>
  card(userId: string, authorizationCode: string): Promise<string>
  outcome(reference: string, state: string, url?: string): Promise<void>
  finalise(payment: DealPayment, transaction: VerifiedTransaction): Promise<void>
}

export interface DealPaymentResult {
  state: string
  reference: string
  authorization_url?: string
  transaction?: VerifiedTransaction
}

type Provider = Pick<BillingProvider, "submit" | "verify">

export async function reconcileDealPayment(
  store: DealPaymentStore,
  provider: Provider,
  payment: DealPayment,
): Promise<DealPaymentResult> {
  const transaction = await provider.verify(payment.reference)
  const checkout = payment.authorization_url
    ? { authorization_url: payment.authorization_url } : {}
  if (!transaction) {
    await store.outcome(payment.reference, "unknown")
    return { state: "unknown", reference: payment.reference, ...checkout }
  }
  if (transaction.reference !== payment.reference ||
      transaction.amount !== payment.amount_cents || transaction.currency !== payment.currency ||
      transaction.metadata?.user_id !== payment.user_id ||
      transaction.metadata?.payment_type !== "one_time_payment" ||
      transaction.metadata?.deal_authorization_id !== payment.deal_id ||
      transaction.metadata?.deal_payment_id !== payment.id) {
    throw new Error("Verified payment does not match this deal")
  }
  if (transaction.status === "success") {
    await store.finalise(payment, transaction)
    return { state: "paid", reference: payment.reference, transaction }
  }
  const state = transaction.status === "failed" ? "failed" : "pending"
  await store.outcome(payment.reference, state)
  return { state, reference: payment.reference, transaction, ...checkout }
}

export async function runDealPayment(
  store: DealPaymentStore,
  provider: Provider,
  request: {
    userId: string
    dealId: string
    action: "checkout" | "charge"
    authorizationCode?: string
    cvv?: string
    callbackUrl?: string
    useCustomerCode?: boolean
  },
): Promise<DealPaymentResult> {
  let payment = await store.prepare(request.userId, request.dealId)
  if (payment.state === "failed") {
    const previous = await reconcileDealPayment(store, provider, payment)
    if (previous.state !== "failed") return previous
    payment = await store.retry(payment)
  }
  if (payment.state !== "ready") return await reconcileDealPayment(store, provider, payment)
  const authorizationCode = request.action === "charge"
    ? await store.card(request.userId, request.authorizationCode ?? "") : undefined
  if (request.action === "checkout" && !request.callbackUrl) throw new Error("Checkout callback is required")
  if (!await store.claim(payment)) return await reconcileDealPayment(store, provider, payment)
  let response: Record<string, unknown>
  try {
    response = await provider.submit(
      request.action === "checkout" ? "/transaction/initialize" : "/transaction/charge_authorization",
      {
        email: payment.email,
        ...(request.useCustomerCode && payment.customer_code ? { customer: payment.customer_code } : {}),
        amount: payment.amount_cents, currency: payment.currency,
        reference: payment.reference, subaccount: payment.subaccount_code, bearer: "account",
        metadata: { user_id: payment.user_id, payment_type: "one_time_payment",
          deal_authorization_id: payment.deal_id, deal_payment_id: payment.id },
        ...(authorizationCode ? { authorization_code: authorizationCode } : {}),
        ...(request.cvv ? { cvv: request.cvv } : {}),
        ...(request.action === "checkout" ? { callback_url: request.callbackUrl, channels: ["card"] } : {}),
      },
    )
  } catch (error) {
    console.error(`Deal payment outcome unknown ref=${payment.reference}`, error)
    await store.outcome(payment.reference, "unknown")
    return { state: "unknown", reference: payment.reference }
  }
  if (request.action === "checkout" && typeof response.authorization_url === "string") {
    await store.outcome(payment.reference, "pending", response.authorization_url)
    return { state: "pending", reference: payment.reference, authorization_url: response.authorization_url }
  }
  return await reconcileDealPayment(store, provider, payment)
}
