export function blocksLegacySubscriptionSubmission(path: string, method: string, body: unknown): boolean {
  if (method === "GET") return false
  const pathname = new URL(path, "https://api.paystack.co").pathname.replace(/\/+$/, "")
  if (pathname.startsWith("/subscription")) return pathname !== "/subscription/disable"
  if (pathname.startsWith("/plan")) return true
  if (!["/transaction/initialize", "/transaction/charge_authorization", "/charge"].includes(pathname)) return false
  if (typeof body !== "object" || body === null) return true
  if ("plan" in body && body.plan) return true
  if (!("metadata" in body) || typeof body.metadata !== "object" || body.metadata === null) return true
  if (!("payment_type" in body.metadata)) return true
  return !["one_time_payment", "payment_method_setup"].includes(String(body.metadata.payment_type))
}
