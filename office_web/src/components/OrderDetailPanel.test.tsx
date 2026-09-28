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
      checkedBy: null, checkedAt: null, checker: null, wasUnavailableAtCreation: false,
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

  it('shows the status label (not the raw action string) for an entry with a recognized newStatus', () => {
    const entry: AuditLogEntry = {
      id: 'a2', orderId: 'o1', action: 'mark_picked_up', oldStatus: 'assigned', newStatus: 'picked_up',
      performer: null, notes: null, serverTimestamp: '2026-09-28T10:10:00Z',
    };
    detailMock.mockReturnValue({
      order: order({}), auditLog: [entry], receipts: [], isLoading: false, isError: false, refetch: vi.fn(),
    });
    render(<OrderDetailPanel orderId="o1" onClose={() => {}} />);
    expect(screen.getByText('تم الاستلام')).toBeInTheDocument();
    expect(screen.queryByText('mark_picked_up')).not.toBeInTheDocument();
  });

  it('shows a checked-item indicator with the checker name', () => {
    detailMock.mockReturnValue({
      order: order({
        items: [{
          id: 'i1', orderId: 'o1', inventoryId: 'inv1', inventoryName: 'أكياس أرز', quantity: 5,
          finalQuantity: null, isCustom: false, customDescription: null, checkStatus: 'checked',
          checkedBy: 'u2', checkedAt: '2026-09-28T11:30:00Z',
          checker: { id: 'u2', fullName: 'فاحص سالم', phone: null, role: 'verifier', isApproved: true },
          wasUnavailableAtCreation: false,
        }],
      }),
      auditLog: [], receipts: [], isLoading: false, isError: false, refetch: vi.fn(),
    });
    render(<OrderDetailPanel orderId="o1" onClose={() => {}} />);
    expect(screen.getByText(/تم الفحص/)).toBeInTheDocument();
    expect(screen.getByText(/فاحص سالم/)).toBeInTheDocument();
  });

  it('shows a pending-item indicator without a checker name', () => {
    detailMock.mockReturnValue({
      order: order({}), // default item has checkStatus 'pending', checker null
      auditLog: [], receipts: [], isLoading: false, isError: false, refetch: vi.fn(),
    });
    render(<OrderDetailPanel orderId="o1" onClose={() => {}} />);
    expect(screen.getByText('قيد الانتظار')).toBeInTheDocument();
  });

  it('shows an inline audit-log error instead of blanking the panel when the audit log fails to load', () => {
    detailMock.mockReturnValue({
      order: order({}), auditLog: [], receipts: [], isLoading: false, isError: false,
      auditLogError: true, receiptsError: false, refetch: vi.fn(),
    });
    render(<OrderDetailPanel orderId="o1" onClose={() => {}} />);
    expect(screen.getByText('تعذر تحميل السجل الزمني')).toBeInTheDocument();
    // The rest of the panel still renders normally.
    expect(screen.getByText('وزارة الصحة')).toBeInTheDocument();
    expect(screen.getByText('أكياس أرز')).toBeInTheDocument();
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
