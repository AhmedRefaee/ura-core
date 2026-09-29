import { describe, it, expect } from 'vitest';
import { buildStepTimeline } from './stepTimeline';
import type { StatusStep } from './statusSteps';
import type { AuditLogEntry } from '../types/domain';

const steps: StatusStep[] = [
  { status: 'assigned', label: 'معين' },
  { status: 'picked_up', label: 'تم الاستلام' },
  { status: 'delivered', label: 'تم التسليم' },
];

function entry(overrides: Partial<AuditLogEntry>): AuditLogEntry {
  return {
    id: 'a1', orderId: 'o1', action: 'status_change', oldStatus: null, newStatus: 'assigned',
    performer: null, notes: null, serverTimestamp: '2026-09-28T10:00:00Z',
    ...overrides,
  };
}

describe('buildStepTimeline', () => {
  it('matches each step to the first audit log entry with the same newStatus', () => {
    const auditLog = [
      entry({ id: 'a1', newStatus: 'assigned', serverTimestamp: '2026-09-28T10:00:00Z' }),
      entry({ id: 'a2', newStatus: 'picked_up', serverTimestamp: '2026-09-28T10:00:12Z' }),
    ];
    const result = buildStepTimeline(steps, auditLog);
    expect(result[0].entry?.id).toBe('a1');
    expect(result[1].entry?.id).toBe('a2');
  });

  it('computes each entry\'s duration as the gap to the next chronological entry', () => {
    const auditLog = [
      entry({ id: 'a1', newStatus: 'assigned', serverTimestamp: '2026-09-28T10:00:00Z' }),
      entry({ id: 'a2', newStatus: 'picked_up', serverTimestamp: '2026-09-28T10:00:12Z' }),
    ];
    const result = buildStepTimeline(steps, auditLog);
    expect(result[0].duration).toBe('12 ثانية');
  });

  it('leaves duration null for the last audit log entry (nothing comes after it)', () => {
    const auditLog = [
      entry({ id: 'a1', newStatus: 'assigned', serverTimestamp: '2026-09-28T10:00:00Z' }),
    ];
    const result = buildStepTimeline(steps, auditLog);
    expect(result[0].duration).toBeNull();
  });

  it('leaves entry and duration null for a step with no matching audit log row', () => {
    const auditLog = [entry({ id: 'a1', newStatus: 'assigned' })];
    const result = buildStepTimeline(steps, auditLog);
    // 'delivered' step has no matching entry in this fixture.
    const deliveredResult = result.find((r) => r.status === 'delivered');
    expect(deliveredResult?.entry).toBeNull();
    expect(deliveredResult?.duration).toBeNull();
  });

  it('matches the assigned step to an order_created row even though its newStatus is null (real data)', () => {
    const auditLog = [entry({ id: 'a1', action: 'order_created', newStatus: null })];
    const result = buildStepTimeline(steps, auditLog);
    expect(result[0].entry?.id).toBe('a1');
  });
});
