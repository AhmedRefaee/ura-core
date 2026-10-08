import type { Order } from '../types/domain';
import { orderDirectionLabel } from '../types/domain';
import { StatusChip } from './StatusChip';
import { offStockKind } from '../lib/orderItemView';

const OFF_STOCK_COLOR = '#5E35B1';

/** Purple "+N" pill: this order has items that must be bought from outside the inventory. */
function OffStockPill({ order }: { order: Order }) {
  const count = order.items.filter((i) => offStockKind(i, order.direction) !== null).length;
  if (count === 0) return null;
  return (
    <span
      title={`${count} ${count === 1 ? 'صنف' : 'أصناف'} خارج المخزون`}
      aria-label={`${count} خارج المخزون`}
      className="ms-2 inline-flex items-center gap-0.5 rounded-full border px-1.5 text-xs font-medium align-middle"
      style={{ color: OFF_STOCK_COLOR, borderColor: `${OFF_STOCK_COLOR}66`, background: `${OFF_STOCK_COLOR}14` }}
    >
      <span aria-hidden>+</span>
      {count}
    </span>
  );
}

interface OrdersTableProps {
  orders: Order[];
  onSelect: (id: string) => void;
  selectedId: string | null;
}

export function OrdersTable({ orders, onSelect, selectedId }: OrdersTableProps) {
  if (orders.length === 0) {
    return <div className="p-8 text-center text-text-low">لا توجد طلبات مطابقة</div>;
  }

  return (
    <table className="w-full text-sm text-right border-collapse">
      <thead className="sticky top-0 bg-surface-inset">
        <tr>
          <th className="h-9 px-3 text-xs font-medium text-text-low border-b border-border-subtle">رقم الطلب</th>
          <th className="h-9 px-3 text-xs font-medium text-text-low border-b border-border-subtle">الجهة</th>
          <th className="h-9 px-3 text-xs font-medium text-text-low border-b border-border-subtle">نوع العملية</th>
          <th className="h-9 px-3 text-xs font-medium text-text-low border-b border-border-subtle">الحالة</th>
          <th className="h-9 px-3 text-xs font-medium text-text-low border-b border-border-subtle">المندوب</th>
          <th className="h-9 px-3 text-xs font-medium text-text-low border-b border-border-subtle">التاريخ</th>
        </tr>
      </thead>
      <tbody>
        {orders.map((order) => (
          <tr
            key={order.id}
            onClick={() => onSelect(order.id)}
            className={`h-9 cursor-pointer border-b border-surface-inset hover:bg-surface-inset ${
              selectedId === order.id ? 'bg-surface-inset' : ''
            }`}
          >
            <td className="px-3">
              {order.referenceCode ?? order.id.slice(0, 8)}
              <OffStockPill order={order} />
            </td>
            <td className="px-3">{order.entity?.name ?? '—'}</td>
            <td className="px-3">{orderDirectionLabel[order.direction]}</td>
            <td className="px-3">
              <StatusChip status={order.status} />
            </td>
            <td className="px-3">{order.rep?.fullName ?? '—'}</td>
            <td className="px-3">{order.createdAt ? new Date(order.createdAt).toLocaleString('ar') : '—'}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
