import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Shell } from './Shell';

vi.mock('../hooks/useProfile', () => ({ useProfile: () => ({ data: { id: 'u1', fullName: 'أحمد', phone: null, role: 'verifier', isApproved: true } }) }));
vi.mock('../hooks/useAuth', () => ({ signOut: vi.fn().mockResolvedValue(undefined) }));

describe('Shell logout', () => {
  it('clears the query client cache on logout, so a second user never sees stale cached data', async () => {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    client.setQueryData(['orders'], [{ id: 'stale-order' }]);
    const clearSpy = vi.spyOn(client, 'clear');

    render(
      <QueryClientProvider client={client}>
        <MemoryRouter>
          <Shell searchValue="" onSearchChange={() => {}}>
            <p>محتوى</p>
          </Shell>
        </MemoryRouter>
      </QueryClientProvider>,
    );

    fireEvent.click(screen.getByRole('button', { name: 'تسجيل الخروج' }));

    await waitFor(() => expect(clearSpy).toHaveBeenCalled());
  });
});
