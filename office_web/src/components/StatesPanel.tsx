interface StatesPanelProps {
  kind: 'loading' | 'error';
  message?: string;
  onRetry?: () => void;
}

export function StatesPanel({ kind, message, onRetry }: StatesPanelProps) {
  if (kind === 'loading') {
    return <div className="p-8 text-center text-text-low">جارٍ التحميل...</div>;
  }
  return (
    <div className="p-8 text-center">
      <p className="text-error mb-3">{message ?? 'حدث خطأ غير متوقع'}</p>
      {onRetry && (
        <button type="button" onClick={onRetry} className="px-4 py-1.5 rounded-button border border-border-subtle text-sm">
          إعادة المحاولة
        </button>
      )}
    </div>
  );
}
