import { type SupabaseClient } from '@supabase/supabase-js';
export declare const supabase: SupabaseClient | null;
export declare function requireSupabase(): SupabaseClient;
export declare function getUserProfile(userId: string): Promise<any>;
//# sourceMappingURL=supabase.d.ts.map