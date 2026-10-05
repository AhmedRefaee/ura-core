import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ura_core/features/delivery_receipts/data/delivery_receipt_draft_repository.dart';
import 'package:ura_core/shared/models/delivery_receipt_draft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DeliveryReceiptDraft draft({required String id, required DateTime savedAt}) => DeliveryReceiptDraft(
        id: id,
        entityId: 'e1',
        entityName: 'وزارة',
        projectId: 'p1',
        projectName: 'مشروع',
        quantities: const {'i1': 2},
        itemNotes: const {},
        dateMode: 'today',
        splitByCategory: false,
        savedAt: savedAt,
      );

  Future<DeliveryReceiptDraftRepository> build() async {
    SharedPreferences.setMockInitialValues({});
    return DeliveryReceiptDraftRepository(await SharedPreferences.getInstance());
  }

  test('a fresh install has no drafts', () async {
    final repo = await build();
    expect(repo.list(), isEmpty);
  });

  test('save then list round-trips the draft', () async {
    final repo = await build();
    final d = draft(id: 'd1', savedAt: DateTime(2026, 5, 1));
    await repo.save(d);
    expect(repo.list(), [d]);
  });

  test('saving the same id again replaces it instead of duplicating', () async {
    final repo = await build();
    await repo.save(draft(id: 'd1', savedAt: DateTime(2026, 5, 1)));
    final updated = draft(id: 'd1', savedAt: DateTime(2026, 5, 2));
    await repo.save(updated);

    expect(repo.list(), [updated]);
  });

  test('newest first', () async {
    final repo = await build();
    await repo.save(draft(id: 'old', savedAt: DateTime(2026, 5, 1)));
    await repo.save(draft(id: 'new', savedAt: DateTime(2026, 5, 3)));
    await repo.save(draft(id: 'middle', savedAt: DateTime(2026, 5, 2)));

    expect(repo.list().map((d) => d.id), ['new', 'middle', 'old']);
  });

  test('delete removes only the matching draft', () async {
    final repo = await build();
    await repo.save(draft(id: 'keep', savedAt: DateTime(2026, 5, 1)));
    await repo.save(draft(id: 'gone', savedAt: DateTime(2026, 5, 2)));

    await repo.delete('gone');

    expect(repo.list().map((d) => d.id), ['keep']);
  });

  test('corrupt stored data is treated as no drafts, not a crash', () async {
    SharedPreferences.setMockInitialValues({'delivery_receipt_drafts': 'not json at all'});
    final repo = DeliveryReceiptDraftRepository(await SharedPreferences.getInstance());

    expect(repo.list(), isEmpty);
  });
}
