import { useEffect, useState } from 'react';
import { useOrderDetail } from '../hooks/useOrderDetail';
import { resolveSignedUrl } from '../api/storage';
import { getStatusSteps, getCurrentStepIndex } from '../lib/statusSteps';
import { buildStepTimeline } from '../lib/stepTimeline';
import { formatDate } from '../lib/formatDate';
import { StatusChip } from './StatusChip';
import { StatusProgress } from './StatusProgress';
import { AuditTimeline } from './AuditTimeline';
import { ItemsTable } from './ItemsTable';
import { StatesPanel } from './StatesPanel';
import { orderDirectionLabel } from '../types/domain';
import type { DeliveryReceipt, OrderStatus } from '../types/domain';

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
  const [hoveredStatus, setHoveredStatus] = useState<OrderStatus | null>(null);

  if (isLoading) return <StatesPanel kind="loading" />;
  if (isError || !order) return <StatesPanel kind="error" message={(error as Error)?.message} onRetry={refetch} />;

  const steps = getStatusSteps(order);
  const currentIndex = getCurrentStepIndex(steps, order);
  const stepTimeline = buildStepTimeline(steps, auditLog);

  return (
    <div className="w-[560px] shrink-0 border-r border-border-subtle bg-surface-card overflow-y-auto">
      <div className="sticky top-0 z-20 flex items-center justify-between p-4 border-b border-border-subtle bg-surface-card">
        <span className="font-mono text-sm text-text-medium">{order.referenceCode ?? order.id}</span>
        <button type="button" onClick={onClose} className="text-text-low hover:text-text-high">✕</button>
      </div>

      <div className="p-4 space-y-1 text-sm border-b border-border-subtle">
        <p><span className="text-text-low">الجهة: </span>{order.entity?.name ?? '—'}</p>
        <p><span className="text-text-low">الاتجاه: </span>{orderDirectionLabel[order.direction]}</p>
        <p><span className="text-text-low">المندوب: </span>{order.rep?.fullName ?? 'لا يوجد'}</p>
        <p><span className="text-text-low">أنشأه: </span>{order.creator?.fullName ?? '—'}</p>
        <p><span className="text-text-low">الحالة: </span><StatusChip status={order.status} /></p>
        {order.notes && <p><span className="text-text-low">ملاحظات: </span>{order.notes}</p>}
      </div>

      <div className="p-4 border-b border-border-subtle">
        <h3 className="text-sm font-semibold mb-3">تقدم الطلب</h3>
        <StatusProgress
          steps={steps}
          currentIndex={currentIndex}
          stepTimeline={stepTimeline}
          hoveredStatus={hoveredStatus}
          onHoverStatus={setHoveredStatus}
        />
      </div>

      <div className="p-4 border-b border-border-subtle">
        <h3 className="text-sm font-semibold mb-2">السجل الزمني</h3>
        <AuditTimeline
          auditLog={auditLog}
          orderStatus={order.status}
          error={auditLogError}
          hoveredStatus={hoveredStatus}
          onHoverEntry={setHoveredStatus}
        />
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
        <div className="overflow-x-auto">
          <ItemsTable items={order.items} />
        </div>
      </div>
    </div>
  );
}
