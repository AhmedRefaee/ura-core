import { describe, it, expect, vi, beforeEach } from 'vitest';

describe('supabase client', () => {
  beforeEach(() => {
    vi.stubEnv('VITE_SUPABASE_URL', 'https://musaqyislgvshurfrjwx.supabase.co');
    vi.stubEnv('VITE_SUPABASE_ANON_KEY', 'test-anon-key-not-real');
  });

  it('creates a client pointed at the configured URL', async () => {
    vi.resetModules();
    const { supabase } = await import('./supabase');
    expect(supabase.supabaseUrl).toBe('https://musaqyislgvshurfrjwx.supabase.co');
  });
});
