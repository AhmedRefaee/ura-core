import { useEffect, useState } from 'react';
import { useOrderDetail } from '../hooks/useOrderDetail';
import { resolveSignedUrl } from '../api/storage';
import { getStatusSteps, getCurrentStepIndex } from '../lib/statusSteps';
import { StatusChip } from './StatusChip';
import { StatesPanel } from './StatesPanel';
import { orderDirectionLabel, orderStatusLabel } from '../types/domain';
import type { AuditLogEntry, DeliveryReceipt, ItemCheckStatus } from '../types/domain';

const CHECK_STATUS_STYLE: Record<ItemCheckStatus, { label: string; color: string }> = {
  checked: { label: 'تم الفحص', color: '#2E7D32' },
  rejected: { label: 'مرفوض', color: '#B91C1C' },
  pending: { label: 'قيد الانتظار', color: '#64748B' },
};

// Mirrors the real Flutter timeline widget: label off newStatus, not the raw
// action string, since action values (status_change, mark_picked_up, ...)
// don't map 1:1 to a readable label the way statuses do.
function auditEntryLabel(entry: AuditLogEntry): string {
  if (entry.action === 'order_created') return 'تم إنشاء الطلب';
  if (entry.newStatus && orderStatusLabel[entry.newStatus]) return orderStatusLabel[entry.newStatus];
  return entry.action;
}

function formatDate(iso: string | null): string {
  return iso ? new Date(iso).toLocaleString('ar') : '—';
}

function ReceiptRow({ receipt }: { receipt: DeliveryReceipt }) {
  const [url, setUrl] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    resolveSignedUrl('delivery-receipts', receipt.pdfUrl).then((u) => {
      if (!cancelled) setUrl(u);
    });
    return () => {
      cancelled = true;
    };
  }, [receipt.pdfUrl]);

  return (
    <li className="flex items-center justify-between py-1.5 text-sm">
      <span className="text-text-medium">{formatDate(receipt.createdAt)} — {receipt.rep?.fullName ?? '—'}</span>
      {url && (
        <a href={url} target="_blank" rel="noreferrer" className="text-primary underline">
          فتح السند
        </a>
      )}
    </li>
  );
}

export function OrderDetailPanel({ orderId, onClose }: { orderId: string; onClose: () => void }) {
  const { order, auditLog, receipts, isLoading, isError, error, auditLogError, receiptsError, refetch } = useOrderDetail(orderId);

  if (isLoading) return <StatesPanel kind="loading" />;
  if (isError || !order) return <StatesPanel kind="error" message={(error as Error)?.message} onRetry={refetch} />;

  const steps = getStatusSteps(order);
  const currentIndex = getCurrentStepIndex(steps, order);

  return (
    <div className="w-[420px] shrink-0 border-r border-border-subtle bg-surface-card overflow-y-auto">
      <div className="flex items-center justify-between p-4 border-b border-border-subtle">
        <span className="font-mono text-sm text-text-medium">{order.referenceCode ?? order.id}</span>
        <button type="button" onClick={onClose} className="text-text-low hover:text-text-high">✕</button>
      </div>

      <div className="p-4 space-y-1 text-sm border-b border-border-subtle">
        <p><span className="text-text-low">الجهة: </span>{order.entity?.name ?? '—'}</p>
        <p><span className="text-text-low">الاتجاه: </span>{orderDirectionLabel[order.direction]}</p>
        <p><span className="text-text-low">المندوب: </span>{order.rep?.fullName ?? 'لا يوجد'}</p>
        <p><span className="text-text-low">الحالة: </span><StatusChip status={order.status} /></p>
        {order.notes && <p><span className="text-text-low">ملاحظات: </span>{order.notes}</p>}
      </div>

      <div className="p-4 border-b border-border-subtle">
        <h3 className="text-sm font-semibold mb-2">تقدم الطلب</h3>
        <ol className="flex flex-col gap-1">
          {steps.map((step, i) => (
            <li key={step.status} className={`text-sm ${i <= currentIndex ? 'text-text-high font-medium' : 'text-text-low'}`}>
              {i + 1}. {step.label}
            </li>
          ))}
        </ol>
      </div>

      <div className="p-4 border-b border-border-subtle">
        <h3 className="text-sm font-semibold mb-2">السجل الزمني</h3>
        {auditLogError ? (
          <p className="text-sm text-error">تعذر تحميل السجل الزمني</p>
        ) : auditLog.length === 0 ? (
          <p className="text-sm text-text-low">لا يوجد سجل بعد</p>
        ) : (
          <ul className="space-y-1">
            {auditLog.map((entry) => (
              <li key={entry.id} className="text-sm text-text-medium">
                {formatDate(entry.serverTimestamp)} — <span>{auditEntryLabel(entry)}</span>
                {entry.performer && ` — ${entry.performer.fullName}`}
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="p-4 border-b border-border-subtle">
        <h3 className="text-sm font-semibold mb-2">سندات الاستلام</h3>
        {receiptsError ? (
          <p className="text-sm text-error">تعذر تحميل سندات الاستلام</p>
        ) : receipts.length === 0 ? (
          <p className="text-sm text-text-low">لا توجد سندات استلام لهذا الطلب</p>
        ) : (
          <ul>
            {receipts.map((r) => <ReceiptRow key={r.id} receipt={r} />)}
          </ul>
        )}
      </div>

      <div className="p-4">
        <h3 className="text-sm font-semibold mb-2">الأصناف</h3>
        <ul className="space-y-2">
          {order.items.map((item) => (
            <li key={item.id} className="text-sm">
              <p className="font-medium text-text-high">{item.isCustom ? (item.customDescription ?? 'صنف مخصص') : (item.inventoryName ?? '—')}</p>
              <p className="text-text-low">
                الكمية: {item.finalQuantity ?? item.quantity}
                {item.finalQuantity != null && ` (مطلوب: ${item.quantity})`}
              </p>
              {item.wasUnavailableAtCreation && (
                <span className="inline-block text-xs text-warning bg-warning-bg px-2 py-0.5 rounded-input mt-1">غير متوفر</span>
              )}
              <p className="text-xs mt-1" style={{ color: CHECK_STATUS_STYLE[item.checkStatus].color }}>
                {CHECK_STATUS_STYLE[item.checkStatus].label}
                {item.checker && ` — ${item.checker.fullName}`}
                {item.checkedAt && ` — ${formatDate(item.checkedAt)}`}
              </p>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
