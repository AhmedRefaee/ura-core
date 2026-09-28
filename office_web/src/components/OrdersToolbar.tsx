import type { SortMode, DirectionFilter, GroupMode } from '../lib/orderFilters';

interface OrdersToolbarProps {
  sortMode: SortMode;
  directionFilter: DirectionFilter;
  groupMode: GroupMode | null;
  activeTab: 'active' | 'completed';
  onSortModeChange: (mode: SortMode) => void;
  onDirectionFilterChange: (filter: DirectionFilter) => void;
  onGroupModeChange: (mode: GroupMode | null) => void;
  onTabChange: (tab: 'active' | 'completed') => void;
}

export function OrdersToolbar({
  sortMode, directionFilter, groupMode, activeTab,
  onSortModeChange, onDirectionFilterChange, onGroupModeChange, onTabChange,
}: OrdersToolbarProps) {
  return (
    <div className="flex items-center gap-3 px-4 py-2 border-b border-border-subtle bg-surface-card">
      <div className="flex rounded-button overflow-hidden border border-border-subtle">
        <button
          type="button"
          onClick={() => onTabChange('active')}
          className={`px-3 py-1.5 text-sm ${activeTab === 'active' ? 'bg-primary-fill text-white' : 'text-text-medium'}`}
        >
          نشطة
        </button>
        <button
          type="button"
          onClick={() => onTabChange('completed')}
          className={`px-3 py-1.5 text-sm ${activeTab === 'completed' ? 'bg-primary-fill text-white' : 'text-text-medium'}`}
        >
          مكتملة
        </button>
      </div>

      <label className="text-sm text-text-low" htmlFor="direction-filter">نوع العملية</label>
      <select
        id="direction-filter"
        value={directionFilter}
        onChange={(e) => onDirectionFilterChange(e.target.value as DirectionFilter)}
        className="h-8 px-2 rounded-input border border-border-subtle text-sm"
      >
        <option value="all">الكل</option>
        <option value="outbound">توريد</option>
        <option value="inbound_rep">مشتريات مندوب داخلي</option>
        <option value="inbound_external">مشتريات مندوب خارجي</option>
      </select>

      <label className="text-sm text-text-low" htmlFor="sort-mode">الترتيب</label>
      <select
        id="sort-mode"
        value={sortMode}
        onChange={(e) => onSortModeChange(e.target.value as SortMode)}
        className="h-8 px-2 rounded-input border border-border-subtle text-sm"
      >
        <option value="most_recent">الأحدث</option>
        <option value="oldest">الأقدم</option>
        <option value="frequent">الأكثر تكراراً</option>
      </select>

      <label className="text-sm text-text-low" htmlFor="group-mode">التجميع</label>
      <select
        id="group-mode"
        value={groupMode ?? ''}
        onChange={(e) => onGroupModeChange(e.target.value ? (e.target.value as GroupMode) : null)}
        className="h-8 px-2 rounded-input border border-border-subtle text-sm"
      >
        <option value="">بلا</option>
        <option value="entity">حسب الجهة</option>
        <option value="rep">حسب المندوب</option>
      </select>
    </div>
  );
}
