import { supabase } from '../config/supabase';

export async function trackContentAccess(
  eventType: string,
  itemCount: number,
  userId?: string,
): Promise<void> {
  if (!supabase) {
    return;
  }

  try {
    await supabase.from('activity').insert({
      user_id: userId ?? null,
      activity_type: eventType,
      metadata: { item_count: itemCount },
      created_at: new Date().toISOString(),
    });
  } catch (error) {
    console.warn('Failed to track content access:', error);
  }
}
