import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { Sidebar } from './Sidebar';

describe('Sidebar', () => {
  it('shows الطلبات as enabled and the rest as قريباً', () => {
    render(<MemoryRouter><Sidebar /></MemoryRouter>);
    const orders = screen.getByRole('link', { name: /الطلبات/ });
    expect(orders).toHaveAttribute('href', '/orders');

    for (const label of ['المخزون', 'المناديب', 'الإحصائيات', 'الإعدادات']) {
      expect(screen.getByText(label).closest('div')).toHaveTextContent('قريباً');
    }
  });
});
