import { useEffect, useState } from 'react';
import { useOrderDetail } from '../hooks/useOrderDetail';
import { resolveSignedUrl } from '../api/storage';
import { getStatusSteps, getCurrentStepIndex } from '../lib/statusSteps';
import { StatusChip } from './StatusChip';
import { StatesPanel } from './StatesPanel';
import { orderDirectionLabel } from '../types/domain';
import type { AuditLogEntry, DeliveryReceipt } from '../types/domain';

const ACTION_LABEL: Record<string, string> = {
  order_created: 'تم إنشاء الطلب',
  status_changed: 'تغيير حالة الطلب',
};

function auditEntryLabel(entry: AuditLogEntry): string {
  return ACTION_LABEL[entry.action] ?? entry.action;
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
  const { order, auditLog, receipts, isLoading, isError, error, refetch } = useOrderDetail(orderId);

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
        {auditLog.length === 0 ? (
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
        {receipts.length === 0 ? (
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
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
