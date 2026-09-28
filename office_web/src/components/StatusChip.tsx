import type { OrderStatus } from '../types/domain';
import { orderStatusLabel } from '../types/domain';
import { orderStatusColor } from '../lib/statusColors';

export function StatusChip({ status }: { status: OrderStatus }) {
  const style = orderStatusColor[status];
  return (
    <span
      className="inline-flex items-center px-2 py-0.5 rounded-input text-xs font-medium"
      style={{ backgroundColor: style.bg, color: style.text }}
    >
      {orderStatusLabel[status]}
    </span>
  );
}
