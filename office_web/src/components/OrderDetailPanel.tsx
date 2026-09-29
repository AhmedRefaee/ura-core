import { useRef, useState, type PointerEvent as ReactPointerEvent } from 'react';
import { Link } from 'react-router-dom';
import { OrderDetailContent } from './OrderDetailContent';

const MIN_WIDTH = 420;
const MAX_WIDTH = 900;
const DEFAULT_WIDTH = 560;
const STORAGE_KEY = 'ura.orderDetailPanel.width';

function clampWidth(width: number): number {
  return Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, width));
}

function readStoredWidth(): number {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    const parsed = raw ? Number(raw) : NaN;
    return Number.isFinite(parsed) ? clampWidth(parsed) : DEFAULT_WIDTH;
  } catch {
    return DEFAULT_WIDTH;
  }
}

export function OrderDetailPanel({ orderId, onClose }: { orderId: string; onClose: () => void }) {
  const [width, setWidth] = useState(readStoredWidth);
  const draggingRef = useRef(false);
  const startXRef = useRef(0);
  const startWidthRef = useRef(0);

  const handlePointerDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    draggingRef.current = true;
    startXRef.current = e.clientX;
    startWidthRef.current = width;
    e.currentTarget.setPointerCapture(e.pointerId);
  };

  const handlePointerMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (!draggingRef.current) return;
    // The panel's left edge is pinned to the window edge, so its right edge
    // -- where this handle sits -- has to move right to grow the panel and
    // left to shrink it. That's a plain, non-inverted delta.
    setWidth(clampWidth(startWidthRef.current + (e.clientX - startXRef.current)));
  };

  const handlePointerUp = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (!draggingRef.current) return;
    draggingRef.current = false;
    e.currentTarget.releasePointerCapture(e.pointerId);
    const finalWidth = clampWidth(startWidthRef.current + (e.clientX - startXRef.current));
    setWidth(finalWidth);
    try {
      localStorage.setItem(STORAGE_KEY, String(finalWidth));
    } catch {
      // best-effort persistence only -- a failed write just means the width
      // resets to default next time, not worth surfacing to the user.
    }
  };

  return (
    <div className="flex shrink-0" style={{ width }} data-testid="order-detail-panel">
      <div
        role="separator"
        aria-orientation="vertical"
        aria-label="تغيير حجم اللوحة"
        data-testid="panel-resize-handle"
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        className="w-1.5 shrink-0 cursor-col-resize bg-transparent hover:bg-primary/30 active:bg-primary/50 transition-colors"
      />
      <div className="flex-1 min-w-0 border-r border-border-subtle bg-surface-card overflow-y-auto">
        <OrderDetailContent
          orderId={orderId}
          stepperOrientation="vertical"
          headerActions={
            <div className="flex items-center gap-3">
              <Link
                to={`/order/${orderId}`}
                target="_blank"
                rel="noreferrer"
                title="فتح في صفحة مستقلة"
                className="text-text-low hover:text-text-high"
              >
                ↗
              </Link>
              <button type="button" onClick={onClose} className="text-text-low hover:text-text-high">✕</button>
            </div>
          }
        />
      </div>
    </div>
  );
}
