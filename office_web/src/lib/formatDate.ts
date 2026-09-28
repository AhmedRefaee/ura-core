export function formatDate(iso: string | null): string {
  return iso ? new Date(iso).toLocaleString('ar') : '—';
}
