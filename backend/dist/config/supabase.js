import { createClient } from '@supabase/supabase-js';
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_KEY ?? process.env.SUPABASE_SERVICE_ROLE_KEY;
export const supabase = supabaseUrl && supabaseServiceKey
    ? createClient(supabaseUrl, supabaseServiceKey, {
        auth: {
            autoRefreshToken: false,
            persistSession: false,
        },
    })
    : null;
export function requireSupabase() {
    if (!supabase) {
        throw new Error('Supabase is not configured. Set SUPABASE_URL and SUPABASE_SERVICE_KEY.');
    }
    return supabase;
}
export async function getUserProfile(userId) {
    const client = requireSupabase();
    const { data, error } = await client
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .single();
    if (error) {
        throw error;
    }
    return data;
}
