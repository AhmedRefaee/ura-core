import { describe, it, expect, vi } from 'vitest';
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { fetchOrderDetail, fetchAuditLog, fetchDeliveryReceipts, ORDER_DETAIL_SELECT } from './orderDetail';

// eslint-disable-next-line @typescript-eslint/no-unused-vars
function chain(resolvedValue: unknown) {
  const order = vi.fn().mockResolvedValue(resolvedValue);
  const eq = vi.fn().mockReturnValue({ order, single: vi.fn().mockResolvedValue(resolvedValue) });
  const select = vi.fn().mockReturnValue({ eq });
  return { select, eq, order };
}

describe('fetchOrderDetail', () => {
  it('queries orders by id with the detail select and maps the row', async () => {
    const single = vi.fn().mockResolvedValue({
      data: {
        id: 'o1', reference_code: null, direction: 'outbound', entity_id: 'e1', entity: null,
        rep_id: null, rep: null, creator: null, status: 'assigned', notes: null,
        storage_actor_id: null, created_at: null, assigned_at: null, picked_up_at: null,
        move_started_at: null, delivered_at: null, order_items: [],
      },
      error: null,
    });
    const eq = vi.fn().mockReturnValue({ single });
    const select = vi.fn().mockReturnValue({ eq });
    const from = vi.fn().mockReturnValue({ select });
    vi.doMock('../lib/supabase', () => ({ supabase: { from } }));
    vi.resetModules();
    const mod = await import('./orderDetail');

    const order = await mod.fetchOrderDetail('o1');
    expect(from).toHaveBeenCalledWith('orders');
    expect(select).toHaveBeenCalledWith(mod.ORDER_DETAIL_SELECT);
    expect(eq).toHaveBeenCalledWith('id', 'o1');
    expect(order.id).toBe('o1');
  });
});

describe('fetchAuditLog', () => {
  it('queries audit_log for the order, oldest first', async () => {
    const order = vi.fn().mockResolvedValue({
      data: [{ id: 'a1', order_id: 'o1', action: 'order_created', old_status: null, new_status: 'assigned', performer: null, notes: null, server_timestamp: '2026-09-28T10:00:00Z' }],
      error: null,
    });
    const eq = vi.fn().mockReturnValue({ order });
    const select = vi.fn().mockReturnValue({ eq });
    const from = vi.fn().mockReturnValue({ select });
    vi.doMock('../lib/supabase', () => ({ supabase: { from } }));
    vi.resetModules();
    const mod = await import('./orderDetail');

    const entries = await mod.fetchAuditLog('o1');
    expect(from).toHaveBeenCalledWith('audit_log');
    expect(eq).toHaveBeenCalledWith('order_id', 'o1');
    expect(order).toHaveBeenCalledWith('server_timestamp', { ascending: true });
    expect(entries).toHaveLength(1);
  });
});

describe('fetchDeliveryReceipts', () => {
  it('queries delivery_receipts for the order, newest first', async () => {
    const order = vi.fn().mockResolvedValue({ data: [], error: null });
    const eq = vi.fn().mockReturnValue({ order });
    const select = vi.fn().mockReturnValue({ eq });
    const from = vi.fn().mockReturnValue({ select });
    vi.doMock('../lib/supabase', () => ({ supabase: { from } }));
    vi.resetModules();
    const mod = await import('./orderDetail');

    const receipts = await mod.fetchDeliveryReceipts('o1');
    expect(from).toHaveBeenCalledWith('delivery_receipts');
    expect(eq).toHaveBeenCalledWith('order_id', 'o1');
    expect(order).toHaveBeenCalledWith('created_at', { ascending: false });
    expect(receipts).toEqual([]);
  });
});
