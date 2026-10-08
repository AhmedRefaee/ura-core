import type { OrderDirection, OrderItem } from '../types/domain';

export type OffStockKind = 'new' | 'outOfStock';

export interface CustomItemPayload {
  name?: string;
  unit?: string;
  brand?: string;
  variety?: string;
}

/** Off-stock items store their details as a JSON string in custom_description. */
export function parseCustomPayload(item: OrderItem): CustomItemPayload | null {
  const desc = item.customDescription;
  if (!desc || !desc.startsWith('{')) return null;
  try {
    const json = JSON.parse(desc);
    return json && typeof json === 'object' ? (json as CustomItemPayload) : null;
  } catch {
    return null;
  }
}

export function itemDisplayName(item: OrderItem): string {
  if (!item.isCustom) return item.inventoryName ?? '—';
  const payload = parseCustomPayload(item);
  if (payload) return payload.name || 'صنف خارج المخزون';
  return item.customDescription ?? 'صنف خارج المخزون';
}

/** Mirrors the app's offStockKindOf: a link back to an inventory row means it was out of stock, not new. */
export function offStockKind(item: OrderItem, direction: OrderDirection): OffStockKind | null {
  if (item.isCustom) return item.sourceInventoryId == null ? 'new' : 'outOfStock';
  if (direction === 'outbound' && item.wasUnavailableAtCreation) return 'outOfStock';
  return null;
}
