import { describe, it, expect } from 'vitest';
import { mapProfile, mapEntity, mapOrderItem, mapOrder, mapAuditLogEntry, mapDeliveryReceipt } from './mappers';

describe('mapProfile', () => {
  it('maps a profile row', () => {
    const p = mapProfile({ id: 'u1', full_name: 'أحمد', phone: '0500000000', role: 'verifier', is_approved: true });
    expect(p).toEqual({ id: 'u1', fullName: 'أحمد', phone: '0500000000', role: 'verifier', isApproved: true });
  });

  it('returns null role for an unknown value', () => {
    const p = mapProfile({ id: 'u1', full_name: 'أحمد', phone: null, role: null, is_approved: false });
    expect(p.role).toBeNull();
  });
});

describe('mapEntity', () => {
  it('maps an entity row', () => {
    const e = mapEntity({ id: 'e1', name: 'وزارة الصحة', category: 'outgoing', contact_name: null, contact_phone: null, address: null });
    expect(e).toEqual({ id: 'e1', name: 'وزارة الصحة', category: 'outgoing', contactName: null, contactPhone: null, address: null });
  });
});

describe('mapOrderItem', () => {
  it('maps a non-custom item with its inventory join', () => {
    const item = mapOrderItem({
      id: 'i1',
      order_id: 'o1',
      inventory_id: 'inv1',
      quantity: 5,
      final_quantity: null,
      is_custom: false,
      custom_description: null,
      check_status: 'checked',
      checked_by: 'u2',
      was_unavailable_at_creation: false,
      inventory: { id: 'inv1', item_name: 'أكياس أرز' },
      checker: null,
    });
    expect(item.inventoryName).toBe('أكياس أرز');
    expect(item.checkStatus).toBe('checked');
  });

  it('defaults check_status to pending when null', () => {
    const item = mapOrderItem({
      id: 'i1', order_id: 'o1', inventory_id: null, quantity: 1, final_quantity: null,
      is_custom: true, custom_description: 'صنف خاص', check_status: null,
      checked_by: null, was_unavailable_at_creation: false, inventory: null, checker: null,
    });
    expect(item.checkStatus).toBe('pending');
  });
});

describe('mapOrder', () => {
  it('maps an order row with nested entity/rep/items', () => {
    const order = mapOrder({
      id: 'o1', reference_code: 'RN-1', direction: 'outbound', entity_id: 'e1',
      entity: { id: 'e1', name: 'وزارة', category: 'outgoing', contact_name: null, contact_phone: null, address: null },
      rep_id: 'u1', rep: { id: 'u1', full_name: 'مندوب', phone: null, role: 'rep', is_approved: true },
      creator: null, status: 'delivered', notes: null, storage_actor_id: null,
      created_at: '2026-09-28T10:00:00Z', assigned_at: null, picked_up_at: null, move_started_at: null,
      delivered_at: '2026-09-28T12:00:00Z',
      order_items: [{
        id: 'i1', order_id: 'o1', inventory_id: null, quantity: 2, final_quantity: null,
        is_custom: true, custom_description: 'صنف', check_status: 'pending', checked_by: null,
        was_unavailable_at_creation: false, inventory: null, checker: null,
      }],
    });
    expect(order.entity?.name).toBe('وزارة');
    expect(order.items).toHaveLength(1);
    expect(order.status).toBe('delivered');
  });

  it('defaults status to assigned for an unknown value and items to an empty array when absent', () => {
    const order = mapOrder({
      id: 'o1', reference_code: null, direction: 'outbound', entity_id: 'e1', entity: null,
      rep_id: null, rep: null, creator: null, status: 'unknown_status', notes: null,
      storage_actor_id: null, created_at: null, assigned_at: null, picked_up_at: null,
      move_started_at: null, delivered_at: null, order_items: null,
    });
    expect(order.status).toBe('assigned');
    expect(order.items).toEqual([]);
  });
});

describe('mapAuditLogEntry', () => {
  it('maps an audit log row', () => {
    const entry = mapAuditLogEntry({
      id: 'a1', order_id: 'o1', action: 'status_changed', old_status: 'assigned', new_status: 'picked_up',
      performer: { id: 'u1', full_name: 'مندوب', phone: null, role: 'rep', is_approved: true },
      notes: null, server_timestamp: '2026-09-28T10:05:00Z',
    });
    expect(entry.newStatus).toBe('picked_up');
    expect(entry.performer?.fullName).toBe('مندوب');
  });
});

describe('mapDeliveryReceipt', () => {
  it('maps a delivery receipt row with its items', () => {
    const receipt = mapDeliveryReceipt({
      id: 'r1', order_id: 'o1', rep: { id: 'u1', full_name: 'مندوب', phone: null, role: 'rep', is_approved: true },
      delivered_at: null, pdf_url: 'org/u1/1.pdf', notes: null, created_at: '2026-09-28T09:00:00Z',
      delivery_receipt_items: [{ id: 'di1', item_name_snapshot: 'كرسي', unit_snapshot: 'حبة', quantity_delivered: 3 }],
    });
    expect(receipt.pdfUrl).toBe('org/u1/1.pdf');
    expect(receipt.items[0].itemNameSnapshot).toBe('كرسي');
  });
});
