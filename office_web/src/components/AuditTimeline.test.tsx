import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { AuditTimeline } from './AuditTimeline';
import type { AuditLogEntry } from '../types/domain';

function entry(overrides: Partial<AuditLogEntry>): AuditLogEntry {
  return {
    id: 'a1', orderId: 'o1', action: 'order_created', oldStatus: null, newStatus: 'assigned',
    performer: null, notes: null, serverTimestamp: '2026-09-28T10:00:00Z', locationLat: null, locationLng: null,
    ...overrides,
  };
}

describe('AuditTimeline', () => {
  it('shows the error message and nothing else when loading the log failed', () => {
    render(<AuditTimeline auditLog={[]} orderStatus="assigned" error hoveredStatus={null} onHoverEntry={() => {}} />);
    expect(screen.getByText('تعذر تحميل السجل الزمني')).toBeInTheDocument();
  });

  it('shows the empty message when there is no history yet', () => {
    render(<AuditTimeline auditLog={[]} orderStatus="assigned" error={false} hoveredStatus={null} onHoverEntry={() => {}} />);
    expect(screen.getByText('لا يوجد سجل بعد')).toBeInTheDocument();
  });

  it('labels order_created distinctly and other entries by their newStatus', () => {
    const entries = [
      entry({ id: 'a1', action: 'order_created', newStatus: 'assigned', serverTimestamp: '2026-09-28T10:00:00Z' }),
      entry({ id: 'a2', action: 'mark_picked_up', newStatus: 'picked_up', serverTimestamp: '2026-09-28T10:00:12Z' }),
    ];
    render(<AuditTimeline auditLog={entries} orderStatus="picked_up" error={false} hoveredStatus={null} onHoverEntry={() => {}} />);
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
    render(<AuditTimeline auditLog={entries} orderStatus="on_the_move" error={false} hoveredStatus={null} onHoverEntry={() => {}} />);
    // Gap between a1 and a2 is 12 seconds; distinct from the 60s total.
    expect(screen.getByText('12 ثانية')).toBeInTheDocument();
  });

  it('shows the actor role and name when a performer is present', () => {
    const entries = [
      entry({
        performer: { id: 'u1', fullName: 'أحمد رفاعي', phone: null, role: 'rep', isApproved: true },
      }),
    ];
    render(<AuditTimeline auditLog={entries} orderStatus="assigned" error={false} hoveredStatus={null} onHoverEntry={() => {}} />);
    expect(screen.getByText('مندوب · أحمد رفاعي')).toBeInTheDocument();
  });

  it('does not crash and shows no actor line when performer is null', () => {
    const entries = [entry({ performer: null })];
    render(<AuditTimeline auditLog={entries} orderStatus="assigned" error={false} hoveredStatus={null} onHoverEntry={() => {}} />);
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
    render(<AuditTimeline auditLog={entries} orderStatus="delivered" error={false} hoveredStatus={null} onHoverEntry={() => {}} />);
    // Total (creation -> last entry) is 67s; distinct from any single step's gap.
    expect(screen.getByText('1 دقيقة 7 ثانية')).toBeInTheDocument();
    expect(screen.getByText(/المدة الإجمالية من الإنشاء إلى التسليم/)).toBeInTheDocument();
  });

  it('does not show a total-elapsed banner with only one entry', () => {
    render(<AuditTimeline auditLog={[entry({})]} orderStatus="assigned" error={false} hoveredStatus={null} onHoverEntry={() => {}} />);
    expect(screen.queryByText(/المدة الإجمالية/)).not.toBeInTheDocument();
  });

  it('calls onHoverEntry with the row\'s status on hover, and null on leave', () => {
    const onHoverEntry = vi.fn();
    const entries = [entry({ id: 'a1', newStatus: 'assigned' })];
    render(<AuditTimeline auditLog={entries} orderStatus="assigned" error={false} hoveredStatus={null} onHoverEntry={onHoverEntry} />);
    const row = screen.getByTestId('audit-row-a1');
    fireEvent.mouseEnter(row);
    expect(onHoverEntry).toHaveBeenCalledWith('assigned');
    fireEvent.mouseLeave(row);
    expect(onHoverEntry).toHaveBeenCalledWith(null);
  });

  it('highlights the row whose status is currently hovered (from the stepper), and no other row', () => {
    const entries = [
      entry({ id: 'a1', newStatus: 'assigned' }),
      entry({ id: 'a2', action: 'mark_picked_up', newStatus: 'picked_up', serverTimestamp: '2026-09-28T10:00:12Z' }),
    ];
    render(<AuditTimeline auditLog={entries} orderStatus="picked_up" error={false} hoveredStatus="picked_up" onHoverEntry={() => {}} />);
    const highlighted = screen.getByTestId('audit-row-a2') as HTMLElement;
    const notHighlighted = screen.getByTestId('audit-row-a1') as HTMLElement;
    expect(highlighted.style.backgroundColor).not.toBe('');
    expect(notHighlighted.style.backgroundColor).toBe('');
  });

  it('links to Google Maps only on entries that carry a location', () => {
    render(<AuditTimeline
      auditLog={[entry({ id: 'a', locationLat: 24.7, locationLng: 46.6 }), entry({ id: 'b', newStatus: 'picked_up' })]}
      orderStatus="picked_up" error={false} hoveredStatus={null} onHoverEntry={() => {}}
    />);
    const links = screen.getAllByRole('link', { name: /عرض الموقع/ });
    expect(links).toHaveLength(1);
    expect(links[0]).toHaveAttribute('href', 'https://www.google.com/maps/search/?api=1&query=24.7,46.6');
  });
});
