import { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { Shell } from '../components/Shell';
import { OrdersToolbar } from '../components/OrdersToolbar';
import { OrdersTable } from '../components/OrdersTable';
import { OrderDetailPanel } from '../components/OrderDetailPanel';
import { StatesPanel } from '../components/StatesPanel';
import { useOrders } from '../hooks/useOrders';
import { filterOrdersByQuery, filterOrdersByDirection, sortOrders, groupOrders } from '../lib/orderFilters';
import type { SortMode, DirectionFilter, GroupMode } from '../lib/orderFilters';
import type { Order } from '../types/domain';

const DONE_STATUSES = new Set<Order['status']>(['delivered', 'delivered_to_storage']);

export default function Orders() {
  const { orderId } = useParams();
  const navigate = useNavigate();
  const { data: orders, isLoading, isError, error, refetch } = useOrders();

  const [search, setSearch] = useState('');
  const [sortMode, setSortMode] = useState<SortMode>('most_recent');
  const [directionFilter, setDirectionFilter] = useState<DirectionFilter>('all');
  const [groupMode, setGroupMode] = useState<GroupMode | null>(null);
  const [activeTab, setActiveTab] = useState<'active' | 'completed'>('active');

  if (isLoading) {
    return (
      <Shell searchValue={search} onSearchChange={setSearch}>
        <StatesPanel kind="loading" />
      </Shell>
    );
  }

  if (isError) {
    return (
      <Shell searchValue={search} onSearchChange={setSearch}>
        <StatesPanel kind="error" message={(error as Error)?.message} onRetry={() => refetch()} />
      </Shell>
    );
  }

  const byTab = (orders ?? []).filter((o) => (activeTab === 'active' ? !DONE_STATUSES.has(o.status) : DONE_STATUSES.has(o.status)));
  const prepared = filterOrdersByDirection(filterOrdersByQuery(byTab, search), directionFilter);
  const groups = groupMode ? groupOrders(prepared, groupMode, sortMode) : null;
  const visible = groups ? null : sortOrders(prepared, sortMode);

  return (
    <Shell searchValue={search} onSearchChange={setSearch}>
      <div className="h-full flex">
        <div className="flex-1 min-w-0 flex flex-col">
          <OrdersToolbar
            sortMode={sortMode}
            directionFilter={directionFilter}
            groupMode={groupMode}
            activeTab={activeTab}
            onSortModeChange={setSortMode}
            onDirectionFilterChange={setDirectionFilter}
            onGroupModeChange={setGroupMode}
            onTabChange={setActiveTab}
          />
          <div className="flex-1 overflow-auto">
            {groups ? (
              groups.map((group) => (
                <section key={group.key} className="mb-2">
                  <h2 className="sticky top-0 z-10 bg-surface-inset px-3 h-9 flex items-center text-sm font-semibold text-text-high border-b border-border-subtle">
                    {group.label} — {group.orders.length} طلبات
                  </h2>
                  <OrdersTable orders={group.orders} selectedId={orderId ?? null} onSelect={(id) => navigate(`/orders/${id}`)} />
                </section>
              ))
            ) : (
              <OrdersTable orders={visible ?? []} selectedId={orderId ?? null} onSelect={(id) => navigate(`/orders/${id}`)} />
            )}
          </div>
        </div>
        {orderId && <OrderDetailPanel orderId={orderId} onClose={() => navigate('/orders')} />}
      </div>
    </Shell>
  );
}
