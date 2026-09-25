import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../shared/models/delivery_receipt.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/models/project.dart';
import '../../../shared/models/project_item.dart';
import '../data/delivery_receipt_repository.dart';
import '../data/delivery_receipt_storage_service.dart';
import '../logic/delivery_receipt_pdf.dart';

part 'create_delivery_receipt_state.dart';

class CreateDeliveryReceiptCubit extends Cubit<CreateDeliveryReceiptState> {
  final DeliveryReceiptRepository _repo;
  final DeliveryReceiptStorageService _storage;

  CreateDeliveryReceiptCubit(this._repo, this._storage) : super(CreateDeliveryReceiptInitial());

  /// Generate and upload PDF, then create the receipt in DB.
  Future<void> generateAndCreate({
    required String entityId,
    required Entity entity,
    required String projectId,
    required Project project,
    required List<ProjectItem> selectedItems,
    String? orderId,
    String? notes,
  }) async {
    try {
      emit(const CreateDeliveryReceiptLoading());

      // Generate PDF in memory
      final fakeRep = Profile(
        id: 'temp',
        fullName: '',
        isApproved: false,
      );

      final pdfDoc = await DeliveryReceiptPdf.generate(
        receipt: DeliveryReceipt(
          id: 'temp',
          entityId: entityId,
          entity: entity,
          projectId: projectId,
          project: project,
          orderId: orderId,
          repId: 'temp',
          deliveredAt: DateTime.now(),
          notes: notes,
          items: [],
        ),
        entity: entity,
        project: project,
        rep: fakeRep,
      );

      final pdfBytes = await pdfDoc.save();
      final tempDir = await _getTempDirectory();
      final tempPath = '${tempDir.path}/receipt_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await File(tempPath).writeAsBytes(pdfBytes);

      // Upload PDF to Storage
      final uploadResult = await _storage.uploadPdf(
        receiptId: 'receipt',
        localPath: tempPath,
        fileName: 'receipt.pdf',
      );

      String? pdfUrl;
      switch (uploadResult) {
        case AppSuccess(:final data):
          pdfUrl = data;
        case AppFailure(:final error):
          emit(CreateDeliveryReceiptError(error.message));
          await File(tempPath).delete();
          return;
      }

      // Create receipt with selected items
      final items = selectedItems
          .map((item) => {
                'project_item_id': item.id,
                'quantity_delivered': item.quantity,
              })
          .toList();

      final result = await _repo.createDeliveryReceipt(
        entityId: entityId,
        projectId: projectId,
        items: items,
        orderId: orderId,
        pdfUrl: pdfUrl,
        notes: notes,
      );

      await File(tempPath).delete();

      switch (result) {
        case AppSuccess(:final data):
          emit(CreateDeliveryReceiptSuccess(data));
        case AppFailure(:final error):
          emit(CreateDeliveryReceiptError(error.message));
      }
    } catch (e, st) {
      logger.e('CreateDeliveryReceiptCubit → generateAndCreate failed', error: e, stackTrace: st);
      emit(const CreateDeliveryReceiptError('فشل إنشاء السند'));
    }
  }

  Future<Directory> _getTempDirectory() async {
    return getTemporaryDirectory();
  }
}
