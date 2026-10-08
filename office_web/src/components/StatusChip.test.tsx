import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { StatusChip } from './StatusChip';

describe('StatusChip', () => {
  it.each([
    ['assigned', 'معين'],
    ['picked_up', 'تم الاستلام'],
    ['on_the_move', 'في الطريق'],
    ['delivered', 'تم التسليم'],
    ['delivered_to_storage', 'تم الاستلام في المخزن'],
  ] as const)('renders the Arabic label for %s', (status, label) => {
    render(<StatusChip status={status} />);
    expect(screen.getByText(label)).toBeInTheDocument();
  });
});
