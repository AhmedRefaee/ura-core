import type { AuditLogEntry, OrderStatus } from '../types/domain';
import type { StatusStep } from './statusSteps';
import { durationBetween } from './duration';

export interface StepTimelineEntry {
  status: OrderStatus;
  entry: AuditLogEntry | null;
  // Time spent in this step: the gap to the next chronological audit log
  // row, mirroring exactly how AuditTimeline computes its own per-row
  // duration badges, so the two views can never disagree on the numbers.
  duration: string | null;
}

export function buildStepTimeline(steps: StatusStep[], auditLog: AuditLogEntry[]): StepTimelineEntry[] {
  return steps.map((step) => {
    const index = auditLog.findIndex((e) => e.newStatus === step.status);
    if (index === -1) return { status: step.status, entry: null, duration: null };
    const entry = auditLog[index];
    const next = auditLog[index + 1];
    const duration = next ? durationBetween(entry.serverTimestamp, next.serverTimestamp) : null;
    return { status: step.status, entry, duration };
  });
}
