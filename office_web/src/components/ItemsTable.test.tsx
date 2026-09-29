import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ItemsTable } from './ItemsTable';
import type { OrderItem } from '../types/domain';

function item(overrides: Partial<OrderItem>): OrderItem {
  return {
    id: 'i1', orderId: 'o1', inventoryId: 'inv1', inventoryName: 'أكياس أرز', quantity: 5,
    finalQuantity: null, isCustom: false, customDescription: null, checkStatus: 'pending',
    checkedBy: null, checkedAt: null, checker: null, wasUnavailableAtCreation: false,
    ...overrides,
  };
}

describe('ItemsTable', () => {
  it('renders a row number, name, and requested quantity per item', () => {
    render(<ItemsTable items={[item({})]} />);
    expect(screen.getByText('1')).toBeInTheDocument();
    expect(screen.getByText('أكياس أرز')).toBeInTheDocument();
    expect(screen.getByText('5')).toBeInTheDocument();
  });

  it('shows a custom item by its description', () => {
    render(<ItemsTable items={[item({ isCustom: true, customDescription: 'صنف خاص', inventoryName: null })]} />);
    expect(screen.getByText('صنف خاص')).toBeInTheDocument();
  });

  it('shows the final quantity only when it differs from the requested one', () => {
    render(<ItemsTable items={[item({ quantity: 5, finalQuantity: 3 })]} />);
    expect(screen.getByText('3')).toBeInTheDocument();
  });

  it('omits the final-quantity column value when it is null', () => {
    render(<ItemsTable items={[item({ quantity: 5, finalQuantity: null })]} />);
    expect(screen.getByText('—')).toBeInTheDocument();
  });

  it('shows the check status and, when checked, the checker name', () => {
    render(<ItemsTable items={[item({
      checkStatus: 'checked', checker: { id: 'u2', fullName: 'فاحص سالم', phone: null, role: 'verifier', isApproved: true },
    })]} />);
    expect(screen.getByText('تم الفحص')).toBeInTheDocument();
    expect(screen.getByText('فاحص سالم')).toBeInTheDocument();
  });

  it('shows the "غير متوفر" badge only for a non-custom item flagged unavailable at creation', () => {
    render(<ItemsTable items={[item({ wasUnavailableAtCreation: true })]} />);
    expect(screen.getByText('غير متوفر')).toBeInTheDocument();
  });

  it('shows an empty message instead of a table when there are no items', () => {
    render(<ItemsTable items={[]} />);
    expect(screen.getByText('لا توجد أصناف في هذا الطلب')).toBeInTheDocument();
  });
});
