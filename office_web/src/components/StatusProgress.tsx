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
        const color = orderStatusColor[step.status].text;
        const isLast = i === steps.length - 1;
        return (
          <div key={step.status} className="flex-1 flex flex-col items-center min-w-0">
            <div className="flex items-center w-full">
              <div
                className="w-6 h-6 shrink-0 rounded-full flex items-center justify-center text-white text-xs font-bold"
                style={{ backgroundColor: reached ? color : '#CBD5E1' }}
              >
                {reached && '✓'}
              </div>
              {!isLast && (
                <div
                  className="flex-1 h-0.5"
                  style={{ backgroundColor: i < currentIndex ? color : '#CBD5E1' }}
                />
              )}
            </div>
            <span
              className="text-xs mt-1 text-center truncate w-full"
              style={{ color: reached ? color : '#94A3B8', fontWeight: reached ? 600 : 400 }}
            >
              {step.label}
            </span>
          </div>
        );
      })}
    </div>
  );
}
