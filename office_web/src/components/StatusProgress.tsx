import type { StatusStep } from '../lib/statusSteps';
import type { StepTimelineEntry } from '../lib/stepTimeline';
import type { OrderStatus } from '../types/domain';
import { orderStatusColor } from '../lib/statusColors';
import { formatDateTime } from '../lib/formatDate';

interface StatusProgressProps {
  steps: StatusStep[];
  currentIndex: number;
  stepTimeline: StepTimelineEntry[];
  hoveredStatus: OrderStatus | null;
  onHoverStatus: (status: OrderStatus | null) => void;
}

export function StatusProgress({ steps, currentIndex, stepTimeline, hoveredStatus, onHoverStatus }: StatusProgressProps) {
  return (
    <div className="flex items-start">
      {steps.map((step, i) => {
        const reached = i <= currentIndex;
        const isCurrent = i === currentIndex;
        const isHovered = hoveredStatus === step.status;
        const solidColor = orderStatusColor[step.status].solid;
        const labelColor = orderStatusColor[step.status].text;
        const isLast = i === steps.length - 1;
        const timelineEntry = stepTimeline.find((s) => s.status === step.status);

        return (
          <div key={step.status} className={`flex items-start ${isLast ? 'flex-none' : 'flex-1'}`}>
            <div className="flex flex-col items-center shrink-0">
              <div
                data-testid={`status-step-${step.status}`}
                className="relative"
                onMouseEnter={() => onHoverStatus(step.status)}
                onMouseLeave={() => onHoverStatus(null)}
              >
                {/* Ambient "in progress" cue on the current step only — a calm
                    pulse, not the flashier animate-ping, to match a
                    professional dashboard's mood. motion-safe: respects
                    prefers-reduced-motion automatically. */}
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

                {/* Tooltip: always mounted, opacity/scale-driven so it can
                    transition on both enter and exit (a conditionally-mounted
                    element can't animate its own exit). Scales from the
                    circle it belongs to, not from the viewport center. */}
                {timelineEntry?.entry && (
                  <div
                    role="tooltip"
                    className="absolute top-full mt-2 left-1/2 z-10 whitespace-nowrap rounded-input bg-text-high px-2 py-1 text-xs text-white shadow-lg transition-[opacity,transform] duration-150 ease-out"
                    style={{
                      transform: `translateX(-50%) scale(${isHovered ? 1 : 0.95})`,
                      opacity: isHovered ? 1 : 0,
                      pointerEvents: 'none',
                      transformOrigin: 'top center',
                    }}
                  >
                    <div>{formatDateTime(timelineEntry.entry.serverTimestamp)}</div>
                    {timelineEntry.duration && (
                      <div className="text-white/70">
                        المدة: <span>{timelineEntry.duration}</span>
                      </div>
                    )}
                  </div>
                )}
              </div>
              <span
                className="text-xs mt-2 text-center whitespace-nowrap transition-colors duration-150 ease-out"
                style={{ color: reached ? labelColor : '#94A3B8', fontWeight: reached ? 600 : 400 }}
              >
                {step.label}
              </span>
            </div>
            {!isLast && (
              // mt-4 (16px) + half the line's own height (2px) = 18px,
              // matching the circle's own vertical center (36px / 2).
              <div
                className="flex-1 h-1 rounded-full mt-4 transition-colors duration-150 ease-out"
                style={{ backgroundColor: i < currentIndex ? solidColor : '#E2E8F0' }}
              />
            )}
          </div>
        );
      })}
    </div>
  );
}
