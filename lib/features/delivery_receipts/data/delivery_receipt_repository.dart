import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/delivery_receipt.dart';

class DeliveryReceiptRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const _receiptSelect =
      '*, '
      'entity:entities(*), '
      'project:projects(*), '
      'rep:profiles!delivery_receipts_rep_id_fkey(id, full_name, phone, role, is_approved, created_at), '
      'delivery_receipt_items(*)';

  /// Fetch receipts for an order (optionally tied to one).
  Future<AppResult<List<DeliveryReceipt>>> fetchReceiptsForOrder(String orderId) async {
    try {
      logger.d('DeliveryReceiptRepository → fetchReceiptsForOrder: $orderId');
      final data = await _supabase
          .from('delivery_receipts')
          .select(_receiptSelect)
          .eq('order_id', orderId)
          .order('created_at', ascending: false);
      final receipts = (data as List).map((e) => DeliveryReceipt.fromMap(e as Map<String, dynamic>)).toList();
      logger.i('DeliveryReceiptRepository → ${receipts.length} receipts for order $orderId');
      return AppSuccess(receipts);
    } catch (e, st) {
      logger.e('DeliveryReceiptRepository → fetchReceiptsForOrder failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  /// Fetch receipts for a project (standalone or order-tied).
  Future<AppResult<List<DeliveryReceipt>>> fetchReceiptsForProject(String projectId) async {
    try {
      logger.d('DeliveryReceiptRepository → fetchReceiptsForProject: $projectId');
      final data = await _supabase
          .from('delivery_receipts')
          .select(_receiptSelect)
          .eq('project_id', projectId)
          .order('created_at', ascending: false);
      final receipts = (data as List).map((e) => DeliveryReceipt.fromMap(e as Map<String, dynamic>)).toList();
      logger.i('DeliveryReceiptRepository → ${receipts.length} receipts for project $projectId');
      return AppSuccess(receipts);
    } catch (e, st) {
      logger.e('DeliveryReceiptRepository → fetchReceiptsForProject failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  Future<AppResult<List<DeliveryReceipt>>> fetchMyReceipts() async {
    try {
      final uid = _supabase.auth.currentUser!.id;
      logger.d('DeliveryReceiptRepository → fetchMyReceipts: $uid');
      final data = await _supabase
          .from('delivery_receipts')
          .select(_receiptSelect)
          .eq('rep_id', uid)
          .order('created_at', ascending: false);
      final receipts = (data as List).map((e) => DeliveryReceipt.fromMap(e as Map<String, dynamic>)).toList();
      return AppSuccess(receipts);
    } catch (e, st) {
      logger.e('DeliveryReceiptRepository → fetchMyReceipts failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  /// Create a delivery receipt via the server-side RPC for atomicity.
  /// [items] is a list of {"project_item_id": uuid, "quantity_delivered": num}
  Future<AppResult<String>> createDeliveryReceipt({
    required String entityId,
    required String projectId,
    required List<Map<String, dynamic>> items,
    String? orderId,
    String? pdfUrl,
    String? notes,
    String? replacesReceiptId,
  }) async {
    try {
      logger.d('DeliveryReceiptRepository → createDeliveryReceipt | projectId: $projectId items: ${items.length}');
      final result = await _supabase.rpc('create_delivery_receipt', params: {
        'p_entity_id': entityId,
        'p_project_id': projectId,
        'p_items': items,
        'p_order_id': orderId,
        'p_pdf_url': pdfUrl,
        'p_notes': notes,
        'p_replaces': replacesReceiptId,
      });

      if (result['success'] as bool? ?? false) {
        final receiptId = result['delivery_receipt_id'] as String;
        logger.i('DeliveryReceiptRepository → receipt created: $receiptId');
        return AppSuccess(receiptId);
      }
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e('DeliveryReceiptRepository → createDeliveryReceipt failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }

  /// Archives a سند (hidden everywhere, kept for audit). Only its creator
  /// or an admin may; the server enforces it.
  Future<AppResult<void>> deleteDeliveryReceipt(String receiptId) async {
    try {
      logger.d('DeliveryReceiptRepository → deleteDeliveryReceipt: $receiptId');
      final result = await _supabase.rpc('delete_delivery_receipt', params: {'p_receipt_id': receiptId});
      if (result['success'] as bool? ?? false) return const AppSuccess(null);
      return AppFailure(ErrorHandler.fromRpcResult(result as Map));
    } catch (e, st) {
      logger.e('DeliveryReceiptRepository → deleteDeliveryReceipt failed', error: e, stackTrace: st);
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
