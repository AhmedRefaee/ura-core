import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { StatusProgress } from './StatusProgress';
import type { StatusStep } from '../lib/statusSteps';
import type { StepTimelineEntry } from '../lib/stepTimeline';
import type { AuditLogEntry } from '../types/domain';
import { formatTime } from '../lib/formatDate';

const steps: StatusStep[] = [
  { status: 'assigned', label: 'معين' },
  { status: 'picked_up', label: 'تم الاستلام' },
  { status: 'on_the_move', label: 'في الطريق' },
  { status: 'delivered', label: 'تم التسليم' },
];

function entryFor(status: StatusStep['status']): AuditLogEntry {
  return {
    id: `a-${status}`, orderId: 'o1', action: 'status_change', oldStatus: null, newStatus: status,
    performer: null, notes: null, serverTimestamp: '2026-09-28T10:00:12Z',
  };
}

const stepTimeline: StepTimelineEntry[] = steps.map((s) => ({
  status: s.status, entry: entryFor(s.status), duration: '12 ثانية',
}));

describe('StatusProgress', () => {
  it('renders every step label', () => {
    render(<StatusProgress steps={steps} currentIndex={1} stepTimeline={stepTimeline} hoveredStatus={null} onHoverStatus={() => {}} />);
    for (const step of steps) {
      expect(screen.getByText(step.label)).toBeInTheDocument();
    }
  });

  it('marks reached steps with a checkmark and leaves later steps unmarked', () => {
    render(<StatusProgress steps={steps} currentIndex={1} stepTimeline={stepTimeline} hoveredStatus={null} onHoverStatus={() => {}} />);
    expect(screen.getAllByText('✓')).toHaveLength(2);
  });

  it('marks every step reached when the order is fully delivered', () => {
    render(<StatusProgress steps={steps} currentIndex={3} stepTimeline={stepTimeline} hoveredStatus={null} onHoverStatus={() => {}} />);
    expect(screen.getAllByText('✓')).toHaveLength(4);
  });

  it('calls onHoverStatus with the step\'s status on mouse enter, and null on mouse leave', () => {
    const onHoverStatus = vi.fn();
    render(<StatusProgress steps={steps} currentIndex={1} stepTimeline={stepTimeline} hoveredStatus={null} onHoverStatus={onHoverStatus} />);
    const circle = screen.getByTestId('status-step-picked_up');
    fireEvent.mouseEnter(circle);
    expect(onHoverStatus).toHaveBeenCalledWith('picked_up');
    fireEvent.mouseLeave(circle);
    expect(onHoverStatus).toHaveBeenCalledWith(null);
  });

  it('always shows each step\'s exact time and duration, without needing hover', () => {
    render(<StatusProgress steps={steps} currentIndex={1} stepTimeline={stepTimeline} hoveredStatus={null} onHoverStatus={() => {}} />);
    expect(screen.getAllByText(formatTime('2026-09-28T10:00:12Z')).length).toBeGreaterThan(0);
    expect(screen.getAllByText('12 ثانية').length).toBeGreaterThan(0);
  });

  it('never truncates the time text -- the exact second must stay fully readable', () => {
    render(<StatusProgress steps={steps} currentIndex={1} stepTimeline={stepTimeline} hoveredStatus={null} onHoverStatus={() => {}} />);
    for (const timeEl of screen.getAllByText(formatTime('2026-09-28T10:00:12Z'))) {
      expect(timeEl.className).not.toMatch(/truncate|text-ellipsis/);
    }
  });

  it('shows the performer who completed a step, above the step', () => {
    const withPerformer: StepTimelineEntry[] = steps.map((s) => ({
      status: s.status,
      entry: { ...entryFor(s.status), performer: { id: 'u1', fullName: 'فاحص سالم', phone: null, role: 'verifier', isApproved: true } },
      duration: '12 ثانية',
    }));
    render(<StatusProgress steps={steps} currentIndex={3} stepTimeline={withPerformer} hoveredStatus={null} onHoverStatus={() => {}} />);
    expect(screen.getAllByText(/فاحص سالم/).length).toBeGreaterThan(0);
  });

  it('stacks vertically with the same data when orientation is "vertical"', () => {
    render(
      <StatusProgress
        steps={steps}
        currentIndex={1}
        stepTimeline={stepTimeline}
        hoveredStatus={null}
        onHoverStatus={() => {}}
        orientation="vertical"
      />,
    );
    for (const step of steps) {
      expect(screen.getByText(step.label)).toBeInTheDocument();
    }
    expect(screen.getAllByText('✓')).toHaveLength(2);
    expect(screen.getAllByText('12 ثانية').length).toBeGreaterThan(0);
  });

  it('shows no duration line when the step has none (e.g. the current, still-ongoing step)', () => {
    const partialTimeline: StepTimelineEntry[] = steps.map((s) => ({
      status: s.status, entry: s.status === 'assigned' ? entryFor('assigned') : null, duration: null,
    }));
    render(<StatusProgress steps={steps} currentIndex={0} stepTimeline={partialTimeline} hoveredStatus="assigned" onHoverStatus={() => {}} />);
    expect(screen.queryByText(/ثانية|دقيقة|ساعة/)).not.toBeInTheDocument();
  });
});
