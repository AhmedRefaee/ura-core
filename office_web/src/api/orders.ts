import { supabase } from '../lib/supabase';
import { mapOrder } from '../lib/mappers';
import type { Order } from '../types/domain';

// Mirrors OrderRepository._orderSelect in lib/features/verifier/data/order_repository.dart
export const ORDER_SELECT =
  '*, ' +
  'entity:entities(*), ' +
  'rep:profiles!orders_rep_id_fkey(id, full_name, role, is_approved, phone, created_at), ' +
  'creator:profiles!orders_created_by_fkey(id, full_name, role, is_approved, phone, created_at), ' +
  'order_items(*, inventory:inventory!order_items_inventory_id_fkey(id, item_name))';

export async function fetchOrders(): Promise<Order[]> {
  const { data, error } = await supabase.from('orders').select(ORDER_SELECT).order('created_at', { ascending: false });
  if (error) throw new Error(error.message);
  return (data ?? []).map(mapOrder);
}
