import type { ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
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

  async function handleLogout() {
    await signOut();
    navigate('/login');
  }

  return (
    <div className="h-screen flex flex-row-reverse">
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
