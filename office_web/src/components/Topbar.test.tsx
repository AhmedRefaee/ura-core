import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { Topbar } from './Topbar';

describe('Topbar', () => {
  it('calls onLogout when the logout button is clicked', () => {
    const onLogout = vi.fn();
    render(<Topbar userName="أحمد" searchValue="" onSearchChange={() => {}} onLogout={onLogout} />);
    fireEvent.click(screen.getByRole('button', { name: 'تسجيل الخروج' }));
    expect(onLogout).toHaveBeenCalled();
  });

  it('calls onSearchChange as the user types', () => {
    const onSearchChange = vi.fn();
    render(<Topbar userName="أحمد" searchValue="" onSearchChange={onSearchChange} onLogout={() => {}} />);
    fireEvent.change(screen.getByPlaceholderText('بحث شامل في الطلبات...'), { target: { value: 'وزارة' } });
    expect(onSearchChange).toHaveBeenCalledWith('وزارة');
  });
});
