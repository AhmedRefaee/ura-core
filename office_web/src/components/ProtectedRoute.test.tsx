import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';
import { ProtectedRoute } from './ProtectedRoute';

const authMock = vi.fn();
const profileMock = vi.fn();
vi.mock('../hooks/useAuth', () => ({ useAuth: () => authMock() }));
vi.mock('../hooks/useProfile', () => ({ useProfile: () => profileMock() }));

describe('ProtectedRoute', () => {
  it('shows a loading state while auth resolves', () => {
    authMock.mockReturnValue({ session: null, loading: true });
    profileMock.mockReturnValue({ data: undefined, isLoading: true });
    render(<MemoryRouter><ProtectedRoute><p>محتوى</p></ProtectedRoute></MemoryRouter>);
    expect(screen.queryByText('محتوى')).not.toBeInTheDocument();
  });

  it('renders children for an authenticated verifier', () => {
    authMock.mockReturnValue({ session: { user: { id: 'u1' } }, loading: false });
    profileMock.mockReturnValue({ data: { id: 'u1', fullName: 'م', phone: null, role: 'verifier', isApproved: true }, isLoading: false });
    render(<MemoryRouter><ProtectedRoute><p>محتوى</p></ProtectedRoute></MemoryRouter>);
    expect(screen.getByText('محتوى')).toBeInTheDocument();
  });

  it('shows "not available for your role" instead of the content for a non-verifier role', () => {
    authMock.mockReturnValue({ session: { user: { id: 'u1' } }, loading: false });
    profileMock.mockReturnValue({ data: { id: 'u1', fullName: 'م', phone: null, role: 'rep', isApproved: true }, isLoading: false });
    render(<MemoryRouter><ProtectedRoute><p>محتوى</p></ProtectedRoute></MemoryRouter>);
    expect(screen.queryByText('محتوى')).not.toBeInTheDocument();
    expect(screen.getByText(/هذا النظام غير متاح حالياً لدورك/)).toBeInTheDocument();
  });

  it('shows the not-available screen instead of the content for a deactivated (unapproved) verifier', () => {
    authMock.mockReturnValue({ session: { user: { id: 'u1' } }, loading: false });
    profileMock.mockReturnValue({ data: { id: 'u1', fullName: 'م', phone: null, role: 'verifier', isApproved: false }, isLoading: false });
    render(<MemoryRouter><ProtectedRoute><p>محتوى</p></ProtectedRoute></MemoryRouter>);
    expect(screen.queryByText('محتوى')).not.toBeInTheDocument();
    expect(screen.getByText(/هذا النظام غير متاح حالياً لدورك/)).toBeInTheDocument();
  });

  it('does not render children while profile is loading with an authenticated session', () => {
    authMock.mockReturnValue({ session: { user: { id: 'u1' } }, loading: false });
    profileMock.mockReturnValue({ data: undefined, isLoading: true });
    render(<MemoryRouter><ProtectedRoute><p>محتوى</p></ProtectedRoute></MemoryRouter>);
    expect(screen.queryByText('محتوى')).not.toBeInTheDocument();
  });

  it('redirects unauthenticated users to /login', () => {
    authMock.mockReturnValue({ session: null, loading: false });
    profileMock.mockReturnValue({ data: undefined, isLoading: false });
    render(
      <MemoryRouter initialEntries={['/protected']}>
        <Routes>
          <Route path="/login" element={<p>login page</p>} />
          <Route path="/protected" element={<ProtectedRoute><p>محتوى</p></ProtectedRoute>} />
        </Routes>
      </MemoryRouter>
    );
    expect(screen.getByText('login page')).toBeInTheDocument();
    expect(screen.queryByText('محتوى')).not.toBeInTheDocument();
  });
});
