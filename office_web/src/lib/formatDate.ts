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

// Time only, with seconds -- for the stepper and the timeline, which show
// one entry per row/step and repeat often enough that spelling out the full
// date every time is just noise once the date is shown once, up top. Never
// truncate this in the UI: the exact second is the entire point of these
// two views.
export function formatTime(iso: string | null): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('ar', {
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
}

// Date only, no time -- for the one place it needs to appear per order
// (the detail header), since every step/row below it already gives its own
// time via formatTime.
export function formatDateOnly(iso: string | null): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('ar', {
    year: 'numeric', month: 'numeric', day: 'numeric',
  });
}
