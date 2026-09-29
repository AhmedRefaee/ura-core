import type { ItemCheckStatus, OrderItem } from '../types/domain';
import { formatDate } from '../lib/formatDate';

const CHECK_STATUS_STYLE: Record<ItemCheckStatus, { label: string; color: string }> = {
  checked: { label: 'تم الفحص', color: '#2E7D32' },
  rejected: { label: 'مرفوض', color: '#B91C1C' },
  pending: { label: 'قيد الانتظار', color: '#64748B' },
};

function itemName(item: OrderItem): string {
  return item.isCustom ? (item.customDescription ?? 'صنف مخصص') : (item.inventoryName ?? '—');
}

export function ItemsTable({ items }: { items: OrderItem[] }) {
  if (items.length === 0) {
    return <p className="text-sm text-text-low">لا توجد أصناف في هذا الطلب</p>;
  }

  return (
    <table className="w-full text-sm text-right border-collapse">
      <thead className="sticky top-0 bg-surface-inset">
        <tr>
          <th className="h-8 px-2 text-xs font-medium text-text-low border-b border-border-subtle">م</th>
          <th className="h-8 px-2 text-xs font-medium text-text-low border-b border-border-subtle">الصنف</th>
          <th className="h-8 px-2 text-xs font-medium text-text-low border-b border-border-subtle">الكمية المطلوبة</th>
          <th className="h-8 px-2 text-xs font-medium text-text-low border-b border-border-subtle">الكمية النهائية</th>
          <th className="h-8 px-2 text-xs font-medium text-text-low border-b border-border-subtle">الحالة</th>
          <th className="h-8 px-2 text-xs font-medium text-text-low border-b border-border-subtle">الفاحص</th>
        </tr>
      </thead>
      <tbody>
        {items.map((item, i) => {
          const style = CHECK_STATUS_STYLE[item.checkStatus];
          const finalQtyChanged = item.finalQuantity != null && item.finalQuantity !== item.quantity;
          return (
            <tr key={item.id} className="border-b border-surface-inset hover:bg-surface-inset">
              <td className="px-2 py-1.5 text-text-low">{i + 1}</td>
              <td className="px-2 py-1.5">
                <span className="text-text-high">{itemName(item)}</span>
                {!item.isCustom && item.wasUnavailableAtCreation && (
                  <span className="ms-1.5 inline-block text-xs text-warning bg-warning-bg px-1.5 py-0.5 rounded-input">
                    غير متوفر
                  </span>
                )}
              </td>
              <td className="px-2 py-1.5 text-text-medium">{item.quantity}</td>
              <td className="px-2 py-1.5 text-text-medium">{finalQtyChanged ? item.finalQuantity : '—'}</td>
              <td className="px-2 py-1.5">
                <span style={{ color: style.color }}>{style.label}</span>
              </td>
              <td className="px-2 py-1.5 text-text-low text-xs">
                {item.checker && <div>{item.checker.fullName}</div>}
                {item.checkedAt && <div>{formatDate(item.checkedAt)}</div>}
              </td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}
