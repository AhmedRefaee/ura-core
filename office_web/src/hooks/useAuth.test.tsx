import { describe, it, expect, vi } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { useAuth, signIn } from './useAuth';

const mockSession = { user: { id: 'u1' } };

vi.mock('../lib/supabase', () => ({
  supabase: {
    auth: {
      getSession: vi.fn().mockResolvedValue({ data: { session: { user: { id: 'u1' } } } }),
      onAuthStateChange: vi.fn().mockReturnValue({ data: { subscription: { unsubscribe: vi.fn() } } }),
      signInWithPassword: vi.fn(),
    },
  },
}));

describe('useAuth', () => {
  it('resolves the current session on mount', async () => {
    const { result } = renderHook(() => useAuth());
    expect(result.current.loading).toBe(true);
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.session).toEqual(mockSession);
  });
});

describe('signIn', () => {
  it('returns no error on success', async () => {
    const { supabase } = await import('../lib/supabase');
    vi.mocked(supabase.auth.signInWithPassword).mockResolvedValue({ data: {}, error: null } as never);
    const result = await signIn('a@b.com', 'pw');
    expect(result.error).toBeNull();
  });

  it('returns the Supabase error message on failure', async () => {
    const { supabase } = await import('../lib/supabase');
    vi.mocked(supabase.auth.signInWithPassword).mockResolvedValue({
      data: {}, error: { message: 'Invalid login credentials' },
    } as never);
    const result = await signIn('a@b.com', 'wrong');
    expect(result.error).toBe('Invalid login credentials');
  });

  it('returns error message when signInWithPassword rejects (network error)', async () => {
    const { supabase } = await import('../lib/supabase');
    vi.mocked(supabase.auth.signInWithPassword).mockRejectedValue(new Error('Network timeout'));
    const result = await signIn('a@b.com', 'pw');
    expect(result.error).toBe('Network timeout');
  });

  it('returns generic fallback when rejection is not an Error object', async () => {
    const { supabase } = await import('../lib/supabase');
    vi.mocked(supabase.auth.signInWithPassword).mockRejectedValue('Unknown rejection');
    const result = await signIn('a@b.com', 'pw');
    expect(result.error).toBe('An unexpected error occurred');
  });
});
