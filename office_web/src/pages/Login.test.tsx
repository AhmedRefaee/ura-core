import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import Login from './Login';

vi.mock('../hooks/useAuth', () => ({ signIn: vi.fn() }));

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
});
