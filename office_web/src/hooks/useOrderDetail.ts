import { useQuery } from '@tanstack/react-query';
import { fetchOrderDetail, fetchAuditLog, fetchDeliveryReceipts } from '../api/orderDetail';

export function useOrderDetail(orderId: string | null) {
  const orderQuery = useQuery({
    queryKey: ['order', orderId],
    queryFn: () => fetchOrderDetail(orderId as string),
    enabled: !!orderId,
  });
  const auditLogQuery = useQuery({
    queryKey: ['auditLog', orderId],
    queryFn: () => fetchAuditLog(orderId as string),
    enabled: !!orderId,
  });
  const receiptsQuery = useQuery({
    queryKey: ['deliveryReceipts', orderId],
    queryFn: () => fetchDeliveryReceipts(orderId as string),
    enabled: !!orderId,
  });

  return {
    order: orderQuery.data,
    auditLog: auditLogQuery.data ?? [],
    receipts: receiptsQuery.data ?? [],
    isLoading: orderQuery.isLoading || auditLogQuery.isLoading || receiptsQuery.isLoading,
    isError: orderQuery.isError || auditLogQuery.isError || receiptsQuery.isError,
    error: orderQuery.error ?? auditLogQuery.error ?? receiptsQuery.error,
    refetch: () => {
      orderQuery.refetch();
      auditLogQuery.refetch();
      receiptsQuery.refetch();
    },
  };
}
