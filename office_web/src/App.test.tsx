import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import App from './App';

vi.mock('./hooks/useAuth', () => ({
  useAuth: () => ({ session: null, loading: false }),
  signIn: vi.fn(),
  signOut: vi.fn(),
}));
vi.mock('./hooks/useProfile', () => ({ useProfile: () => ({ data: undefined, isLoading: false }) }));

describe('App', () => {
  it('redirects an unauthenticated visitor to the login page', () => {
    render(<App />);
    expect(screen.getByRole('button', { name: 'دخول إلى النظام' })).toBeInTheDocument();
  });
});
