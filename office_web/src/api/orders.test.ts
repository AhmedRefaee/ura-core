import { describe, it, expect, vi } from 'vitest';
import { fetchOrders, ORDER_SELECT } from './orders';

vi.mock('../lib/supabase', () => {
  const order = vi.fn().mockResolvedValue({
    data: [{
      id: 'o1', reference_code: null, direction: 'outbound', entity_id: 'e1', entity: null,
      rep_id: null, rep: null, creator: null, status: 'assigned', notes: null,
      storage_actor_id: null, created_at: '2026-09-28T10:00:00Z', assigned_at: null,
      picked_up_at: null, move_started_at: null, delivered_at: null, order_items: [],
    }],
    error: null,
  });
  const select = vi.fn().mockReturnValue({ order });
  const from = vi.fn().mockReturnValue({ select });
  return { supabase: { from } };
});

describe('fetchOrders', () => {
  it('queries the orders table with the full join select and maps rows', async () => {
    const { supabase } = await import('../lib/supabase');
    const orders = await fetchOrders();
    expect(supabase.from).toHaveBeenCalledWith('orders');
    expect(supabase.from('orders').select).toHaveBeenCalledWith(ORDER_SELECT);
    expect(orders).toHaveLength(1);
    expect(orders[0].id).toBe('o1');
  });
});

describe('fetchOrders error handling', () => {
  it('throws when Supabase returns an error', async () => {
    vi.resetModules();
    vi.doMock('../lib/supabase', () => {
      const order = vi.fn().mockResolvedValue({ data: null, error: { message: 'network down' } });
      const select = vi.fn().mockReturnValue({ order });
      const from = vi.fn().mockReturnValue({ select });
      return { supabase: { from } };
    });
    const { fetchOrders: fetchOrdersFresh } = await import('./orders');
    await expect(fetchOrdersFresh()).rejects.toThrow('network down');
  });
});
