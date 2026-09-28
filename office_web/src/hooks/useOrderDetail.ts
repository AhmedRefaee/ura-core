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
    // Only the core order fetch should blank the whole detail panel. The
    // audit-log and سند queries are ancillary — a failure there is handled
    // inline, per section, via auditLogError/receiptsError below.
    isError: orderQuery.isError,
    error: orderQuery.error,
    auditLogError: auditLogQuery.isError,
    receiptsError: receiptsQuery.isError,
    refetch: () => {
      orderQuery.refetch();
      auditLogQuery.refetch();
      receiptsQuery.refetch();
    },
  };
}
