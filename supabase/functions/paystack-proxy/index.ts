// Paystack API Proxy - Routes all secret-key Paystack calls through server-side
// The PAYSTACK_SECRET_KEY never leaves this Edge Function.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Whitelist of allowed Paystack API path prefixes.
// Any request whose path does NOT start with one of these is rejected.
const ALLOWED_PATH_PREFIXES = [
    '/transaction/initialize',
    '/transaction/verify/',
    '/transaction/charge_authorization',
    // List Transactions (read-only GET, e.g. /transaction?email=...&status=success)
    // used by pending-payment recovery to find a member's successful payment
    // when no local transaction reference was saved.
    '/transaction?',
    '/plan',
    '/subscription',
    '/customer',
    '/transferrecipient',
    '/charge',
    '/subaccount',
    '/bank/resolve',
]

// Special diagnostic path (does NOT call Paystack, just checks config)
const HEALTH_CHECK_PATH = '/__health'

function isAllowedPath(path: string): boolean {
    return ALLOWED_PATH_PREFIXES.some(prefix => path.startsWith(prefix))
}

/**
 * Verify a Supabase JWT locally using the HS256 SUPABASE_JWT_SECRET.
 * This avoids a network round-trip to the Auth server, cutting ~300–800 ms
 * of cold-start latency on every request.
 * Returns the decoded payload (with `sub` as userId) or null on failure.
 */
async function verifyJwtRemote(
    authHeader: string,
): Promise<{ sub: string } | { error: string }> {
    try {
        const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
        const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
        if (!supabaseUrl || !anonKey) {
            return { error: 'supabase_env_not_configured' }
        }
        const resp = await fetch(`${supabaseUrl}/auth/v1/user`, {
            method: 'GET',
            headers: {
                'Authorization': authHeader,
                'apikey': anonKey,
            },
        })
        if (resp.status !== 200) {
            const body = await resp.text()
            return { error: `auth_api_${resp.status}: ${body.substring(0, 120)}` }
        }
        const user = await resp.json()
        if (!user?.id) return { error: 'auth_api_missing_id' }
        return { sub: user.id as string }
    } catch (e) {
        return { error: `verify_remote_exception: ${(e as Error).message}` }
    }
}

async function verifyJwtLocally(
    authHeader: string,
    jwtSecret: string,
): Promise<{ sub: string } | { error: string }> {
    try {
        if (!jwtSecret) return { error: 'jwt_secret_not_configured' }

        const token = authHeader.replace(/^Bearer\s+/i, '')
        const parts = token.split('.')
        if (parts.length !== 3) return { error: 'malformed_token' }

        const [headerB64, payloadB64, signatureB64] = parts

        // base64url → base64 with correct padding (JWT segments are unpadded)
        const toBase64 = (b64url: string) => {
            const s = b64url.replace(/-/g, '+').replace(/_/g, '/')
            return s.padEnd(s.length + (4 - s.length % 4) % 4, '=')
        }

        // Decode payload to check expiry before doing expensive crypto
        const payloadJson = atob(toBase64(payloadB64))
        const payload = JSON.parse(payloadJson)
        const now = Math.floor(Date.now() / 1000)
        if (payload.exp && payload.exp < now) {
            return { error: `token_expired_${now - payload.exp}s_ago` }
        }
        if (!payload.sub) return { error: 'token_missing_sub' }

        // Verify HS256 signature
        const keyData = new TextEncoder().encode(jwtSecret)
        const cryptoKey = await crypto.subtle.importKey(
            'raw', keyData, { name: 'HMAC', hash: 'SHA-256' }, false, ['verify'],
        )
        const signingInput = new TextEncoder().encode(`${headerB64}.${payloadB64}`)
        const sigDecoded = atob(toBase64(signatureB64))
        const signatureBytes = Uint8Array.from(sigDecoded, c => c.charCodeAt(0))
        const valid = await crypto.subtle.verify('HMAC', cryptoKey, signatureBytes, signingInput)
        if (!valid) return { error: 'signature_mismatch' }

        return payload as { sub: string }
    } catch (e) {
        return { error: `verify_exception: ${(e as Error).message}` }
    }
}

