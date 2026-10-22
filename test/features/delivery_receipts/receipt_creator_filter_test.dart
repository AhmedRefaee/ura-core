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
}
