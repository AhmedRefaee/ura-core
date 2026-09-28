import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { StatusProgress } from './StatusProgress';
import type { StatusStep } from '../lib/statusSteps';

const steps: StatusStep[] = [
  { status: 'assigned', label: 'معين' },
  { status: 'picked_up', label: 'تم الاستلام' },
  { status: 'on_the_move', label: 'في الطريق' },
  { status: 'delivered', label: 'تم التسليم' },
];

describe('StatusProgress', () => {
  it('renders every step label', () => {
    render(<StatusProgress steps={steps} currentIndex={1} />);
    for (const step of steps) {
      expect(screen.getByText(step.label)).toBeInTheDocument();
    }
  });

  it('marks reached steps with a checkmark and leaves later steps unmarked', () => {
    render(<StatusProgress steps={steps} currentIndex={1} />);
    // Reached: index 0 and 1 (معين, تم الاستلام) get a check icon each.
    expect(screen.getAllByText('✓')).toHaveLength(2);
  });

  it('marks every step reached when the order is fully delivered', () => {
    render(<StatusProgress steps={steps} currentIndex={3} />);
    expect(screen.getAllByText('✓')).toHaveLength(4);
  });
});
