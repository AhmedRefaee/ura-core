import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { OrdersToolbar } from './OrdersToolbar';

describe('OrdersToolbar', () => {
  it('calls onTabChange when switching between نشطة and مكتملة', () => {
    const onTabChange = vi.fn();
    render(
      <OrdersToolbar
        sortMode="most_recent" directionFilter="all" groupMode={null} activeTab="active"
        onSortModeChange={() => {}} onDirectionFilterChange={() => {}} onGroupModeChange={() => {}}
        onTabChange={onTabChange}
      />,
    );
    fireEvent.click(screen.getByRole('button', { name: 'مكتملة' }));
    expect(onTabChange).toHaveBeenCalledWith('completed');
  });

  it('calls onDirectionFilterChange with the selected direction', () => {
    const onDirectionFilterChange = vi.fn();
    render(
      <OrdersToolbar
        sortMode="most_recent" directionFilter="all" groupMode={null} activeTab="active"
        onSortModeChange={() => {}} onDirectionFilterChange={onDirectionFilterChange} onGroupModeChange={() => {}}
        onTabChange={() => {}}
      />,
    );
    fireEvent.change(screen.getByLabelText('نوع العملية'), { target: { value: 'outbound' } });
    expect(onDirectionFilterChange).toHaveBeenCalledWith('outbound');
  });
});
