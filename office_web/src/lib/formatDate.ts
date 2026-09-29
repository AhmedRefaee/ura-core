export function formatDate(iso: string | null): string {
  return iso ? new Date(iso).toLocaleString('ar') : '—';
}

// Includes seconds, unlike formatDate -- the real audit_log data pairs two
// rows at the exact same minute (see auditLogView.ts), so anywhere two
// entries could legitimately be seconds apart needs this, not formatDate,
// or they'd display as identical timestamps.
export function formatDateTime(iso: string | null): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('ar', {
    year: 'numeric', month: 'numeric', day: 'numeric',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
}
