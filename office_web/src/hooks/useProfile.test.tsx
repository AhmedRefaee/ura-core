import { describe, it, expect, vi } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useProfile } from './useProfile';

vi.mock('./useAuth', () => ({
  useAuth: () => ({ session: { user: { id: 'u1' } }, loading: false }),
}));

vi.mock('../lib/supabase', () => {
  const single = vi.fn().mockResolvedValue({
    data: { id: 'u1', full_name: 'مشرف', phone: null, role: 'verifier', is_approved: true },
    error: null,
  });
  const eq = vi.fn().mockReturnValue({ single });
  const select = vi.fn().mockReturnValue({ eq });
  const from = vi.fn().mockReturnValue({ select });
  return { supabase: { from } };
});

function wrapper({ children }: { children: React.ReactNode }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

describe('useProfile', () => {
  it('fetches the profile row for the logged-in user', async () => {
    const { result } = renderHook(() => useProfile(), { wrapper });
    await waitFor(() => expect(result.current.isLoading).toBe(false));
    expect(result.current.data?.role).toBe('verifier');
  });
});
