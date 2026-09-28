import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { AuditTimeline } from './AuditTimeline';
import type { AuditLogEntry } from '../types/domain';

function entry(overrides: Partial<AuditLogEntry>): AuditLogEntry {
  return {
    id: 'a1', orderId: 'o1', action: 'order_created', oldStatus: null, newStatus: 'assigned',
    performer: null, notes: null, serverTimestamp: '2026-09-28T10:00:00Z',
    ...overrides,
  };
}

describe('AuditTimeline', () => {
  it('shows the error message and nothing else when loading the log failed', () => {
    render(<AuditTimeline auditLog={[]} orderStatus="assigned" error />);
    expect(screen.getByText('تعذر تحميل السجل الزمني')).toBeInTheDocument();
  });

  it('shows the empty message when there is no history yet', () => {
    render(<AuditTimeline auditLog={[]} orderStatus="assigned" error={false} />);
    expect(screen.getByText('لا يوجد سجل بعد')).toBeInTheDocument();
  });

  it('labels order_created distinctly and other entries by their newStatus', () => {
    const entries = [
      entry({ id: 'a1', action: 'order_created', newStatus: 'assigned', serverTimestamp: '2026-09-28T10:00:00Z' }),
      entry({ id: 'a2', action: 'mark_picked_up', newStatus: 'picked_up', serverTimestamp: '2026-09-28T10:00:12Z' }),
    ];
    render(<AuditTimeline auditLog={entries} orderStatus="picked_up" error={false} />);
    expect(screen.getByText('تم إنشاء الطلب')).toBeInTheDocument();
    expect(screen.getByText('تم الاستلام')).toBeInTheDocument();
    expect(screen.queryByText('mark_picked_up')).not.toBeInTheDocument();
  });

  it('shows a duration badge between consecutive entries but not after the last one', () => {
    const entries = [
      entry({ id: 'a1', serverTimestamp: '2026-09-28T10:00:00Z' }),
      entry({ id: 'a2', action: 'mark_picked_up', newStatus: 'picked_up', serverTimestamp: '2026-09-28T10:00:12Z' }),
      entry({ id: 'a3', action: 'start_move', newStatus: 'on_the_move', serverTimestamp: '2026-09-28T10:01:00Z' }),
    ];
    render(<AuditTimeline auditLog={entries} orderStatus="on_the_move" error={false} />);
    // Gap between a1 and a2 is 12 seconds; distinct from the 60s total.
    expect(screen.getByText('12 ثانية')).toBeInTheDocument();
  });

  it('shows the actor role and name when a performer is present', () => {
    const entries = [
      entry({
        performer: { id: 'u1', fullName: 'أحمد رفاعي', phone: null, role: 'rep', isApproved: true },
      }),
    ];
    render(<AuditTimeline auditLog={entries} orderStatus="assigned" error={false} />);
    expect(screen.getByText('مندوب · أحمد رفاعي')).toBeInTheDocument();
  });

  it('does not crash and shows no actor line when performer is null', () => {
    const entries = [entry({ performer: null })];
    render(<AuditTimeline auditLog={entries} orderStatus="assigned" error={false} />);
    expect(screen.getByText('تم إنشاء الطلب')).toBeInTheDocument();
  });

  it('shows a total-elapsed banner spanning creation to the last entry when there are 2+ entries', () => {
    const entries = [
      entry({ id: 'a1', serverTimestamp: '2026-09-28T10:00:00Z' }),
      entry({ id: 'a2', action: 'mark_picked_up', newStatus: 'picked_up', serverTimestamp: '2026-09-28T10:00:12Z' }),
      entry({
        id: 'a3', action: 'mark_delivered', newStatus: 'delivered', serverTimestamp: '2026-09-28T10:01:07Z',
      }),
    ];
    render(<AuditTimeline auditLog={entries} orderStatus="delivered" error={false} />);
    // Total (creation -> last entry) is 67s; distinct from any single step's gap.
    expect(screen.getByText('1 دقيقة 7 ثانية')).toBeInTheDocument();
    expect(screen.getByText(/المدة الإجمالية من الإنشاء إلى التسليم/)).toBeInTheDocument();
  });

  it('does not show a total-elapsed banner with only one entry', () => {
    render(<AuditTimeline auditLog={[entry({})]} orderStatus="assigned" error={false} />);
    expect(screen.queryByText(/المدة الإجمالية/)).not.toBeInTheDocument();
  });
});
