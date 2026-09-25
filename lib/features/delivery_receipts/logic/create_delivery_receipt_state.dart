part of 'create_delivery_receipt_cubit.dart';

abstract class CreateDeliveryReceiptState extends Equatable {
  const CreateDeliveryReceiptState();

  @override
  List<Object?> get props => [];
}

class CreateDeliveryReceiptInitial extends CreateDeliveryReceiptState {
  const CreateDeliveryReceiptInitial();
}

class CreateDeliveryReceiptLoading extends CreateDeliveryReceiptState {
  const CreateDeliveryReceiptLoading();
}

class CreateDeliveryReceiptSuccess extends CreateDeliveryReceiptState {
  final String receiptId;
  const CreateDeliveryReceiptSuccess(this.receiptId);

  @override
  List<Object?> get props => [receiptId];
}

class CreateDeliveryReceiptError extends CreateDeliveryReceiptState {
  final String message;
  const CreateDeliveryReceiptError(this.message);

  @override
  List<Object?> get props => [message];
}
