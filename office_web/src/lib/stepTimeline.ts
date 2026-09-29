import type { AuditLogEntry, OrderStatus } from '../types/domain';
import type { StatusStep } from './statusSteps';
import { durationBetween } from './duration';
import { effectiveStatus } from './auditLogView';

export interface StepTimelineEntry {
  status: OrderStatus;
  entry: AuditLogEntry | null;
  // Time spent in this step: the gap to the next chronological audit log
  // row, mirroring exactly how AuditTimeline computes its own per-row
  // duration badges, so the two views can never disagree on the numbers.
  duration: string | null;
}

// Pass the already-deduped/filtered list from auditLogView.prepareAuditLogForDisplay
// -- matching against the raw list would pair a step with the first half of
// a same-instant duplicate row and report ~0 duration to its own twin.
export function buildStepTimeline(steps: StatusStep[], auditLog: AuditLogEntry[]): StepTimelineEntry[] {
  return steps.map((step) => {
    const index = auditLog.findIndex((e) => effectiveStatus(e) === step.status);
    if (index === -1) return { status: step.status, entry: null, duration: null };
    const entry = auditLog[index];
    const next = auditLog[index + 1];
    const duration = next ? durationBetween(entry.serverTimestamp, next.serverTimestamp) : null;
    return { status: step.status, entry, duration };
  });
}
