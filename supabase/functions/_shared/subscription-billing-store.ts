import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2"
import type { BillingContext, BillingCycle, BillingStore, VerifiedTransaction } from "./subscription-billing.ts"

export class SupabaseBillingStore implements BillingStore {
  constructor(private client: SupabaseClient) {}

  async context(userId: string): Promise<BillingContext> {
    const { data: profile, error } = await this.client.from("profiles")
      .select("email, paystack_customer_code, name, surname").eq("id", userId).single()
    if (error) throw error
    const { data: sub, error: subError } = await this.client.from("subscriptions")
      .select("billing_owner").eq("user_id", userId).order("created_at", { ascending: false }).limit(1).maybeSingle()
    if (subError) throw subError
    return { email: profile.email, customerCode: profile.paystack_customer_code,
      owner: sub?.billing_owner ?? null, name: profile.name, surname: profile.surname }
  }

  async saveCustomer(userId: string, customerCode: string): Promise<void> {
    const { error } = await this.client.from("profiles").update({ paystack_customer_code: customerCode }).eq("id", userId)
    if (error) throw error
  }

  async prepare(userId: string, automatic: boolean, promotionId?: string, participantId?: string): Promise<BillingCycle> {
    const { data, error } = await this.client.rpc("prepare_subscription_billing", {
      p_user_id: userId, p_automatic: automatic, p_promotion_id: promotionId ?? null,
      p_participant_id: participantId ?? null,
    })
    if (error) throw error
    return data
  }

  async find(reference: string, userId?: string): Promise<BillingCycle | null> {
    let query = this.client.from("subscription_billing_cycles").select("*").eq("reference", reference)
    if (userId) query = query.eq("user_id", userId)
    const { data, error } = await query.maybeSingle()
    if (error) throw error
    return data
  }

  async claim(cycleId: string, automatic: boolean): Promise<boolean> {
    const { data, error } = await this.client.rpc("claim_subscription_billing", {
      p_cycle_id: cycleId, p_automatic: automatic,
    })
    if (error) throw error
    return data === true
  }

  async card(userId: string, authorizationCode?: string): Promise<string> {
    let query = this.client.from("members_card_details").select("authorization_code")
      .eq("user_id", userId).eq("is_active", true)
    query = authorizationCode ? query.eq("authorization_code", authorizationCode) : query.eq("is_primary", true)
    const { data, error } = await query.single()
    if (error) throw error
    if (!data.authorization_code) throw new Error("No saved reusable payment method is available")
    return data.authorization_code
  }

  async retry(cycle: BillingCycle, transactionId: string): Promise<BillingCycle> {
    const { data, error } = await this.client.rpc("retry_subscription_billing", {
      p_cycle_id: cycle.id, p_failed_reference: cycle.reference, p_transaction_id: transactionId,
    })
    if (error) throw error
    return data
  }

  async outcome(reference: string, state: "pending" | "unknown" | "failed", detail: string, url?: string): Promise<void> {
    const { error } = await this.client.rpc("record_subscription_billing_outcome", {
      p_reference: reference, p_state: state, p_detail: detail, p_authorization_url: url ?? null,
    })
    if (error) throw error
  }

  async finalise(cycle: BillingCycle, transaction: VerifiedTransaction): Promise<void> {
    const { error } = await this.client.rpc("finalise_subscription_billing", {
      p_reference: cycle.reference, p_transaction_id: String(transaction.id),
      p_amount_cents: transaction.amount, p_currency: transaction.currency,
      p_user_id: cycle.user_id, p_paid_at: transaction.paid_at,
      p_authorization: transaction.authorization ?? null,
    })
    if (error) throw error
  }
}
