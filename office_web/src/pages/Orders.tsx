import { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { Shell } from '../components/Shell';
import { OrdersToolbar } from '../components/OrdersToolbar';
import { OrdersTable } from '../components/OrdersTable';
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
  const visible = groupMode ? groupOrders(prepared, groupMode, sortMode).flatMap((g) => g.orders) : sortOrders(prepared, sortMode);

  return (
    <Shell searchValue={search} onSearchChange={setSearch}>
      <div className="h-full flex flex-row-reverse">
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
            <OrdersTable orders={visible} selectedId={orderId ?? null} onSelect={(id) => navigate(`/orders/${id}`)} />
          </div>
        </div>
      </div>
    </Shell>
  );
}
