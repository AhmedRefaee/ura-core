import type { ReactNode } from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';
import { useProfile } from '../hooks/useProfile';

export function ProtectedRoute({ children }: { children: ReactNode }) {
  const { session, loading: authLoading } = useAuth();
  const { data: profile, isLoading: profileLoading } = useProfile();

  if (authLoading || (session && profileLoading)) {
    return <div className="min-h-screen flex items-center justify-center text-text-low">جارٍ التحميل...</div>;
  }

  if (!session) return <Navigate to="/login" replace />;

  if (profile?.role !== 'verifier' || !profile.isApproved) {
    return (
      <div className="min-h-screen flex items-center justify-center text-center px-6">
        <p className="text-text-medium">هذا النظام غير متاح حالياً لدورك في المنظومة.</p>
      </div>
    );
  }

  return <>{children}</>;
}
