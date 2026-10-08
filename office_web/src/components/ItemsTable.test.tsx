import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ItemsTable } from './ItemsTable';
import type { OrderItem } from '../types/domain';

function item(overrides: Partial<OrderItem>): OrderItem {
  return {
    id: 'i1', orderId: 'o1', inventoryId: 'inv1', inventoryName: 'أكياس أرز', quantity: 5,
    finalQuantity: null, isCustom: false, customDescription: null, sourceInventoryId: null,
    purchasedAt: null, checkStatus: 'pending',
    checkedBy: null, checkedAt: null, checker: null, wasUnavailableAtCreation: false,
    ...overrides,
  };
}

const render1 = (i: OrderItem, direction: 'outbound' | 'inbound' = 'outbound') =>
  render(<ItemsTable items={[i]} direction={direction} />);

describe('ItemsTable', () => {
  it('renders a row number, name, and quantity per item', () => {
    render1(item({}));
    expect(screen.getByText('1')).toBeInTheDocument();
    expect(screen.getByText('أكياس أرز')).toBeInTheDocument();
    expect(screen.getByText('5')).toBeInTheDocument();
  });

  it('shows the name from a JSON custom payload, never the raw JSON', () => {
    render1(item({
      isCustom: true, inventoryName: null,
      customDescription: '{"name":"عصير برتقال","qty":1,"unit":"قطعة","minQty":0}',
    }));
    expect(screen.getByText('عصير برتقال')).toBeInTheDocument();
    expect(screen.getByText('قطعة')).toBeInTheDocument();
    expect(screen.queryByText(/minQty/)).toBeNull();
  });

  it('falls back to plain-text custom descriptions', () => {
    render1(item({ isCustom: true, customDescription: 'صنف خاص', inventoryName: null }));
    expect(screen.getByText('صنف خاص')).toBeInTheDocument();
  });

  it('badges an off-stock item and shows purchase status instead of check status', () => {
    render1(item({ isCustom: true, customDescription: 'صنف خاص', inventoryName: null }));
    expect(screen.getByText('خارج المخزون · جديد')).toBeInTheDocument();
    expect(screen.getByText('لم يُشترَ بعد')).toBeInTheDocument();
  });

  it('shows تم الشراء once purchased', () => {
    render1(item({ isCustom: true, customDescription: 'x', inventoryName: null, purchasedAt: '2026-09-20T10:00:00Z' }));
    expect(screen.getByText('تم الشراء')).toBeInTheDocument();
  });

  it('labels a converted (sourced) custom item as غير متوفر', () => {
    render1(item({ isCustom: true, customDescription: 'x', inventoryName: null, sourceInventoryId: 'inv9' }));
    expect(screen.getByText('خارج المخزون · غير متوفر')).toBeInTheDocument();
  });

  it('shows no status for an ordinary item nobody has checked', () => {
    render1(item({}));
    expect(screen.getByText('—')).toBeInTheDocument();
    expect(screen.queryByText('قيد الانتظار')).toBeNull();
  });

  it('shows the check result and checker once checked', () => {
    render1(item({
      checkStatus: 'checked', checker: { id: 'u2', fullName: 'فاحص سالم', phone: null, role: 'verifier', isApproved: true },
    }));
    expect(screen.getByText('تم الفحص')).toBeInTheDocument();
    expect(screen.getByText('فاحص سالم')).toBeInTheDocument();
  });

  it('shows the final quantity prominently with the requested one struck through when they differ', () => {
    render1(item({ quantity: 5, finalQuantity: 3 }));
    expect(screen.getByText('3')).toBeInTheDocument();
    expect(screen.getByText('5')).toHaveClass('line-through');
  });

  it('flags a stock item that was unavailable at creation on an outbound order', () => {
    render1(item({ wasUnavailableAtCreation: true }));
    expect(screen.getByText('خارج المخزون · غير متوفر')).toBeInTheDocument();
  });

  it('shows an empty message instead of a table when there are no items', () => {
    render(<ItemsTable items={[]} direction="outbound" />);
    expect(screen.getByText('لا توجد أصناف في هذا الطلب')).toBeInTheDocument();
  });
});
