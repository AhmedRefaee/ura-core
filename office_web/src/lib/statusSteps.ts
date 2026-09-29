import type { Order, OrderStatus } from '../types/domain';

export interface StatusStep {
  status: OrderStatus;
  label: string;
}

function involvesStorage(order: Order): boolean {
  return order.items.some((i) => i.inventoryId != null);
}

export function getStatusSteps(order: Order): StatusStep[] {
  switch (order.direction) {
    case 'inbound_external':
      return [
        { status: 'assigned', label: 'تم الإنشاء' },
        { status: 'delivered_to_storage', label: 'تم الاستلام في المخزن' },
      ];
    case 'inbound_rep':
      return [
        { status: 'assigned', label: 'تم الإنشاء' },
        { status: 'picked_up', label: 'تم الشراء' },
        { status: 'on_the_move', label: 'في الطريق' },
        { status: 'delivered_to_storage', label: 'استلام المخزن' },
      ];
    case 'outbound':
    default:
      return [
        { status: 'assigned', label: 'معين' },
        { status: 'picked_up', label: involvesStorage(order) ? 'أُرسل من المخزن' : 'تم الاستلام' },
        { status: 'on_the_move', label: 'في الطريق' },
        { status: 'delivered', label: 'تم التسليم' },
      ];
  }
}

export function getCurrentStepIndex(steps: StatusStep[], order: Order): number {
  const index = steps.findIndex((step) => step.status === order.status);
  if (index >= 0) return index;
  if (order.status === 'delivered' || order.status === 'delivered_to_storage') return steps.length - 1;
  return 0;
}
