import { Link } from 'react-router-dom';
import { OrderDetailContent } from './OrderDetailContent';

export function OrderDetailPanel({ orderId, onClose }: { orderId: string; onClose: () => void }) {
  return (
    <div className="w-[560px] shrink-0 border-r border-border-subtle bg-surface-card overflow-y-auto">
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
  );
}