serve(async (req) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const requestId = crypto.randomUUID()
        // ── Auth ──────────────────────────────────────────────
        const authHeader = req.headers.get('Authorization')
        if (!authHeader) {
            return new Response(
                JSON.stringify({
                    error_code: 'auth_error',
                    error: 'Missing authorization header',
                    request_id: requestId,
                }),
                {
                    status: 401,
                    headers: {
                        ...corsHeaders,
                        'Content-Type': 'application/json',
                        'x-proxy-request-id': requestId,
                    },
                },
            )
        }

        const paystackSecretKeyRaw = Deno.env.get('PAYSTACK_SECRET_KEY') ?? ''
        const paystackSecretKey = paystackSecretKeyRaw.trim()

        if (!paystackSecretKey) {
            console.error(`[${requestId}] PAYSTACK_SECRET_KEY is not configured`)
            return new Response(
                JSON.stringify({ error: 'Payment service not configured' }),
                {
                    status: 500,
                    headers: {
                        ...corsHeaders,
                        'Content-Type': 'application/json',
                        'x-proxy-request-id': requestId,
                    },
                },
            )
        }

        // Verify JWT locally (no network call — uses SUPABASE_JWT_SECRET).
        // If the secret isn't configured (or local verification fails for a
        // non-expiry reason), fall back to the Supabase Auth API so the
        // proxy still works without requiring the JWT secret env var.
        // Supabase CLI blocks the SUPABASE_ prefix for user-set secrets, so
        // we read the JWT secret from APP_JWT_SECRET (preferred) and fall
        // back to SUPABASE_JWT_SECRET in case it was set via the dashboard.
        const jwtSecret = (
            Deno.env.get('APP_JWT_SECRET')
            ?? Deno.env.get('SUPABASE_JWT_SECRET')
            ?? ''
        ).trim()
        let verifyResult = await verifyJwtLocally(authHeader, jwtSecret)
        if ('error' in verifyResult) {
            const localErr = verifyResult.error
            const isExpiry = localErr.startsWith('token_expired')
            if (!isExpiry) {
                console.warn(`Local JWT verify failed (${localErr}), falling back to remote auth check`)
                const remote = await verifyJwtRemote(authHeader)
                if ('error' in remote) {
                    console.error(`[${requestId}] JWT verify failed: local=${localErr} remote=${remote.error} (jwt_secret_len=${jwtSecret.length})`)
                    return new Response(
                        JSON.stringify({
                            error_code: 'auth_error',
                            error: 'Invalid or expired token',
                            detail: remote.error,
                            request_id: requestId,
                        }),
                        {
                            status: 401,
                            headers: {
                                ...corsHeaders,
                                'Content-Type': 'application/json',
                                'x-proxy-request-id': requestId,
                            },
                        },
                    )
                }
                verifyResult = remote
            } else {
                console.error(`[${requestId}] JWT verify failed: ${localErr} (jwt_secret_len=${jwtSecret.length})`)
                return new Response(
                    JSON.stringify({
                        error_code: 'auth_error',
                        error: 'Invalid or expired token',
                        detail: localErr,
                        request_id: requestId,
                    }),
                    {
                        status: 401,
                        headers: {
                            ...corsHeaders,
                            'Content-Type': 'application/json',
                            'x-proxy-request-id': requestId,
                        },
                    },
                )
            }
        }
        const userId = verifyResult.sub

        // ── Parse request ─────────────────────────────────────
        const { path, method, body } = await req.json()

        if (!path || typeof path !== 'string') {
            return new Response(
                JSON.stringify({ error: 'Missing "path" in request body' }),
                {
                    status: 400,
                    headers: {
                        ...corsHeaders,
                        'Content-Type': 'application/json',
                        'x-proxy-request-id': requestId,
                    },
                },
            )
        }

        // ── Health check (diagnose key configuration) ─────────
        if (path === HEALTH_CHECK_PATH) {
            const keyLength = paystackSecretKey.length
            const keyPrefix = paystackSecretKey.substring(0, 8) // e.g. sk_live_ or sk_test_
            const isLiveKey = paystackSecretKey.startsWith('sk_live_')
            const isTestKey = paystackSecretKey.startsWith('sk_test_')
            const keyLooksValid = (isLiveKey || isTestKey) && keyLength > 20

            // Optionally do a quick Paystack balance check to validate the key
            let paystackReachable = false
            let paystackKeyValid = false
            let paystackError = ''
            try {
                const testResp = await fetch('https://api.paystack.co/balance', {
                    method: 'GET',
                    headers: {
                        'Authorization': `Bearer ${paystackSecretKey}`,
                        'Content-Type': 'application/json',
                    },
                })
                paystackReachable = true
                paystackKeyValid = testResp.status === 200
                if (!paystackKeyValid) {
                    const errBody = await testResp.text()
                    paystackError = `HTTP ${testResp.status}: ${errBody.substring(0, 200)}`
                }
            } catch (e) {
                paystackError = `Network error: ${e.message}`
            }

            console.log(`Health check: keyPrefix=${keyPrefix} keyLength=${keyLength} valid=${paystackKeyValid}`)

            return new Response(
                JSON.stringify({
                    status: 'ok',
                    proxy_version: '2.0',
                    key_configured: keyLength > 0,
                    key_length: keyLength,
                    key_prefix: keyPrefix,
                    key_is_live: isLiveKey,
                    key_is_test: isTestKey,
                    key_looks_valid: keyLooksValid,
                    paystack_reachable: paystackReachable,
                    paystack_key_accepted: paystackKeyValid,
                    paystack_error: paystackError || undefined,
                    user_id: userId,
                    timestamp: new Date().toISOString(),
                }),
                {
                    status: 200,
                    headers: {
                        ...corsHeaders,
                        'Content-Type': 'application/json',
                        'x-proxy-request-id': requestId,
                    },
                },
            )
        }

        // ── Validate path ─────────────────────────────────────
        if (!isAllowedPath(path)) {
            console.error(`[${requestId}] BLOCKED: user=${userId} path=${path}`)
            return new Response(
                JSON.stringify({ error: 'Path not allowed' }),
                {
                    status: 403,
                    headers: {
                        ...corsHeaders,
                        'Content-Type': 'application/json',
                        'x-proxy-request-id': requestId,
                    },
                },
            )
        }

        const httpMethod = (method || 'GET').toUpperCase()
        const paystackUrl = `https://api.paystack.co${path}`

        // Log key diagnostics on every request for debugging
        console.log(`[${requestId}] proxy ${httpMethod} ${path} user=${userId} keyLen=${paystackSecretKey.length} keyPrefix=${paystackSecretKey.substring(0, 8)}`)

        // ── Forward to Paystack ───────────────────────────────
        const fetchOptions: RequestInit = {
            method: httpMethod,
            headers: {
                'Authorization': `Bearer ${paystackSecretKey}`,
                'Content-Type': 'application/json',
            },
        }

        // Attach body for POST / PUT (not GET / DELETE)
        if (body && httpMethod !== 'GET' && httpMethod !== 'DELETE') {
            fetchOptions.body = JSON.stringify(body)
        }

        const paystackResponse = await fetch(paystackUrl, fetchOptions)
        const responseText = await paystackResponse.text()

        // Return Paystack's response as-is (status code + body)
        return new Response(responseText, {
            status: paystackResponse.status,
            headers: {
                ...corsHeaders,
                'Content-Type': 'application/json',
                'x-proxy-request-id': requestId,
            },
        })

    } catch (error) {
        const requestId = crypto.randomUUID()
        console.error(`[${requestId}] Paystack proxy error:`, error)
        return new Response(
            JSON.stringify({
                error: error.message || 'Internal proxy error',
                request_id: requestId,
            }),
            {
                status: 500,
                headers: {
                    ...corsHeaders,
                    'Content-Type': 'application/json',
                    'x-proxy-request-id': requestId,
                },
            },
        )
    }
})
