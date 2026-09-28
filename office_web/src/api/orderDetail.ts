import { supabase } from '../lib/supabase';
import { mapOrder, mapAuditLogEntry, mapDeliveryReceipt } from '../lib/mappers';
import type { Order, AuditLogEntry, DeliveryReceipt } from '../types/domain';

// Mirrors OrderRepository._orderDetailSelect in lib/features/verifier/data/order_repository.dart
export const ORDER_DETAIL_SELECT =
  'id, reference_code, direction, entity_id, rep_id, created_by, storage_actor_id, status, notes, ' +
  'created_at, assigned_at, picked_up_at, move_started_at, delivered_at, ' +
  'entity:entities(id, name, category, contact_name, contact_phone, address), ' +
  'rep:profiles!orders_rep_id_fkey(id, full_name, phone, role, is_approved, created_at), ' +
  'creator:profiles!orders_created_by_fkey(id, full_name, phone, role, is_approved, created_at), ' +
  'order_items(id, order_id, inventory_id, quantity, final_quantity, is_custom, custom_description, source_inventory_id, ' +
  'check_status, checked_by, checked_at, ' +
  'inventory:inventory!order_items_inventory_id_fkey(id, item_name), ' +
  'checker:profiles!order_items_checked_by_fkey(id, full_name, phone, role, is_approved, created_at))';

export async function fetchOrderDetail(id: string): Promise<Order> {
  const { data, error } = await supabase.from('orders').select(ORDER_DETAIL_SELECT).eq('id', id).single();
  if (error) throw new Error(error.message);
  return mapOrder(data);
}

const AUDIT_LOG_SELECT =
  'id, order_id, action, old_status, new_status, notes, server_timestamp, ' +
  'performer:profiles!audit_log_performed_by_fkey(id, full_name, phone, role, is_approved, created_at)';

export async function fetchAuditLog(orderId: string): Promise<AuditLogEntry[]> {
  const { data, error } = await supabase
    .from('audit_log')
    .select(AUDIT_LOG_SELECT)
    .eq('order_id', orderId)
    .order('server_timestamp', { ascending: true });
  if (error) throw new Error(error.message);
  return (data ?? []).map(mapAuditLogEntry);
}

const DELIVERY_RECEIPT_SELECT =
  'id, order_id, pdf_url, notes, delivered_at, created_at, ' +
  'rep:profiles!delivery_receipts_rep_id_fkey(id, full_name, phone, role, is_approved, created_at), ' +
  'delivery_receipt_items(id, item_name_snapshot, unit_snapshot, quantity_delivered)';

export async function fetchDeliveryReceipts(orderId: string): Promise<DeliveryReceipt[]> {
  const { data, error } = await supabase
    .from('delivery_receipts')
    .select(DELIVERY_RECEIPT_SELECT)
    .eq('order_id', orderId)
    .order('created_at', { ascending: false });
  if (error) throw new Error(error.message);
  return (data ?? []).map(mapDeliveryReceipt);
}
