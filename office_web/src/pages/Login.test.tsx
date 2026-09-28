import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';
import Login from './Login';

vi.mock('../hooks/useAuth', () => ({
  signIn: vi.fn(),
  useAuth: vi.fn(() => ({ session: null, loading: false })),
}));

describe('Login', () => {
  it('shows an inline error on invalid credentials, not a silent failure', async () => {
    const { signIn } = await import('../hooks/useAuth');
    vi.mocked(signIn).mockResolvedValue({ error: 'Invalid login credentials' });

    render(<MemoryRouter><Login /></MemoryRouter>);
    fireEvent.change(screen.getByLabelText('اسم المستخدم أو البريد المؤسسي'), { target: { value: 'a@b.com' } });
    fireEvent.change(screen.getByLabelText('كلمة المرور'), { target: { value: 'wrong' } });
    fireEvent.click(screen.getByRole('button', { name: 'دخول إلى النظام' }));

    await waitFor(() => expect(screen.getByText('Invalid login credentials')).toBeInTheDocument());
  });

  it('submits the typed email and password', async () => {
    const { signIn } = await import('../hooks/useAuth');
    vi.mocked(signIn).mockResolvedValue({ error: null });

    render(<MemoryRouter><Login /></MemoryRouter>);
    fireEvent.change(screen.getByLabelText('اسم المستخدم أو البريد المؤسسي'), { target: { value: 'a@b.com' } });
    fireEvent.change(screen.getByLabelText('كلمة المرور'), { target: { value: 'right-pw' } });
    fireEvent.click(screen.getByRole('button', { name: 'دخول إلى النظام' }));

    await waitFor(() => expect(signIn).toHaveBeenCalledWith('a@b.com', 'right-pw'));
  });

  it('navigates to /orders after a successful sign-in', async () => {
    const { signIn } = await import('../hooks/useAuth');
    vi.mocked(signIn).mockResolvedValue({ error: null });

    render(
      <MemoryRouter initialEntries={['/login']}>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route path="/orders" element={<p>orders page</p>} />
        </Routes>
      </MemoryRouter>,
    );
    fireEvent.change(screen.getByLabelText('اسم المستخدم أو البريد المؤسسي'), { target: { value: 'a@b.com' } });
    fireEvent.change(screen.getByLabelText('كلمة المرور'), { target: { value: 'right-pw' } });
    fireEvent.click(screen.getByRole('button', { name: 'دخول إلى النظام' }));

    await waitFor(() => expect(screen.getByText('orders page')).toBeInTheDocument());
  });

  it('redirects an already-authenticated visitor at /login to /orders without submitting the form', async () => {
    const { useAuth } = await import('../hooks/useAuth');
    vi.mocked(useAuth).mockReturnValue({ session: { user: { id: 'u1' } }, loading: false } as ReturnType<typeof useAuth>);

    render(
      <MemoryRouter initialEntries={['/login']}>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route path="/orders" element={<p>orders page</p>} />
        </Routes>
      </MemoryRouter>,
    );

    expect(screen.getByText('orders page')).toBeInTheDocument();
    expect(screen.queryByLabelText('كلمة المرور')).not.toBeInTheDocument();

    vi.mocked(useAuth).mockReturnValue({ session: null, loading: false } as ReturnType<typeof useAuth>);
  });
});
