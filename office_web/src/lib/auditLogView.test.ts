import { describe, it, expect } from 'vitest';
import { effectiveStatus, prepareAuditLogForDisplay } from './auditLogView';
import type { AuditLogEntry } from '../types/domain';

function entry(overrides: Partial<AuditLogEntry>): AuditLogEntry {
  return {
    id: 'a1', orderId: 'o1', action: 'status_change', oldStatus: null, newStatus: null,
    performer: null, notes: null, serverTimestamp: '2026-09-28T10:00:00Z',
    ...overrides,
  };
}

// Real API response captured from the live app for order URA-1575-CN: every
// transition writes a generic status_change row AND a specific one
// (storage_pickup, start_move, mark_delivered), both at the exact same
// server_timestamp -- a real backend logging pattern, not a fetch bug.
const realOrderAuditLog: AuditLogEntry[] = [
  entry({ id: 'e1', action: 'order_created', oldStatus: null, newStatus: null, serverTimestamp: '2026-09-13T11:53:24.993203+00:00' }),
  entry({ id: 'e2', action: 'status_change', oldStatus: 'assigned', newStatus: 'picked_up', serverTimestamp: '2026-09-13T11:54:02.082056+00:00' }),
  entry({ id: 'e3', action: 'storage_pickup', oldStatus: 'assigned', newStatus: 'picked_up', serverTimestamp: '2026-09-13T11:54:02.082056+00:00' }),
  entry({ id: 'e4', action: 'status_change', oldStatus: 'picked_up', newStatus: 'on_the_move', serverTimestamp: '2026-09-13T11:54:16.565544+00:00' }),
  entry({ id: 'e5', action: 'start_move', oldStatus: 'picked_up', newStatus: 'on_the_move', serverTimestamp: '2026-09-13T11:54:16.565544+00:00' }),
  entry({ id: 'e6', action: 'status_change', oldStatus: 'on_the_move', newStatus: 'delivered', serverTimestamp: '2026-09-13T12:32:19.3652+00:00' }),
  entry({ id: 'e7', action: 'mark_delivered', oldStatus: 'on_the_move', newStatus: 'delivered', serverTimestamp: '2026-09-13T12:32:19.3652+00:00' }),
];

describe('effectiveStatus', () => {
  it('treats order_created as the assigned status, even though newStatus is null in the real data', () => {
    expect(effectiveStatus(entry({ action: 'order_created', newStatus: null }))).toBe('assigned');
  });

  it('returns newStatus as-is for every other action', () => {
    expect(effectiveStatus(entry({ action: 'status_change', newStatus: 'picked_up' }))).toBe('picked_up');
  });

  it('returns null for a non-status action with no newStatus (e.g. an item-level toggle)', () => {
    expect(effectiveStatus(entry({ action: 'toggle_off_stock_item_purchased', newStatus: null }))).toBeNull();
  });
});

describe('prepareAuditLogForDisplay', () => {
  it('collapses the real same-timestamp duplicate pairs down to one row per transition', () => {
    const result = prepareAuditLogForDisplay(realOrderAuditLog);
    // 7 raw rows -> 4 real transitions (created, picked_up, on_the_move, delivered).
    expect(result).toHaveLength(4);
    expect(result.map((e) => e.id)).toEqual(['e1', 'e2', 'e4', 'e6']);
  });

  it('drops non-status entries entirely (e.g. an item-level toggle action)', () => {
    const withNoise: AuditLogEntry[] = [
      ...realOrderAuditLog,
      entry({ id: 'noise', action: 'toggle_off_stock_item_purchased', oldStatus: null, newStatus: null, serverTimestamp: '2026-09-13T12:00:00Z' }),
    ];
    const result = prepareAuditLogForDisplay(withNoise);
    expect(result.find((e) => e.id === 'noise')).toBeUndefined();
    expect(result).toHaveLength(4);
  });

  it('keeps distinct entries whose timestamps genuinely differ, even with the same newStatus', () => {
    const entries = [
      entry({ id: 'a', newStatus: 'picked_up', serverTimestamp: '2026-09-28T10:00:00Z' }),
      entry({ id: 'b', newStatus: 'picked_up', serverTimestamp: '2026-09-28T10:05:00Z' }),
    ];
    expect(prepareAuditLogForDisplay(entries)).toHaveLength(2);
  });
});
