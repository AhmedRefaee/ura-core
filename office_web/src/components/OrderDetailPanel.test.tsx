import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import type { Order, AuditLogEntry, DeliveryReceipt } from '../types/domain';

const detailMock = vi.fn();
vi.mock('../hooks/useOrderDetail', () => ({ useOrderDetail: () => detailMock() }));
vi.mock('../api/storage', () => ({ resolveSignedUrl: vi.fn().mockResolvedValue('https://signed.example/x.pdf') }));

import { OrderDetailPanel } from './OrderDetailPanel';

function order(overrides: Partial<Order>): Order {
  return {
    id: 'o1', referenceCode: 'RN-1', direction: 'outbound', entityId: 'e1',
    entity: { id: 'e1', name: 'وزارة الصحة', category: 'outgoing', contactName: null, contactPhone: null, address: null },
    repId: null, rep: { id: 'u1', fullName: 'مندوب أحمد', phone: null, role: 'rep', isApproved: true },
    creator: null, status: 'assigned', notes: null, storageActorId: null,
    createdAt: '2026-09-28T10:00:00Z', assignedAt: null, pickedUpAt: null, moveStartedAt: null,
    deliveredAt: null,
    items: [{
      id: 'i1', orderId: 'o1', inventoryId: null, inventoryName: 'أكياس أرز', quantity: 5,
      finalQuantity: null, isCustom: false, customDescription: null, checkStatus: 'pending',
      checkedBy: null, checker: null, wasUnavailableAtCreation: false,
    }],
    ...overrides,
  };
}

describe('OrderDetailPanel', () => {
  it('renders order info, the current step, and each item', () => {
    detailMock.mockReturnValue({
      order: order({}), auditLog: [] as AuditLogEntry[], receipts: [] as DeliveryReceipt[],
      isLoading: false, isError: false, refetch: vi.fn(),
    });
    render(<OrderDetailPanel orderId="o1" onClose={() => {}} />);
    expect(screen.getByText('وزارة الصحة')).toBeInTheDocument();
    expect(screen.getByText('مندوب أحمد')).toBeInTheDocument();
    expect(screen.getByText('أكياس أرز')).toBeInTheDocument();
  });

  it('renders the "no history yet" message instead of crashing when audit log is empty', () => {
    detailMock.mockReturnValue({
      order: order({}), auditLog: [] as AuditLogEntry[], receipts: [] as DeliveryReceipt[],
      isLoading: false, isError: false, refetch: vi.fn(),
    });
    render(<OrderDetailPanel orderId="o1" onClose={() => {}} />);
    expect(screen.getByText('لا يوجد سجل بعد')).toBeInTheDocument();
  });

  it('renders a chronological entry per audit log row, even with just order_created', () => {
    const entry: AuditLogEntry = {
      id: 'a1', orderId: 'o1', action: 'order_created', oldStatus: null, newStatus: 'assigned',
      performer: null, notes: null, serverTimestamp: '2026-09-28T10:00:00Z',
    };
    detailMock.mockReturnValue({
      order: order({}), auditLog: [entry], receipts: [], isLoading: false, isError: false, refetch: vi.fn(),
    });
    render(<OrderDetailPanel orderId="o1" onClose={() => {}} />);
    expect(screen.getByText('تم إنشاء الطلب')).toBeInTheDocument();
  });

  it('shows an empty message when there is no سند attached, not an error', () => {
    detailMock.mockReturnValue({
      order: order({}), auditLog: [], receipts: [], isLoading: false, isError: false, refetch: vi.fn(),
    });
    render(<OrderDetailPanel orderId="o1" onClose={() => {}} />);
    expect(screen.getByText('لا توجد سندات استلام لهذا الطلب')).toBeInTheDocument();
  });

  it('renders a سند row with a link once a PDF URL resolves', async () => {
    const receipt: DeliveryReceipt = {
      id: 'r1', orderId: 'o1', rep: { id: 'u1', fullName: 'مندوب أحمد', phone: null, role: 'rep', isApproved: true },
      deliveredAt: null, pdfUrl: 'org1/u1/1.pdf', notes: null, createdAt: '2026-09-28T09:00:00Z', items: [],
    };
    detailMock.mockReturnValue({
      order: order({}), auditLog: [], receipts: [receipt], isLoading: false, isError: false, refetch: vi.fn(),
    });
    render(<OrderDetailPanel orderId="o1" onClose={() => {}} />);
    await waitFor(() => expect(screen.getByRole('link', { name: /فتح السند/ })).toHaveAttribute('href', 'https://signed.example/x.pdf'));
  });
});
