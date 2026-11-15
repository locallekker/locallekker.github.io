import type { BillingProvider, VerifiedTransaction } from "./subscription-billing.ts"

interface ProviderResponse {
  status: boolean
  message: string
  data: Record<string, unknown>
}

export class PaystackBillingProvider implements BillingProvider {
  private secret: string

  constructor(secret: string) {
    if (!secret) throw new Error("PAYSTACK_SECRET_KEY is not configured")
    this.secret = secret
  }

  private async request(path: string, body?: Record<string, unknown>): Promise<ProviderResponse> {
    const response = await fetch(`https://api.paystack.co${path}`, {
      method: body ? "POST" : "GET",
      headers: { Authorization: `Bearer ${this.secret}`, "Content-Type": "application/json" },
      ...(body ? { body: JSON.stringify(body) } : {}),
      signal: AbortSignal.timeout(20000),
    })
    const result = await response.json() as ProviderResponse
    if (!response.ok || result.status !== true) {
      throw new Error(`Paystack request failed (${response.status}): ${result.message}`)
    }
    return result
  }

  async ensureCustomer(email: string, customerCode: string | null, name?: string | null, surname?: string | null): Promise<string> {
    if (customerCode) return customerCode
    // Customer creation also resolves an existing customer with the same email.
    const result = await this.request("/customer", {
      email, ...(name ? { first_name: name } : {}), ...(surname ? { last_name: surname } : {}),
    })
    if (typeof result.data.customer_code !== "string") throw new Error("Customer code missing from Paystack")
    return result.data.customer_code
  }

  async assertNoRecurringSubscription(customerCode: string): Promise<void> {
    const result = await this.request(`/customer/${encodeURIComponent(customerCode)}`)
    if (!Array.isArray(result.data.subscriptions)) throw new Error("Provider subscription inventory unavailable")
    const subscriptions: unknown[] = result.data.subscriptions
    const unresolved = subscriptions.some(subscription => {
      if (typeof subscription !== "object" || subscription === null || !("status" in subscription)) return true
      return !["complete", "cancelled", "disabled"].includes(String(subscription.status))
    })
    if (unresolved) throw new Error("billing_migration_required: A provider-managed subscription must be resolved first")
  }

  async submit(path: string, body: Record<string, unknown>): Promise<Record<string, unknown>> {
    return (await this.request(path, body)).data
  }

  async verify(reference: string): Promise<VerifiedTransaction | null> {
    try {
      const result = await this.request(`/transaction/verify/${encodeURIComponent(reference)}`)
      const data = result.data
      if ((typeof data.id !== "number" && typeof data.id !== "string") ||
        typeof data.reference !== "string" || typeof data.status !== "string" ||
        typeof data.amount !== "number" || typeof data.currency !== "string") {
        throw new Error("Invalid Paystack verification response")
      }
      return {
        id: data.id, reference: data.reference, status: data.status,
        amount: data.amount, currency: data.currency,
        paid_at: typeof data.paid_at === "string" ? data.paid_at : null,
        metadata: typeof data.metadata === "object" && data.metadata !== null ? data.metadata as Record<string, unknown> : null,
        authorization: typeof data.authorization === "object" && data.authorization !== null
          ? data.authorization as Record<string, unknown> : undefined,
        customer: typeof data.customer === "object" && data.customer !== null
          ? data.customer as Record<string, unknown> : undefined,
      }
    } catch (error) {
      console.error(`Paystack verification unavailable ref=${reference}`, error)
      return null
    }
  }
}
