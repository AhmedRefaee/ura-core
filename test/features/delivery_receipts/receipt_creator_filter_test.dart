import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/features/delivery_receipts/logic/receipt_creator_filter.dart';
import 'package:ura_core/shared/models/delivery_receipt.dart';
import 'package:ura_core/shared/models/profile.dart';

void main() {
  DeliveryReceipt by(String id, String? repId, {String? name, String? linkId}) => DeliveryReceipt(
        id: id,
        entityId: 'e1',
        projectId: 'p1',
        repId: repId,
        rep: repId == null ? null : Profile(id: repId, fullName: name ?? repId, isApproved: true),
        sourceLinkId: linkId,
        submitterName: linkId == null ? null : 'الجهة',
      );

  final mine = by('r1', 'me', name: 'أنا');
  final sara = by('r2', 'u2', name: 'سارة');
  final ali = by('r3', 'u3', name: 'علي');
  final ali2 = by('r4', 'u3', name: 'علي');
  final portal = by('r5', null, linkId: 'l1');
  final all = [mine, sara, ali, ali2, portal];

  test('mine is only what the signed-in user filed', () {
    expect(filterReceiptsByCreator(all, const MineFilter(), 'me'), [mine]);
  });

  test('everyone is the whole list, portal submissions included', () {
    expect(filterReceiptsByCreator(all, const EveryoneFilter(), 'me'), all);
  });

  test('one person, and share-link submissions on their own', () {
    expect(filterReceiptsByCreator(all, const PersonFilter('u3'), 'me'), [ali, ali2]);
    expect(filterReceiptsByCreator(all, const ShareLinkFilter(), 'me'), [portal]);
  });

  test('creators: everyone else who filed, once each, by name', () {
    expect(receiptCreators(all, 'me'), [(id: 'u2', name: 'سارة'), (id: 'u3', name: 'علي')]);
  });

  test('no session means no "mine"', () {
    expect(filterReceiptsByCreator(all, const MineFilter(), null), isEmpty);
  });

  group('entity and date', () {
    DeliveryReceipt on(String id, String entityId, DateTime? created, {DateTime? delivered}) => DeliveryReceipt(
          id: id,
          entityId: entityId,
          projectId: 'p1',
          repId: 'me',
          createdAt: created,
          deliveredAt: delivered,
        );

    final oct1 = on('a', 'e1', DateTime(2026, 10, 1, 9));
    final oct5Late = on('b', 'e2', DateTime(2026, 10, 5, 23, 30));
    final deliveredOct10 = on('c', 'e1', DateTime(2026, 10, 3), delivered: DateTime(2026, 10, 10, 8));
    final undated = on('d', 'e2', null);
    final list = [oct1, oct5Late, deliveredOct10, undated];

    test('no filter keeps everything, undated included', () {
      expect(filterReceiptsByEntityAndDate(list), list);
    });

    test('entity alone', () {
      expect(filterReceiptsByEntityAndDate(list, entityId: 'e2'), [oct5Late, undated]);
    });

    test('a range is whole days, both ends inclusive, by delivery date when known', () {
      expect(
        filterReceiptsByEntityAndDate(list, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 5)),
        [oct1, oct5Late],
        reason: '23:30 on the last day still counts; delivered-on-the-10th is outside',
      );
      expect(filterReceiptsByEntityAndDate(list, from: DateTime(2026, 10, 6)), [deliveredOct10]);
    });

    test('entity and dates together', () {
      expect(
        filterReceiptsByEntityAndDate(list, entityId: 'e1', to: DateTime(2026, 10, 31)),
        [oct1, deliveredOct10],
      );
    });

    test('entities offered once each', () {
      expect(receiptEntities(list).map((e) => e.id).toSet(), {'e1', 'e2'});
    });
  });

  group('sort', () {
    DeliveryReceipt r(String id, DateTime created, int items) => DeliveryReceipt(
          id: id,
          entityId: 'e1',
          projectId: 'p1',
          createdAt: created,
          items: [
            for (var i = 0; i < items; i++)
              DeliveryReceiptItem(
                id: '$id$i',
                deliveryReceiptId: id,
                itemNameSnapshot: 'بند',
                unitSnapshot: 'حبة',
                quantityDelivered: 1,
              ),
          ],
        );

    final early = r('early', DateTime(2026, 10, 1), 2);
    final mid = r('mid', DateTime(2026, 10, 5), 7);
    final late = r('late', DateTime(2026, 10, 9), 2);
    final list = [mid, early, late];

    List<String> ids(ReceiptSort s) => sortReceipts(list, s).map((x) => x.id).toList();

    test('newest and oldest', () {
      expect(ids(ReceiptSort.newest), ['late', 'mid', 'early']);
      expect(ids(ReceiptSort.oldest), ['early', 'mid', 'late']);
    });

    test('most items first; equal counts fall back to newest first', () {
      expect(ids(ReceiptSort.mostItems), ['mid', 'late', 'early']);
    });

    test('only date orders group by day', () {
      expect(ReceiptSort.mostItems.groupsByDay, isFalse);
      expect(ReceiptSort.newest.groupsByDay, isTrue);
    });
  });
}
