import type { OrderStatus } from '../types/domain';

// Exact hex values from lib/core/design_system/theme/colors/order_status_colors.dart
// -- shared by StatusChip and StatusProgress so the website and the Flutter
// app agree on what each status looks like, and the two components agree
// with each other.
//
// `text` is deliberately darkened for on_the_move (#8A6D00, not the raw
// #FBC02D) so it stays legible as small text on a light background — that
// darkened value must NOT be used to fill a large shape (a stepper circle,
// a connecting line), which is what `solid` is for instead.
export const orderStatusColor: Record<OrderStatus, { bg: string; text: string; solid: string }> = {
  assigned: { bg: '#E5393520', text: '#E53935', solid: '#E53935' },
  picked_up: { bg: '#FB8C0020', text: '#FB8C00', solid: '#FB8C00' },
  on_the_move: { bg: '#FBC02D20', text: '#8A6D00', solid: '#FBC02D' },
  delivered: { bg: '#43A04720', text: '#2E7D32', solid: '#43A047' },
  delivered_to_storage: { bg: '#43A04720', text: '#2E7D32', solid: '#43A047' },
};
