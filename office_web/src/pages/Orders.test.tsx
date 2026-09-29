import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import Orders from './Orders';
import type { Order } from '../types/domain';

function order(overrides: Partial<Order>): Order {
  return {
    id: 'o1', referenceCode: 'RN-1', direction: 'outbound', entityId: 'e1',
    entity: { id: 'e1', name: 'وزارة الصحة', category: 'outgoing', contactName: null, contactPhone: null, address: null },
    repId: null, rep: null, creator: null, status: 'assigned', notes: null,
    storageActorId: null, createdAt: '2026-09-28T10:00:00Z', assignedAt: null,
    pickedUpAt: null, moveStartedAt: null, deliveredAt: null, items: [],
    ...overrides,
  };
}

const ordersMock = vi.fn();
vi.mock('../hooks/useOrders', () => ({ useOrders: () => ordersMock() }));
vi.mock('../hooks/useProfile', () => ({ useProfile: () => ({ data: { id: 'u1', fullName: 'مشرف', phone: null, role: 'verifier', isApproved: true } }) }));
vi.mock('../hooks/useAuth', () => ({ signOut: vi.fn() }));
vi.mock('../components/OrderDetailPanel', () => ({
  OrderDetailPanel: ({ orderId, onClose }: { orderId: string; onClose: () => void }) => (
    <div>
      <span>لوحة تفاصيل الطلب {orderId}</span>
      <button onClick={onClose}>إغلاق</button>
    </div>
  ),
}));

function renderOrders() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={['/orders']}>
        <Orders />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('Orders page', () => {
  it('shows the loading state while orders are fetching', () => {
    ordersMock.mockReturnValue({ data: undefined, isLoading: true, isError: false, refetch: vi.fn() });
    renderOrders();
    expect(screen.getByText('جارٍ التحميل...')).toBeInTheDocument();
  });

  it('shows the error state with a retry button on failure', () => {
    const refetch = vi.fn();
    ordersMock.mockReturnValue({ data: undefined, isLoading: false, isError: true, error: new Error('تعذر الاتصال'), refetch });
    renderOrders();
    fireEventClickRetry();
    expect(refetch).toHaveBeenCalled();

    function fireEventClickRetry() {
      screen.getByRole('button', { name: 'إعادة المحاولة' }).click();
    }
  });

  it('filters delivered orders out of the نشطة tab and lists undelivered ones', async () => {
    ordersMock.mockReturnValue({
      data: [order({ id: 'a', status: 'assigned' }), order({ id: 'b', status: 'delivered' })],
      isLoading: false, isError: false, refetch: vi.fn(),
    });
    renderOrders();
    await waitFor(() => expect(screen.getByText('وزارة الصحة')).toBeInTheDocument());
  });

  it('shows a labeled section with a count per group when a group mode is selected', async () => {
    ordersMock.mockReturnValue({
      data: [
        order({ id: 'a', entityId: 'e1', entity: { id: 'e1', name: 'وزارة الصحة', category: 'outgoing', contactName: null, contactPhone: null, address: null } }),
        order({ id: 'b', entityId: 'e1', entity: { id: 'e1', name: 'وزارة الصحة', category: 'outgoing', contactName: null, contactPhone: null, address: null } }),
        order({ id: 'c', entityId: 'e2', entity: { id: 'e2', name: 'وزارة التعليم', category: 'outgoing', contactName: null, contactPhone: null, address: null } }),
      ],
      isLoading: false, isError: false, refetch: vi.fn(),
    });
    renderOrders();
    fireEvent.change(screen.getByLabelText('التجميع'), { target: { value: 'entity' } });

    expect(await screen.findByText('وزارة الصحة — 2 طلبات')).toBeInTheDocument();
    expect(screen.getByText('وزارة التعليم — 1 طلبات')).toBeInTheDocument();
  });

  it('shows the detail panel beside the table when the URL has an order id', async () => {
    ordersMock.mockReturnValue({
      data: [order({ id: 'a' })], isLoading: false, isError: false, refetch: vi.fn(),
    });
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={client}>
        <MemoryRouter initialEntries={['/orders/a']}>
          <Routes>
            <Route path="/orders/:orderId?" element={<Orders />} />
          </Routes>
        </MemoryRouter>
      </QueryClientProvider>,
    );
    await waitFor(() => expect(screen.getByText('لوحة تفاصيل الطلب a')).toBeInTheDocument());
    expect(screen.getByText('وزارة الصحة')).toBeInTheDocument();
  });
});
