import type {
  Profile, Entity, OrderItem, Order, AuditLogEntry, DeliveryReceipt,
  OrderStatus, OrderDirection, ItemCheckStatus, UserRole,
} from '../types/domain';

const VALID_STATUSES: OrderStatus[] = ['assigned', 'picked_up', 'on_the_move', 'delivered', 'delivered_to_storage'];
const VALID_DIRECTIONS: OrderDirection[] = ['outbound', 'inbound_rep', 'inbound_external'];
const VALID_CHECK_STATUSES: ItemCheckStatus[] = ['pending', 'checked', 'rejected'];
const VALID_ROLES: UserRole[] = ['verifier', 'rep', 'storage_actor', 'manager', 'admin'];

function asStatus(value: string | null): OrderStatus {
  return VALID_STATUSES.includes(value as OrderStatus) ? (value as OrderStatus) : 'assigned';
}

function asDirection(value: string): OrderDirection {
  return VALID_DIRECTIONS.includes(value as OrderDirection) ? (value as OrderDirection) : 'outbound';
}

function asCheckStatus(value: string | null): ItemCheckStatus {
  return VALID_CHECK_STATUSES.includes(value as ItemCheckStatus) ? (value as ItemCheckStatus) : 'pending';
}

function asRole(value: string | null): UserRole | null {
  return VALID_ROLES.includes(value as UserRole) ? (value as UserRole) : null;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function mapProfile(row: any): Profile {
  return {
    id: row.id,
    fullName: row.full_name,
    phone: row.phone ?? null,
    role: asRole(row.role ?? null),
    isApproved: row.is_approved ?? false,
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function mapEntity(row: any): Entity {
  return {
    id: row.id,
    name: row.name,
    category: row.category,
    contactName: row.contact_name ?? null,
    contactPhone: row.contact_phone ?? null,
    address: row.address ?? null,
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function mapOrderItem(row: any): OrderItem {
  return {
    id: row.id,
    orderId: row.order_id,
    inventoryId: row.inventory_id ?? null,
    inventoryName: row.inventory?.item_name ?? null,
    quantity: Number(row.quantity),
    finalQuantity: row.final_quantity != null ? Number(row.final_quantity) : null,
    isCustom: !!row.is_custom,
    customDescription: row.custom_description ?? null,
    sourceInventoryId: row.source_inventory_id ?? null,
    purchasedAt: row.purchased_at ?? null,
    checkStatus: asCheckStatus(row.check_status ?? null),
    checkedBy: row.checked_by ?? null,
    checkedAt: row.checked_at ?? null,
    checker: row.checker ? mapProfile(row.checker) : null,
    wasUnavailableAtCreation: !!row.was_unavailable_at_creation,
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function mapOrder(row: any): Order {
  return {
    id: row.id,
    referenceCode: row.reference_code ?? null,
    direction: asDirection(row.direction),
    entityId: row.entity_id,
    entity: row.entity ? mapEntity(row.entity) : null,
    repId: row.rep_id ?? null,
    rep: row.rep ? mapProfile(row.rep) : null,
    creator: row.creator ? mapProfile(row.creator) : null,
    status: asStatus(row.status),
    notes: row.notes ?? null,
    storageActorId: row.storage_actor_id ?? null,
    createdAt: row.created_at ?? null,
    assignedAt: row.assigned_at ?? null,
    pickedUpAt: row.picked_up_at ?? null,
    moveStartedAt: row.move_started_at ?? null,
    deliveredAt: row.delivered_at ?? null,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    items: (row.order_items ?? []).map((i: any) => mapOrderItem(i)),
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function mapAuditLogEntry(row: any): AuditLogEntry {
  return {
    id: row.id,
    orderId: row.order_id,
    action: row.action,
    oldStatus: row.old_status ? asStatus(row.old_status) : null,
    newStatus: row.new_status ? asStatus(row.new_status) : null,
    performer: row.performer ? mapProfile(row.performer) : null,
    notes: row.notes ?? null,
    serverTimestamp: row.server_timestamp ?? null,
    locationLat: row.location_lat != null ? Number(row.location_lat) : null,
    locationLng: row.location_lng != null ? Number(row.location_lng) : null,
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function mapDeliveryReceipt(row: any): DeliveryReceipt {
  return {
    id: row.id,
    orderId: row.order_id ?? null,
    rep: row.rep ? mapProfile(row.rep) : null,
    deliveredAt: row.delivered_at ?? null,
    pdfUrl: row.pdf_url ?? null,
    notes: row.notes ?? null,
    createdAt: row.created_at ?? null,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    items: (row.delivery_receipt_items ?? []).map((i: any) => ({
      id: i.id,
      itemNameSnapshot: i.item_name_snapshot,
      unitSnapshot: i.unit_snapshot,
      quantityDelivered: Number(i.quantity_delivered),
    })),
  };
}
