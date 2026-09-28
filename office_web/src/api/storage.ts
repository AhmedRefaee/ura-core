import { supabase } from '../lib/supabase';

const LIFETIME_SECONDS = 3600;

export function pathOf(bucket: string, stored: string): string {
  if (!stored.startsWith('http')) return stored;
  const marker = `/${bucket}/`;
  const i = stored.indexOf(marker);
  if (i < 0) return stored;
  return decodeURIComponent(stored.slice(i + marker.length).split('?')[0]);
}

export async function resolveSignedUrl(bucket: string, stored: string | null): Promise<string | null> {
  if (!stored) return null;
  const path = pathOf(bucket, stored);
  const { data, error } = await supabase.storage.from(bucket).createSignedUrl(path, LIFETIME_SECONDS);
  if (error || !data) return null;
  return data.signedUrl;
}
