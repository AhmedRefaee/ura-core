import { Link } from 'react-router-dom';

const comingSoon = [
  { key: 'inventory', label: 'المخزون' },
  { key: 'reps', label: 'المناديب' },
  { key: 'stats', label: 'الإحصائيات' },
  { key: 'settings', label: 'الإعدادات' },
];

export function Sidebar() {
  return (
    <aside className="w-64 shrink-0 bg-surface-card border-l border-border-subtle flex flex-col py-4">
      <div className="px-4 mb-6">
        <p className="font-semibold text-text-high">روح النمو المتحدة</p>
        <p className="text-xs text-text-low">منظومة العمليات</p>
      </div>
      <nav className="flex-1 px-2 space-y-1">
        <Link
          to="/orders"
          className="block px-3 py-2 rounded-button bg-primary-fill text-white font-medium"
        >
          الطلبات
        </Link>
        {comingSoon.map((item) => (
          <div
            key={item.key}
            className="flex items-center justify-between px-3 py-2 rounded-button text-text-low cursor-not-allowed"
          >
            <span>{item.label}</span>
            <span className="text-xs bg-surface-inset px-2 py-0.5 rounded-full">قريباً</span>
          </div>
        ))}
      </nav>
    </aside>
  );
}
