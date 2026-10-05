import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/shared/models/delivery_receipt_draft.dart';

void main() {
  test('toJson/fromJson round-trips every field, including a null customDate', () {
    final draft = DeliveryReceiptDraft(
      id: 'd1',
      entityId: 'e1',
      entityName: 'وزارة',
      projectId: 'p1',
      projectName: 'مشروع',
      orderId: 'o1',
      quantities: const {'i1': 3.5, 'i2': 10},
      itemNotes: const {'i1': 'مكسور'},
      dateMode: 'blank',
      customDate: null,
      splitByCategory: true,
      savedAt: DateTime(2026, 5, 1, 14, 30),
    );

    final roundTripped = DeliveryReceiptDraft.fromJson(draft.toJson());

    expect(roundTripped, draft);
  });

  test('round-trips a set customDate', () {
    final draft = DeliveryReceiptDraft(
      id: 'd1',
      entityId: 'e1',
      entityName: 'وزارة',
      projectId: 'p1',
      projectName: 'مشروع',
      quantities: const {'i1': 1},
      itemNotes: const {},
      dateMode: 'custom',
      customDate: DateTime(2026, 6, 15),
      splitByCategory: false,
      savedAt: DateTime(2026, 5, 1),
    );

    expect(DeliveryReceiptDraft.fromJson(draft.toJson()).customDate, DateTime(2026, 6, 15));
  });

  test('itemCount is the number of picked lines', () {
    final draft = DeliveryReceiptDraft(
      id: 'd1',
      entityId: 'e1',
      entityName: 'وزارة',
      projectId: 'p1',
      projectName: 'مشروع',
      quantities: const {'i1': 1, 'i2': 2, 'i3': 3},
      itemNotes: const {},
      dateMode: 'today',
      splitByCategory: false,
      savedAt: DateTime(2026, 5, 1),
    );

    expect(draft.itemCount, 3);
  });
}
