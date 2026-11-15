import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2"
import type { DealPayment, DealPaymentStore } from "./deal-payments.ts"
import type { VerifiedTransaction } from "./subscription-billing.ts"

export class SupabaseDealPaymentStore implements DealPaymentStore {
  constructor(private client: SupabaseClient) {}

  async prepare(userId: string, dealId: string): Promise<DealPayment> {
    const { data, error } = await this.client.rpc("prepare_deal_payment", {
      p_user_id: userId, p_deal_id: dealId,
    })
    if (error) throw error
    return data
  }

  async find(reference: string, userId?: string): Promise<DealPayment | null> {
    let query = this.client.from("deal_payment_attempts").select("*").eq("reference", reference)
    if (userId) query = query.eq("user_id", userId)
    const { data, error } = await query.maybeSingle()
    if (error) throw error
    return data
  }

  async claim(payment: DealPayment): Promise<boolean> {
    const { data, error } = await this.client.rpc("claim_deal_payment", { p_payment_id: payment.id })
    if (error) throw error
    return data === true
  }

  async retry(payment: DealPayment): Promise<DealPayment> {
    const { data, error } = await this.client.rpc("retry_deal_payment", {
      p_payment_id: payment.id, p_reference: payment.reference,
    })
    if (error) throw error
    return data
  }

  async card(userId: string, authorizationCode: string): Promise<string> {
    if (!authorizationCode) throw new Error("Choose a saved card")
    const { data, error } = await this.client.from("members_card_details").select("authorization_code")
      .eq("user_id", userId).eq("authorization_code", authorizationCode).eq("is_active", true).single()
    if (error) throw error
    return data.authorization_code
  }

  async outcome(reference: string, state: string, url?: string): Promise<void> {
    const { error } = await this.client.rpc("record_deal_payment_outcome", {
      p_reference: reference, p_state: state, p_authorization_url: url ?? null,
    })
    if (error) throw error
  }

  async finalise(payment: DealPayment, transaction: VerifiedTransaction): Promise<void> {
    const { error } = await this.client.rpc("finalise_deal_payment", {
      p_deal_id: payment.deal_id, p_user_id: payment.user_id, p_reference: transaction.reference,
      p_transaction_id: String(transaction.id), p_amount_cents: transaction.amount,
      p_currency: transaction.currency, p_paid_at: transaction.paid_at,
    })
    if (error) throw error
  }
}
