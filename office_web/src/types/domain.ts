export type OrderDirection = 'outbound' | 'inbound_rep' | 'inbound_external';
export type OrderStatus = 'assigned' | 'picked_up' | 'on_the_move' | 'delivered' | 'delivered_to_storage';
export type ItemCheckStatus = 'pending' | 'checked' | 'rejected';
export type UserRole = 'verifier' | 'rep' | 'storage_actor' | 'manager' | 'admin';

export const orderDirectionLabel: Record<OrderDirection, string> = {
  outbound: 'توريد',
  inbound_rep: 'مشتريات مندوب داخلي',
  inbound_external: 'مشتريات مندوب خارجي',
};

export const orderStatusLabel: Record<OrderStatus, string> = {
  assigned: 'معين',
  picked_up: 'تم الاستلام',
  on_the_move: 'في الطريق',
  delivered: 'تم التسليم',
  delivered_to_storage: 'تم الاستلام في المخزن',
};

export const userRoleLabel: Record<UserRole, string> = {
  verifier: 'مشرف',
  rep: 'مندوب',
  storage_actor: 'أمين مخزن',
  manager: 'مدير',
  admin: 'مسؤول',
};

export interface Profile {
  id: string;
  fullName: string;
  phone: string | null;
  role: UserRole | null;
  isApproved: boolean;
}

export interface Entity {
  id: string;
  name: string;
  category: string;
  contactName: string | null;
  contactPhone: string | null;
  address: string | null;
}

export interface OrderItem {
  id: string;
  orderId: string;
  inventoryId: string | null;
  inventoryName: string | null;
  quantity: number;
  finalQuantity: number | null;
  isCustom: boolean;
  customDescription: string | null;
  sourceInventoryId: string | null;
  purchasedAt: string | null;
  checkStatus: ItemCheckStatus;
  checkedBy: string | null;
  checkedAt: string | null;
  checker: Profile | null;
  wasUnavailableAtCreation: boolean;
}

export interface Order {
  id: string;
  referenceCode: string | null;
  direction: OrderDirection;
  entityId: string;
  entity: Entity | null;
  repId: string | null;
  rep: Profile | null;
  creator: Profile | null;
  status: OrderStatus;
  notes: string | null;
  storageActorId: string | null;
  createdAt: string | null;
  assignedAt: string | null;
  pickedUpAt: string | null;
  moveStartedAt: string | null;
  deliveredAt: string | null;
  items: OrderItem[];
}

export interface AuditLogEntry {
  id: string;
  orderId: string;
  action: string;
  oldStatus: OrderStatus | null;
  newStatus: OrderStatus | null;
  performer: Profile | null;
  notes: string | null;
  serverTimestamp: string | null;
}

export interface DeliveryReceiptItem {
  id: string;
  itemNameSnapshot: string;
  unitSnapshot: string;
  quantityDelivered: number;
}

export interface DeliveryReceipt {
  id: string;
  orderId: string | null;
  rep: Profile | null;
  deliveredAt: string | null;
  pdfUrl: string | null;
  notes: string | null;
  createdAt: string | null;
  items: DeliveryReceiptItem[];
}
