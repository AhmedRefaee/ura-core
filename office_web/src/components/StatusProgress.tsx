import type { StatusStep } from '../lib/statusSteps';
import type { StepTimelineEntry } from '../lib/stepTimeline';
import type { AuditLogEntry, OrderStatus } from '../types/domain';
import { userRoleLabel } from '../types/domain';
import { orderStatusColor } from '../lib/statusColors';
import { formatDateTime } from '../lib/formatDate';

interface StatusProgressProps {
  steps: StatusStep[];
  currentIndex: number;
  stepTimeline: StepTimelineEntry[];
  hoveredStatus: OrderStatus | null;
  onHoverStatus: (status: OrderStatus | null) => void;
  // Horizontal suits the full-width page; vertical suits the narrow side
  // panel. Same data either way -- time, duration, who acted -- just laid
  // out to fit the space available.
  orientation?: 'horizontal' | 'vertical';
}

function performerLabel(entry: AuditLogEntry | null | undefined): string | null {
  const performer = entry?.performer;
  if (!performer) return null;
  return performer.role ? `${userRoleLabel[performer.role]} · ${performer.fullName}` : performer.fullName;
}

export function StatusProgress({ steps, currentIndex, stepTimeline, hoveredStatus, onHoverStatus, orientation = 'horizontal' }: StatusProgressProps) {
  const rows = steps.map((step, i) => {
    const timelineEntry = stepTimeline.find((s) => s.status === step.status) ?? null;
    return {
      step,
      i,
      reached: i <= currentIndex,
      isCurrent: i === currentIndex,
      isHovered: hoveredStatus === step.status,
      isLast: i === steps.length - 1,
      solidColor: orderStatusColor[step.status].solid,
      labelColor: orderStatusColor[step.status].text,
      timelineEntry,
      time: timelineEntry?.entry?.serverTimestamp ? formatDateTime(timelineEntry.entry.serverTimestamp) : null,
      performer: performerLabel(timelineEntry?.entry),
    };
  });

  if (orientation === 'vertical') {
    return (
      <div className="flex flex-col">
        {rows.map(({ step, i, reached, isCurrent, isHovered, isLast, solidColor, labelColor, timelineEntry, time, performer }) => (
          <div key={step.status} className="flex items-stretch gap-7">
            <div className="flex flex-col items-center shrink-0">
              <div
                data-testid={`status-step-${step.status}`}
                className="relative shrink-0"
                onMouseEnter={() => onHoverStatus(step.status)}
                onMouseLeave={() => onHoverStatus(null)}
              >
                {isCurrent && (
                  <span
                    className="absolute inset-0 rounded-full motion-safe:animate-pulse"
                    style={{ backgroundColor: solidColor, opacity: 0.35 }}
                    aria-hidden="true"
                  />
                )}
                <div
                  className="relative w-8 h-8 shrink-0 rounded-full flex items-center justify-center text-white text-xs font-bold border-2 border-surface-card shadow-sm cursor-default transition-transform duration-150 ease-out"
                  style={{
                    backgroundColor: reached ? solidColor : '#E2E8F0',
                    transform: isHovered ? 'scale(1.08)' : 'scale(1)',
                  }}
                >
                  {reached && '✓'}
                </div>
              </div>
              {!isLast && (
                <div className="relative flex-1 min-h-[28px] w-1 my-0.5">
                  <div
                    className="absolute inset-y-0 left-1/2 -translate-x-1/2 w-1 -z-10 rounded-full transition-colors duration-150 ease-out"
                    style={{ backgroundColor: i < currentIndex ? solidColor : '#E2E8F0' }}
                  />
                  {timelineEntry?.duration && (
                    // Centered by transform, not text-align, so it lands on
                    // the line regardless of RTL -- the column itself is
                    // only 4px wide and can't center overflowing text on
                    // its own.
                    <span className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 whitespace-nowrap bg-surface-card px-1 text-[10px] leading-none text-text-low">
                      {timelineEntry.duration}
                    </span>
                  )}
                </div>
              )}
            </div>
            <div className={`min-w-0 ${isLast ? 'pb-1' : 'pb-3'}`}>
              {performer && <p className="text-[11px] text-text-low truncate">{performer}</p>}
              <p
                className="text-sm transition-colors duration-150 ease-out"
                style={{ color: reached ? labelColor : '#94A3B8', fontWeight: reached ? 600 : 400 }}
              >
                {step.label}
              </p>
              {time && <p className="text-[11px] text-text-low">{time}</p>}
            </div>
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className="flex items-start">
      {rows.map(({ step, i, reached, isCurrent, isHovered, isLast, solidColor, labelColor, timelineEntry, time, performer }) => (
        <div key={step.status} className={`flex items-start ${isLast ? 'flex-none' : 'flex-1'}`}>
          <div className="flex flex-col items-center shrink-0">
            <span
              className="h-4 leading-4 max-w-[100px] text-[11px] text-text-low text-center truncate"
              title={performer ?? undefined}
            >
              {performer ?? ' '}
            </span>
            <div
              data-testid={`status-step-${step.status}`}
              className="relative mt-1"
              onMouseEnter={() => onHoverStatus(step.status)}
              onMouseLeave={() => onHoverStatus(null)}
            >
              {isCurrent && (
                <span
                  className="absolute inset-0 rounded-full motion-safe:animate-pulse"
                  style={{ backgroundColor: solidColor, opacity: 0.35 }}
                  aria-hidden="true"
                />
              )}
              <div
                className="relative w-9 h-9 shrink-0 rounded-full flex items-center justify-center text-white text-sm font-bold border-2 border-surface-card shadow-sm cursor-default transition-transform duration-150 ease-out"
                style={{
                  backgroundColor: reached ? solidColor : '#E2E8F0',
                  transform: isHovered ? 'scale(1.08)' : 'scale(1)',
                }}
              >
                {reached && '✓'}
              </div>
            </div>
            <span className="mt-1.5 max-w-[100px] text-[11px] text-text-low text-center truncate">{time ?? ' '}</span>
            <span
              className="text-xs mt-1 text-center whitespace-nowrap transition-colors duration-150 ease-out"
              style={{ color: reached ? labelColor : '#94A3B8', fontWeight: reached ? 600 : 400 }}
            >
              {step.label}
            </span>
          </div>
          {!isLast && (
            // mt-9 (36px) = performer row (16px) + its mt-1 (4px) + half the
            // circle (18px) - half the line's own height (2px), so the line
            // lands on the circle's vertical center regardless of what text
            // surrounds it above and below.
            <div className="flex-1 flex items-center gap-1 mt-9">
              <div
                className="flex-1 h-1 rounded-full transition-colors duration-150 ease-out"
                style={{ backgroundColor: i < currentIndex ? solidColor : '#E2E8F0' }}
              />
              {timelineEntry?.duration && (
                <span className="shrink-0 text-[10px] text-text-low whitespace-nowrap">{timelineEntry.duration}</span>
              )}
              <div
                className="flex-1 h-1 rounded-full transition-colors duration-150 ease-out"
                style={{ backgroundColor: i < currentIndex ? solidColor : '#E2E8F0' }}
              />
            </div>
          )}
        </div>
      ))}
    </div>
  );
}
