import type { AuditLogEntry, OrderStatus } from '../types/domain';

// order_created rows carry newStatus: null in the real data (verified
// against the live API) even though they represent the order's initial
// "assigned" state -- everything that matches/colors by status needs this,
// not just the label.
export function effectiveStatus(entry: AuditLogEntry): OrderStatus | null {
  if (entry.action === 'order_created') return 'assigned';
  return entry.newStatus;
}

// The real backend writes two audit_log rows per transition -- a generic
// `status_change` and a specific one (`storage_pickup`, `start_move`,
// `mark_delivered`, ...) -- at the exact same server_timestamp. Verified
// directly against the live API response for a real order. Collapse each
// same-instant pair to one row, and drop rows that aren't a status
// transition at all (no effective status -- e.g. an item-level toggle),
// since this list is specifically the order's status history.
export function prepareAuditLogForDisplay(auditLog: AuditLogEntry[]): AuditLogEntry[] {
  const kept = new Map<string, AuditLogEntry>();
  for (const entry of auditLog) {
    const status = effectiveStatus(entry);
    if (status === null) continue;
    const key = `${entry.serverTimestamp}|${status}`;
    const existing = kept.get(key);
    if (!existing) {
      kept.set(key, entry);
    } else if (existing.locationLat == null && entry.locationLat != null) {
      // Only the RPC's own row records where the rep was; the trigger's generic
      // `status_change` row never does. Whichever of the pair comes first, the
      // surviving row must carry the location.
      kept.set(key, { ...existing, locationLat: entry.locationLat, locationLng: entry.locationLng });
    }
  }
  return [...kept.values()];
}
