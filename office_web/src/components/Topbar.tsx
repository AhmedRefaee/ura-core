interface TopbarProps {
  userName: string;
  searchValue: string;
  onSearchChange: (value: string) => void;
  onLogout: () => void;
}

export function Topbar({ userName, searchValue, onSearchChange, onLogout }: TopbarProps) {
  return (
    <header className="h-14 shrink-0 bg-surface-card border-b border-border-subtle flex items-center px-4 gap-4">
      <input
        type="text"
        value={searchValue}
        onChange={(e) => onSearchChange(e.target.value)}
        placeholder="بحث شامل في الطلبات..."
        className="w-80 h-9 px-3 rounded-input border border-border-subtle focus:border-primary focus:outline-none text-sm"
      />
      <div className="flex-1" />
      <span className="text-sm text-text-medium">{userName}</span>
      <button
        type="button"
        onClick={onLogout}
        className="text-sm text-text-low hover:text-error"
      >
        تسجيل الخروج
      </button>
    </header>
  );
}
