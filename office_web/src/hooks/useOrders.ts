import { useQuery } from '@tanstack/react-query';
import { fetchOrders } from '../api/orders';

export function useOrders() {
  return useQuery({ queryKey: ['orders'], queryFn: fetchOrders });
}
