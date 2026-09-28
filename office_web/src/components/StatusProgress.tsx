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
          <div key={step.status} className="flex-1 flex flex-col items-center min-w-0">
            <div className="flex items-center w-full">
              <div
                className="w-9 h-9 shrink-0 rounded-full flex items-center justify-center text-white text-sm font-bold border-2 border-surface-card shadow-sm"
                style={{ backgroundColor: reached ? solidColor : '#E2E8F0' }}
              >
                {reached && '✓'}
              </div>
              {!isLast && (
                <div
                  className="flex-1 h-1 rounded-full"
                  style={{ backgroundColor: i < currentIndex ? solidColor : '#E2E8F0' }}
                />
              )}
            </div>
            <span
              className="text-xs mt-2 text-center truncate w-full"
              style={{ color: reached ? labelColor : '#94A3B8', fontWeight: reached ? 600 : 400 }}
            >
              {step.label}
            </span>
          </div>
        );
      })}
    </div>
  );
}
