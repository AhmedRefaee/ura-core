import { describe, it, expect, vi, beforeEach } from 'vitest';

describe('supabase client', () => {
  beforeEach(() => {
    vi.stubEnv('VITE_SUPABASE_URL', 'https://musaqyislgvshurfrjwx.supabase.co');
    vi.stubEnv(
      'VITE_SUPABASE_ANON_KEY',
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im11c2FxeWlzbGd2c2h1cmZyand4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNDcwODgsImV4cCI6MjA5MDYyMzA4OH0.gR2k3UkW70GuBIZ69qz6WXvlFT1EMOpYlJCOtwBLF_M',
    );
  });

  it('creates a client pointed at the configured URL', async () => {
    vi.resetModules();
    const { supabase } = await import('./supabase');
    expect(supabase.supabaseUrl).toBe('https://musaqyislgvshurfrjwx.supabase.co');
  });
});
