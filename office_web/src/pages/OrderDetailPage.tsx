import { useState } from 'react';
import { Link, Navigate, useParams } from 'react-router-dom';
import { Shell } from '../components/Shell';
import { OrderDetailContent } from '../components/OrderDetailContent';

export default function OrderDetailPage() {
  const { orderId } = useParams<{ orderId: string }>();
  const [search, setSearch] = useState('');

  if (!orderId) return <Navigate to="/orders" replace />;

  return (
    <Shell searchValue={search} onSearchChange={setSearch}>
      <div className="h-full overflow-y-auto">
        <div className="max-w-4xl mx-auto min-h-full bg-surface-card border-x border-border-subtle">
          <OrderDetailContent
            orderId={orderId}
            headerActions={
              <Link to="/orders" className="text-sm text-primary hover:underline">
                العودة إلى الطلبات
              </Link>
            }
          />
        </div>
      </div>
    </Shell>
  );
}
