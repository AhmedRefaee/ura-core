import { useEffect, useState, type ReactNode } from 'react';
import { useOrderDetail } from '../hooks/useOrderDetail';
import { resolveSignedUrl } from '../api/storage';
import { getStatusSteps, getCurrentStepIndex } from '../lib/statusSteps';
import { buildStepTimeline } from '../lib/stepTimeline';
import { prepareAuditLogForDisplay } from '../lib/auditLogView';
import { formatDate, formatDateOnly } from '../lib/formatDate';
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

interface OrderDetailContentProps {
  orderId: string;
  // The one thing the panel (close button) and the full page (nothing, or a
  // back link) render differently in the header -- everything else about
  // showing an order's detail is identical between the two.
  headerActions?: ReactNode;
  // The panel is 560px wide, too narrow for a horizontal stepper with time/
  // duration/performer around each step, so it stacks vertically there; the
  // full page has room to stay horizontal.
  stepperOrientation?: 'horizontal' | 'vertical';
}

export function OrderDetailContent({ orderId, headerActions, stepperOrientation = 'horizontal' }: OrderDetailContentProps) {
  const { order, auditLog, receipts, isLoading, isError, error, auditLogError, receiptsError, refetch } = useOrderDetail(orderId);
  const [hoveredStatus, setHoveredStatus] = useState<OrderStatus | null>(null);

  if (isLoading) return <StatesPanel kind="loading" />;
  if (isError || !order) return <StatesPanel kind="error" message={(error as Error)?.message} onRetry={refetch} />;

  const steps = getStatusSteps(order);
  const currentIndex = getCurrentStepIndex(steps, order);
  // Collapses the real backend's same-instant duplicate rows (one generic
  // status_change + one specific action per transition) and drops non-status
  // audit rows -- see auditLogView.ts. Shared by both children below so the
  // stepper tooltip and the timeline list can never disagree.
  const displayAuditLog = prepareAuditLogForDisplay(auditLog);
  const stepTimeline = buildStepTimeline(steps, displayAuditLog);
  // Shown once here so every step/row below can give just its time, not the
  // full date -- avoids repeating the same date on every line.
  const orderDate = order.createdAt ?? displayAuditLog[0]?.serverTimestamp ?? null;

  return (
    <>
      <div className="sticky top-0 z-20 flex items-center justify-between p-4 border-b border-border-subtle bg-surface-card">
        <span className="font-mono text-sm text-text-medium">{order.referenceCode ?? order.id}</span>
        {headerActions}
      </div>

      <div className="p-4 space-y-1 text-sm border-b border-border-subtle">
        <p><span className="text-text-low">التاريخ: </span>{formatDateOnly(orderDate)}</p>
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
          orientation={stepperOrientation}
        />
      </div>

      <div className="p-4 border-b border-border-subtle">
        <h3 className="text-sm font-semibold mb-2">السجل الزمني</h3>
        <AuditTimeline
          auditLog={displayAuditLog}
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
    </>
  );
}
