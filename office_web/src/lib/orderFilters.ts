import type { Order, OrderDirection } from '../types/domain';

export type SortMode = 'most_recent' | 'oldest' | 'frequent';
export type DirectionFilter = 'all' | OrderDirection;
export type GroupMode = 'entity' | 'rep';

export interface OrderGroup {
  key: string;
  label: string;
  orders: Order[];
}

function sortDate(order: Order): number {
  return order.createdAt ? new Date(order.createdAt).getTime() : 0;
}

export function filterOrdersByQuery(orders: Order[], query: string): Order[] {
  const q = query.trim().toLowerCase();
  if (!q) return orders;
  return orders.filter((order) =>
    (order.entity?.name ?? '').toLowerCase().includes(q) ||
    (order.rep?.fullName ?? '').toLowerCase().includes(q) ||
    (order.referenceCode ?? '').toLowerCase().includes(q),
  );
}

export function filterOrdersByDirection(orders: Order[], filter: DirectionFilter): Order[] {
  if (filter === 'all') return orders;
  return orders.filter((order) => order.direction === filter);
}

export function sortOrders(orders: Order[], mode: SortMode): Order[] {
  const entityCounts = new Map<string, number>();
  for (const order of orders) entityCounts.set(order.entityId, (entityCounts.get(order.entityId) ?? 0) + 1);

  return [...orders].sort((a, b) => {
    let result: number;
    if (mode === 'most_recent') result = sortDate(b) - sortDate(a);
    else if (mode === 'oldest') result = sortDate(a) - sortDate(b);
    else result = (entityCounts.get(b.entityId) ?? 0) - (entityCounts.get(a.entityId) ?? 0);
    return result !== 0 ? result : sortDate(b) - sortDate(a);
  });
}

export function groupOrders(orders: Order[], mode: GroupMode, sortMode: SortMode): OrderGroup[] {
  const groups = new Map<string, Order[]>();
  const labels = new Map<string, string>();

  for (const order of orders) {
    const key = mode === 'entity' ? order.entityId : order.repId ?? 'unassigned';
    const label = mode === 'entity' ? order.entity?.name ?? 'بدون جهة' : order.rep?.fullName ?? 'بدون مندوب';
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(order);
    labels.set(key, label);
  }

  const result: OrderGroup[] = Array.from(groups.entries()).map(([key, groupOrders]) => ({
    key,
    label: labels.get(key) ?? '—',
    orders: sortOrders(groupOrders, sortMode),
  }));

  result.sort((a, b) => a.label.localeCompare(b.label, 'ar'));
  return result;
}
