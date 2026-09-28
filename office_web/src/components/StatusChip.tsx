import type { OrderStatus } from '../types/domain';
import { orderStatusLabel } from '../types/domain';

// Exact hex values from lib/core/design_system/theme/colors/order_status_colors.dart
const statusStyle: Record<OrderStatus, { bg: string; text: string }> = {
  assigned: { bg: '#E5393520', text: '#E53935' },
  picked_up: { bg: '#FB8C0020', text: '#FB8C00' },
  on_the_move: { bg: '#FBC02D20', text: '#8A6D00' },
  delivered: { bg: '#43A04720', text: '#2E7D32' },
  delivered_to_storage: { bg: '#43A04720', text: '#2E7D32' },
};

export function StatusChip({ status }: { status: OrderStatus }) {
  const style = statusStyle[status];
  return (
    <span
      className="inline-flex items-center px-2 py-0.5 rounded-input text-xs font-medium"
      style={{ backgroundColor: style.bg, color: style.text }}
    >
      {orderStatusLabel[status]}
    </span>
  );
}
