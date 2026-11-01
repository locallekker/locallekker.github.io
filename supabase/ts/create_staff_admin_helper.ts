import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY!; // use service role key in secure environment

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

export async function createStaffAdmin(payload: { email: string; name?: string; role?: string }) {
    const res = await supabase.rpc('create_staff_admin', {}); // older SDKs take named params; adjust if needed

    // If your RPC expects payload named `payload`, call:
    // const res = await supabase.rpc('create_staff_admin', { payload });

    if (res.error) {
        throw res.error;
    }
    return res.data;
}

// Example usage from an admin-only script
(async () => {
    try {
        const result = await createStaffAdmin({ email: 'alice@example.com', name: 'Alice' });
        console.log('createStaffAdmin result:', result);
    } catch (e) {
        console.error('createStaffAdmin failed:', e);
    }
})();
