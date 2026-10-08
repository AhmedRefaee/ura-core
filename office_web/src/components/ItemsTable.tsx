import type { OrderDirection, OrderItem } from '../types/domain';
import { formatDate } from '../lib/formatDate';
import { itemDisplayName, offStockKind, parseCustomPayload } from '../lib/orderItemView';

const OFF_STOCK_COLOR = '#5E35B1';
const KIND_LABEL = { new: 'جديد', outOfStock: 'غير متوفر' } as const;

const TH = 'h-8 px-3 text-xs font-medium text-text-low border-b border-border-subtle';

function StatusCell({ item, offStock }: { item: OrderItem; offStock: boolean }) {
  // Off-stock items are bought from outside, so "purchased" is the status that matters for them.
  if (offStock) {
    return item.purchasedAt ? (
      <div>
        <span className="text-success">تم الشراء</span>
        <div className="text-xs text-text-low">{formatDate(item.purchasedAt)}</div>
      </div>
    ) : (
      <span className="text-text-low">لم يُشترَ بعد</span>
    );
  }
  // Ordinary stock items only carry a status once someone has actually inspected them.
  if (item.checkStatus === 'pending') return <span className="text-text-low">—</span>;
  return (
    <div>
      <span style={{ color: item.checkStatus === 'checked' ? '#2E7D32' : '#B91C1C' }}>
        {item.checkStatus === 'checked' ? 'تم الفحص' : 'مرفوض'}
      </span>
      {item.checker && <div className="text-xs text-text-low">{item.checker.fullName}</div>}
      {item.checkedAt && <div className="text-xs text-text-low">{formatDate(item.checkedAt)}</div>}
    </div>
  );
}

export function ItemsTable({ items, direction }: { items: OrderItem[]; direction: OrderDirection }) {
  if (items.length === 0) {
    return <p className="text-sm text-text-low">لا توجد أصناف في هذا الطلب</p>;
  }

  return (
    <table className="w-full text-sm text-right border-collapse">
      <thead className="sticky top-0 bg-surface-inset">
        <tr>
          <th className={TH}>م</th>
          <th className={TH}>الصنف</th>
          <th className={TH}>الكمية</th>
          <th className={TH}>الحالة</th>
        </tr>
      </thead>
      <tbody>
        {items.map((item, i) => {
          const kind = offStockKind(item, direction);
          const payload = parseCustomPayload(item);
          const unit = payload?.unit;
          const detail = [payload?.brand, payload?.variety].filter(Boolean).join(' · ');
          const finalQtyChanged = item.finalQuantity != null && item.finalQuantity !== item.quantity;
          return (
            <tr key={item.id} className="border-b border-surface-inset hover:bg-surface-inset align-top">
              <td className="px-3 py-2 text-text-low">{i + 1}</td>
              <td className="px-3 py-2">
                <div className="text-text-high">{itemDisplayName(item)}</div>
                {detail && <div className="text-xs text-text-low">{detail}</div>}
                {kind && (
                  <span
                    className="mt-1 inline-block text-xs px-1.5 py-0.5 rounded-input border"
                    style={{ color: OFF_STOCK_COLOR, borderColor: `${OFF_STOCK_COLOR}66`, background: `${OFF_STOCK_COLOR}14` }}
                  >
                    خارج المخزون · {KIND_LABEL[kind]}
                  </span>
                )}
              </td>
              <td className="px-3 py-2 text-text-medium whitespace-nowrap">
                {finalQtyChanged ? (
                  <>
                    <span className="text-text-high">{item.finalQuantity}</span>
                    <span className="text-xs text-text-low line-through ms-1.5">{item.quantity}</span>
                  </>
                ) : (
                  item.quantity
                )}
                {unit && <span className="text-xs text-text-low ms-1">{unit}</span>}
              </td>
              <td className="px-3 py-2">
                <StatusCell item={item} offStock={kind !== null} />
              </td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}
