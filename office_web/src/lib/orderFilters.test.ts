import { describe, it, expect } from 'vitest';
import { filterOrdersByQuery, filterOrdersByDirection, sortOrders, groupOrders } from './orderFilters';
import type { Order } from '../types/domain';

function order(overrides: Partial<Order>): Order {
  return {
    id: 'o1', referenceCode: null, direction: 'outbound', entityId: 'e1', entity: null,
    repId: null, rep: null, creator: null, status: 'assigned', notes: null,
    storageActorId: null, createdAt: '2026-09-28T10:00:00Z', assignedAt: null,
    pickedUpAt: null, moveStartedAt: null, deliveredAt: null, items: [],
    ...overrides,
  };
}

describe('filterOrdersByQuery', () => {
  it('matches by entity name, rep name, or reference code, case-insensitively', () => {
    const orders = [
      order({ id: 'a', entity: { id: 'e1', name: 'Ministry of Health', category: 'outgoing', contactName: null, contactPhone: null, address: null } }),
      order({ id: 'b', rep: { id: 'u1', fullName: 'Ahmed Refaee', phone: null, role: 'rep', isApproved: true } }),
      order({ id: 'c', referenceCode: 'RN-9821' }),
      order({ id: 'd' }),
    ];
    expect(filterOrdersByQuery(orders, 'ministry').map((o) => o.id)).toEqual(['a']);
    expect(filterOrdersByQuery(orders, 'AHMED').map((o) => o.id)).toEqual(['b']);
    expect(filterOrdersByQuery(orders, 'rn-9821').map((o) => o.id)).toEqual(['c']);
  });

  it('returns everything unchanged for an empty query', () => {
    const orders = [order({ id: 'a' }), order({ id: 'b' })];
    expect(filterOrdersByQuery(orders, '  ')).toHaveLength(2);
  });
});

describe('filterOrdersByDirection', () => {
  it('filters by direction, or returns everything for "all"', () => {
    const orders = [order({ id: 'a', direction: 'outbound' }), order({ id: 'b', direction: 'inbound_rep' })];
    expect(filterOrdersByDirection(orders, 'outbound').map((o) => o.id)).toEqual(['a']);
    expect(filterOrdersByDirection(orders, 'all')).toHaveLength(2);
  });
});

describe('sortOrders', () => {
  it('sorts most_recent first by createdAt descending', () => {
    const orders = [
      order({ id: 'old', createdAt: '2026-01-01T00:00:00Z' }),
      order({ id: 'new', createdAt: '2026-09-01T00:00:00Z' }),
    ];
    expect(sortOrders(orders, 'most_recent').map((o) => o.id)).toEqual(['new', 'old']);
    expect(sortOrders(orders, 'oldest').map((o) => o.id)).toEqual(['old', 'new']);
  });

  it('sorts frequent by how many orders share the same entity, ties broken by recency', () => {
    const orders = [
      order({ id: 'a', entityId: 'e1', createdAt: '2026-01-01T00:00:00Z' }),
      order({ id: 'b', entityId: 'e1', createdAt: '2026-02-01T00:00:00Z' }),
      order({ id: 'c', entityId: 'e2', createdAt: '2026-03-01T00:00:00Z' }),
    ];
    expect(sortOrders(orders, 'frequent').map((o) => o.id)).toEqual(['b', 'a', 'c']);
  });
});

describe('groupOrders', () => {
  it('groups by entity, each group internally sorted', () => {
    const orders = [
      order({ id: 'a', entityId: 'e1', entity: { id: 'e1', name: 'وزارة', category: 'outgoing', contactName: null, contactPhone: null, address: null }, createdAt: '2026-01-01T00:00:00Z' }),
      order({ id: 'b', entityId: 'e1', entity: { id: 'e1', name: 'وزارة', category: 'outgoing', contactName: null, contactPhone: null, address: null }, createdAt: '2026-02-01T00:00:00Z' }),
      order({ id: 'c', entityId: 'e2', entity: { id: 'e2', name: 'بلدية', category: 'outgoing', contactName: null, contactPhone: null, address: null }, createdAt: '2026-03-01T00:00:00Z' }),
    ];
    const groups = groupOrders(orders, 'entity', 'most_recent');
    expect(groups.map((g) => g.label)).toEqual(['بلدية', 'وزارة']);
    expect(groups.find((g) => g.label === 'وزارة')?.orders.map((o) => o.id)).toEqual(['b', 'a']);
  });

  it('labels a missing rep as بدون مندوب', () => {
    const orders = [order({ id: 'a', repId: null, rep: null })];
    const groups = groupOrders(orders, 'rep', 'most_recent');
    expect(groups[0].label).toBe('بدون مندوب');
  });
});
