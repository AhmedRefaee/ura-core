import { useEffect, useRef } from 'react';
import type { AuditLogEntry, OrderStatus } from '../types/domain';
import { orderStatusLabel, userRoleLabel } from '../types/domain';
import { orderStatusColor } from '../lib/statusColors';
import { formatDate } from '../lib/formatDate';
import { durationBetween } from '../lib/duration';

const DONE_STATUSES = new Set<OrderStatus>(['delivered', 'delivered_to_storage']);

// Mirrors the real Flutter timeline widget: label off newStatus, not the raw
// action string, since action values (status_change, mark_picked_up, ...)
// don't map 1:1 to a readable label the way statuses do.
function auditEntryLabel(entry: AuditLogEntry): string {
  if (entry.action === 'order_created') return 'تم إنشاء الطلب';
  if (entry.newStatus && orderStatusLabel[entry.newStatus]) return orderStatusLabel[entry.newStatus];
  return entry.action;
}

interface AuditTimelineProps {
  auditLog: AuditLogEntry[];
  orderStatus: OrderStatus;
  error: boolean;
  hoveredStatus: OrderStatus | null;
  onHoverEntry: (status: OrderStatus | null) => void;
}

export function AuditTimeline({ auditLog, orderStatus, error, hoveredStatus, onHoverEntry }: AuditTimelineProps) {
  const rowRefs = useRef(new Map<string, HTMLLIElement>());

  // Scrolling here is a no-op (block: 'nearest') when the row is already
  // fully visible, so this is safe to run regardless of whether the hover
  // originated from this list or from the stepper above it.
  useEffect(() => {
    if (!hoveredStatus) return;
    const match = auditLog.find((e) => e.newStatus === hoveredStatus);
    if (!match) return;
    rowRefs.current.get(match.id)?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }, [hoveredStatus, auditLog]);

  if (error) return <p className="text-sm text-error">تعذر تحميل السجل الزمني</p>;
  if (auditLog.length === 0) return <p className="text-sm text-text-low">لا يوجد سجل بعد</p>;

  const total = auditLog.length >= 2
    ? durationBetween(auditLog[0].serverTimestamp, auditLog[auditLog.length - 1].serverTimestamp)
    : null;
  const bannerLabel = DONE_STATUSES.has(orderStatus)
    ? 'المدة الإجمالية من الإنشاء إلى التسليم'
    : 'المدة منذ الإنشاء حتى الآن';

  return (
    <div>
      {total && (
        <div className="mb-3 flex items-center justify-between rounded-input bg-success-bg px-3 py-2 text-sm text-success">
          <span>{bannerLabel}</span>
          <span className="font-semibold">{total}</span>
        </div>
      )}
      <ul className="space-y-1">
        {auditLog.map((entry, i) => {
          const next = auditLog[i + 1];
          const stepDuration = next ? durationBetween(entry.serverTimestamp, next.serverTimestamp) : null;
          const color = entry.newStatus ? orderStatusColor[entry.newStatus].text : '#64748B';
          const bg = entry.newStatus ? orderStatusColor[entry.newStatus].bg : undefined;
          const isHighlighted = entry.newStatus != null && entry.newStatus === hoveredStatus;
          return (
            <li
              key={entry.id}
              data-testid={`audit-row-${entry.id}`}
              ref={(el) => {
                if (el) rowRefs.current.set(entry.id, el);
                else rowRefs.current.delete(entry.id);
              }}
              className="flex items-start gap-2 rounded-input p-2 -mx-2 transition-colors duration-150 ease-out"
              style={{ backgroundColor: isHighlighted ? bg : undefined }}
              onMouseEnter={() => entry.newStatus && onHoverEntry(entry.newStatus)}
              onMouseLeave={() => onHoverEntry(null)}
            >
              <div className="w-2.5 h-2.5 rounded-full mt-1.5 shrink-0" style={{ backgroundColor: color }} />
              <div className="flex-1 min-w-0">
                <div className="flex items-center justify-between gap-2">
                  <span className="text-sm font-medium text-text-high">{auditEntryLabel(entry)}</span>
                  {stepDuration && (
                    <span
                      className="shrink-0 rounded-input px-1.5 py-0.5 text-xs font-medium"
                      style={{ backgroundColor: `${color}20`, color }}
                    >
                      {stepDuration}
                    </span>
                  )}
                </div>
                <p className="text-xs text-text-low">{formatDate(entry.serverTimestamp)}</p>
                {entry.performer && (
                  <p className="text-xs text-text-low">
                    {entry.performer.role ? `${userRoleLabel[entry.performer.role]} · ` : ''}
                    {entry.performer.fullName}
                  </p>
                )}
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
