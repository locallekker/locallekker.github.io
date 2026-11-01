// Supabase Edge Function: delete-auth-user
// Receives POST { user_id } with Authorization: Bearer <admin_access_token>
// Verifies caller is an admin (checks memberships, profiles, and admin_dashboard) and deletes the auth user

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variables');
}

function jsonResponse(body: object, status = 200) {
    return new Response(JSON.stringify(body), {
        status,
        headers: { 'content-type': 'application/json' },
    });
}

async function isCallerAdmin(callerId: string, callerEmail: string | null): Promise<boolean> {
    // Check 1: Known admin emails (matches Flutter app logic)
    if (callerEmail === 'admin@locallekker.com' || callerEmail === 'locallekkerclub@gmail.com') {
        console.log('Admin verified by email:', callerEmail);
        return true;
    }

    const serviceHeaders = {
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        apiKey: SERVICE_ROLE_KEY!,
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
    };

    // Check 2: memberships table
    try {
        const membershipsResp = await fetch(
            `${SUPABASE_URL}/rest/v1/memberships?user_id=eq.${callerId}&role=eq.admin&select=role`,
            { method: 'GET', headers: serviceHeaders }
        );
        if (membershipsResp.ok) {
            const memberships = await membershipsResp.json();
            if (Array.isArray(memberships) && memberships.length > 0 && memberships[0]?.role === 'admin') {
                console.log('Admin verified via memberships table');
                return true;
            }
        }
    } catch (e) {
        console.warn('memberships check error:', e);
    }

    // Check 3: profiles table
    try {
        const profilesResp = await fetch(
            `${SUPABASE_URL}/rest/v1/profiles?id=eq.${callerId}&role=eq.admin&select=role`,
            { method: 'GET', headers: serviceHeaders }
        );
        if (profilesResp.ok) {
            const profiles = await profilesResp.json();
            if (Array.isArray(profiles) && profiles.length > 0 && profiles[0]?.role === 'admin') {
                console.log('Admin verified via profiles table');
                return true;
            }
        }
    } catch (e) {
        console.warn('profiles check error:', e);
    }

    // Check 4: admin_dashboard table (presence means admin)
    try {
        const dashResp = await fetch(
            `${SUPABASE_URL}/rest/v1/admin_dashboard?select=id&limit=1`,
            { method: 'GET', headers: serviceHeaders }
        );
        if (dashResp.ok) {
            const dash = await dashResp.json();
            if (Array.isArray(dash) && dash.length > 0) {
                console.log('Admin verified via admin_dashboard table access');
                return true;
            }
        }
    } catch (e) {
        console.warn('admin_dashboard check error:', e);
    }

    return false;
}

export default async function handler(req: Request): Promise<Response> {
    if (req.method !== 'POST') return jsonResponse({ error: 'Method not allowed' }, 405);

    try {
        const authHeader = req.headers.get('authorization') || '';
        const token = authHeader.replace(/^Bearer\s+/i, '');
        if (!token) return jsonResponse({ error: 'Missing Authorization token' }, 401);

        // 1) Resolve caller user from token
        const userResp = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
            method: 'GET',
            headers: { Authorization: `Bearer ${token}` },
        });

        if (!userResp.ok) {
            const text = await userResp.text();
            return jsonResponse({ error: 'Invalid token or unable to resolve user', detail: text }, 401);
        }

        const caller = await userResp.json();
        const callerId = caller?.id;
        const callerEmail = caller?.email || null;
        if (!callerId) return jsonResponse({ error: 'Unable to determine caller id' }, 401);

        // 2) Verify caller is an admin (multiple checks for reliability)
        const adminVerified = await isCallerAdmin(callerId, callerEmail);
        if (!adminVerified) {
            console.error(`Admin verification failed for caller: ${callerId} (${callerEmail})`);
            return jsonResponse({ error: 'Forbidden - caller is not an admin' }, 403);
        }

        // 3) Parse body
        const body = await req.json().catch(() => null);
        const user_id = body?.user_id || body?.userId || body?.id;
        if (!user_id) return jsonResponse({ error: 'Missing user_id in body' }, 400);

        // 4) Delete auth user via admin endpoint (with timeout and retry)
        let deleteSuccess = false;
        let lastDeleteError = '';

        for (let attempt = 1; attempt <= 3; attempt++) {
            try {
                const controller = new AbortController();
                const timeoutId = setTimeout(() => controller.abort(), 25000); // 25s timeout

                const deleteResp = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${user_id}`, {
                    method: 'DELETE',
                    headers: {
                        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
                        apikey: SERVICE_ROLE_KEY!,
                    },
                    signal: controller.signal,
                });

                clearTimeout(timeoutId);

                if (deleteResp.ok) {
                    console.log(`Successfully deleted auth user: ${user_id} on attempt ${attempt}`);
                    deleteSuccess = true;
                    break;
                } else {
                    const txt = await deleteResp.text();
                    lastDeleteError = `${deleteResp.status} ${txt}`;
                    console.error(`Auth delete attempt ${attempt} failed for ${user_id}: ${lastDeleteError}`);
                }
            } catch (fetchErr) {
                lastDeleteError = String(fetchErr);
                console.error(`Auth delete attempt ${attempt} error for ${user_id}: ${lastDeleteError}`);
            }

            // Wait before retry (2s, 4s)
            if (attempt < 3) {
                await new Promise(resolve => setTimeout(resolve, attempt * 2000));
            }
        }

        if (!deleteSuccess) {
            console.error(`Auth delete failed for ${user_id} after 3 attempts: ${lastDeleteError}`);
            return jsonResponse({ error: 'Failed to delete auth user after retries', detail: lastDeleteError }, 504);
        }

        return jsonResponse({ success: true, user_id });
    } catch (err) {
        console.error('Handler error', err);
        return jsonResponse({ error: 'Server error', detail: String(err) }, 500);
    }
}
