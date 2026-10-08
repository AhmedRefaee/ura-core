import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { OrdersTable } from './OrdersTable';
import type { Order } from '../types/domain';

function order(overrides: Partial<Order>): Order {
  return {
    id: 'o1', referenceCode: 'RN-1', direction: 'outbound', entityId: 'e1',
    entity: { id: 'e1', name: 'وزارة الصحة', category: 'outgoing', contactName: null, contactPhone: null, address: null },
    repId: null, rep: null, creator: null, status: 'assigned', notes: null,
    storageActorId: null, createdAt: '2026-09-28T10:00:00Z', assignedAt: null,
    pickedUpAt: null, moveStartedAt: null, deliveredAt: null, items: [],
    ...overrides,
  };
}

describe('OrdersTable', () => {
  it('renders one row per order with its entity, direction and status', () => {
    render(<OrdersTable orders={[order({})]} onSelect={() => {}} selectedId={null} />);
    expect(screen.getByText('وزارة الصحة')).toBeInTheDocument();
    expect(screen.getByText('توريد')).toBeInTheDocument();
    expect(screen.getByText('معين')).toBeInTheDocument();
  });

  it('calls onSelect with the order id when a row is clicked', () => {
    const onSelect = vi.fn();
    render(<OrdersTable orders={[order({ id: 'o42' })]} onSelect={onSelect} selectedId={null} />);
    fireEvent.click(screen.getByText('وزارة الصحة'));
    expect(onSelect).toHaveBeenCalledWith('o42');
  });

  it('shows an empty message when there are no orders', () => {
    render(<OrdersTable orders={[]} onSelect={() => {}} selectedId={null} />);
    expect(screen.getByText('لا توجد طلبات مطابقة')).toBeInTheDocument();
  });

  it('shows a purple +N pill only on orders with off-stock items', () => {
    const base = {
      id: 'i', orderId: 'o1', inventoryId: null, inventoryName: null, quantity: 1, finalQuantity: null,
      isCustom: true, customDescription: 'x', sourceInventoryId: null, purchasedAt: null,
      checkStatus: 'pending' as const, checkedBy: null, checkedAt: null, checker: null, wasUnavailableAtCreation: false,
    };
    render(<OrdersTable orders={[
      order({ id: 'a', referenceCode: 'A', items: [base, { ...base, id: 'j' }] }),
      order({ id: 'b', referenceCode: 'B', items: [] }),
    ]} onSelect={() => {}} selectedId={null} />);
    expect(screen.getAllByLabelText(/خارج المخزون/)).toHaveLength(1);
    expect(screen.getByLabelText('2 خارج المخزون')).toBeInTheDocument();
  });
});
