import type { ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { Sidebar } from './Sidebar';
import { Topbar } from './Topbar';
import { useProfile } from '../hooks/useProfile';
import { signOut } from '../hooks/useAuth';

interface ShellProps {
  children: ReactNode;
  searchValue: string;
  onSearchChange: (value: string) => void;
}

export function Shell({ children, searchValue, onSearchChange }: ShellProps) {
  const { data: profile } = useProfile();
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  async function handleLogout() {
    // Clear all cached query data (orders, profile, order detail, ...) so a
    // second user signing in right after on a shared tab never briefly sees
    // the previous user's cached data before the refetch completes.
    queryClient.clear();
    await signOut();
    navigate('/login');
  }

  return (
    <div className="h-screen flex">
      <Sidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <Topbar
          userName={profile?.fullName ?? ''}
          searchValue={searchValue}
          onSearchChange={onSearchChange}
          onLogout={handleLogout}
        />
        <main className="flex-1 min-h-0 overflow-hidden">{children}</main>
      </div>
    </div>
  );
}
