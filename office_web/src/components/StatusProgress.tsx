import type { StatusStep } from '../lib/statusSteps';
import { orderStatusColor } from '../lib/statusColors';

interface StatusProgressProps {
  steps: StatusStep[];
  currentIndex: number;
}

export function StatusProgress({ steps, currentIndex }: StatusProgressProps) {
  return (
    <div className="flex items-start">
      {steps.map((step, i) => {
        const reached = i <= currentIndex;
        const solidColor = orderStatusColor[step.status].solid;
        const labelColor = orderStatusColor[step.status].text;
        const isLast = i === steps.length - 1;
        return (
          // The circle+label column is its own fixed-width unit (shrink-0),
          // separate from the connector line — the line must not share a
          // flex box with the label, or the label centers under the line's
          // width too and drifts off the circle it belongs to.
          <div key={step.status} className={`flex items-start ${isLast ? 'flex-none' : 'flex-1'}`}>
            <div className="flex flex-col items-center shrink-0">
              <div
                className="w-9 h-9 shrink-0 rounded-full flex items-center justify-center text-white text-sm font-bold border-2 border-surface-card shadow-sm"
                style={{ backgroundColor: reached ? solidColor : '#E2E8F0' }}
              >
                {reached && '✓'}
              </div>
              <span
                className="text-xs mt-2 text-center whitespace-nowrap"
                style={{ color: reached ? labelColor : '#94A3B8', fontWeight: reached ? 600 : 400 }}
              >
                {step.label}
              </span>
            </div>
            {!isLast && (
              // mt-4 (16px) + half the line's own height (2px) = 18px,
              // matching the circle's own vertical center (36px / 2).
              <div
                className="flex-1 h-1 rounded-full mt-4"
                style={{ backgroundColor: i < currentIndex ? solidColor : '#E2E8F0' }}
              />
            )}
          </div>
        );
      })}
    </div>
  );
}
