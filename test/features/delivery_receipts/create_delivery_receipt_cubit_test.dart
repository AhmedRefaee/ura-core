import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/features/delivery_receipts/data/delivery_receipt_draft_repository.dart';
import 'package:ura_core/features/delivery_receipts/data/delivery_receipt_repository.dart';
import 'package:ura_core/features/delivery_receipts/data/delivery_receipt_storage_service.dart';
import 'package:ura_core/features/delivery_receipts/logic/create_delivery_receipt_cubit.dart';
import 'package:ura_core/features/projects/data/project_repository.dart';
import 'package:ura_core/features/verifier/data/entity_repository.dart';
import 'package:ura_core/shared/models/delivery_receipt.dart';
import 'package:ura_core/shared/models/delivery_receipt_draft.dart';
import 'package:ura_core/shared/models/entity.dart';
import 'package:ura_core/shared/models/project.dart';
import 'package:ura_core/shared/models/project_item.dart';

class MockEntityRepository extends Mock implements EntityRepository {}

class MockProjectRepository extends Mock implements ProjectRepository {}

class MockDeliveryReceiptRepository extends Mock implements DeliveryReceiptRepository {}

class MockDeliveryReceiptStorageService extends Mock implements DeliveryReceiptStorageService {}

class MockDeliveryReceiptDraftRepository extends Mock implements DeliveryReceiptDraftRepository {}

void main() {
  // submit() builds a real PDF (Arabic fonts via rootBundle) -- same
  // requirement as delivery_receipt_pdf_test.dart.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(DeliveryReceiptDraft(
      id: 'fallback',
      entityId: 'e',
      entityName: 'e',
      projectId: 'p',
      projectName: 'p',
      quantities: const {},
      itemNotes: const {},
      dateMode: 'today',
      splitByCategory: false,
      savedAt: DateTime(2026),
    ));
  });

  const entity = Entity(id: 'e1', name: 'وزارة', category: EntityCategory.outgoing);
  const projectA = Project(id: 'p1', entityId: 'e1', name: 'مشروع أ');
  const projectB = Project(id: 'p2', entityId: 'e1', name: 'مشروع ب');
  const item = ProjectItem(id: 'i1', projectId: 'p2', itemName: 'كرسي', quantity: 10, unit: 'حبة');

  late MockEntityRepository entities;
  late MockProjectRepository projects;
  late MockDeliveryReceiptDraftRepository drafts;

  CreateDeliveryReceiptCubit build(DeliveryReceiptLaunch launch) => CreateDeliveryReceiptCubit(
        entities,
        projects,
        MockDeliveryReceiptRepository(),
        MockDeliveryReceiptStorageService(),
        drafts,
        launch,
      );

  setUp(() {
    entities = MockEntityRepository();
    projects = MockProjectRepository();
    drafts = MockDeliveryReceiptDraftRepository();
    when(() => drafts.save(any())).thenAnswer((_) async {});
    when(() => drafts.delete(any())).thenAnswer((_) async {});
    when(() => entities.fetchEntities()).thenAnswer((_) async => const AppSuccess([entity]));
    when(() => projects.fetchProjectsForEntity('e1'))
        .thenAnswer((_) async => const AppSuccess([projectA, projectB]));
    when(() => projects.fetchProjectItems(any())).thenAnswer((_) async => const AppSuccess([item]));
    when(() => projects.fetchEntityIdsWithProjects()).thenAnswer((_) async => const AppSuccess({'e1'}));
  });

  test('launched from an order, entity and the order\'s project are pre-filled', () async {
    final cubit = build(const DeliveryReceiptLaunch(orderId: 'o1', entity: entity, projectId: 'p2'));
    await cubit.init();

    expect(cubit.state.entity, entity);
    expect(cubit.state.project, projectB);
    expect(cubit.state.items, [item]);
  });

  test('an order without a project leaves the project choice to the rep', () async {
    final cubit = build(const DeliveryReceiptLaunch(orderId: 'o1', entity: entity));
    await cubit.init();

    expect(cubit.state.entity, entity);
    expect(cubit.state.project, isNull);
    expect(cubit.state.projects, [projectA, projectB]);
  });

  test('standalone launch starts with nothing chosen', () async {
    final cubit = build(const DeliveryReceiptLaunch());
    await cubit.init();

    expect(cubit.state.entities, [entity]);
    expect(cubit.state.entity, isNull);
    verifyNever(() => projects.fetchProjectsForEntity(any()));
  });

  test('cannot submit until at least one quantity is above zero', () async {
    final cubit = build(const DeliveryReceiptLaunch(entity: entity, projectId: 'p2'));
    await cubit.init();
    expect(cubit.state.canSubmit, isFalse);

    cubit.setQuantity('i1', 3);
    expect(cubit.state.canSubmit, isTrue);

    cubit.setQuantity('i1', 0);
    expect(cubit.state.canSubmit, isFalse);
  });

  test('typed quantities: Arabic digits and thousands parse; text blocks submit', () async {
    final cubit = build(const DeliveryReceiptLaunch(entity: entity, projectId: 'p2'));
    await cubit.init();

    cubit.setQuantityText('i1', '1,000');
    expect(cubit.state.quantities['i1'], 1000, reason: '"," is a thousands separator');
    cubit.setQuantityText('i1', '١٢٫٥');
    expect(cubit.state.quantities['i1'], 12.5);
    expect(cubit.state.canSubmit, isTrue);

    cubit.setQuantityText('i1', '12 كيس');
    expect(cubit.state.invalid, contains('i1'));
    expect(cubit.state.canSubmit, isFalse, reason: 'a typo must not silently drop the line');

    cubit.setQuantityText('i1', '');
    expect(cubit.state.invalid, isEmpty);
    expect(cubit.state.quantities, isEmpty);
  });

  test("a slow response for an earlier project pick can't overwrite a later pick", () async {
    final cubit = build(const DeliveryReceiptLaunch());
    await cubit.init();
    const itemA = ProjectItem(id: 'a1', projectId: 'p1', itemName: 'قديم', quantity: 1, unit: 'حبة');
    final slowA = Completer<AppResult<List<ProjectItem>>>();
    when(() => projects.fetchProjectItems('p1')).thenAnswer((_) => slowA.future);
    when(() => projects.fetchProjectItems('p2')).thenAnswer((_) async => const AppSuccess([item]));

    final pickA = cubit.selectProject(projectA);
    await cubit.selectProject(projectB);
    slowA.complete(const AppSuccess([itemA]));
    await pickA;

    expect(cubit.state.project, projectB);
    expect(cubit.state.items, [item]);
  });

  test('editing pre-fills the old quantities onto lines that still exist', () async {
    const old = DeliveryReceipt(
      id: 'r1',
      entityId: 'e1',
      entity: entity,
      projectId: 'p2',
      repId: 'u1',
      notes: 'ملاحظة قديمة',
      items: [
        DeliveryReceiptItem(id: 'x', deliveryReceiptId: 'r1', projectItemId: 'i1', itemNameSnapshot: 'كرسي', unitSnapshot: 'حبة', quantityDelivered: 4),
        DeliveryReceiptItem(id: 'y', deliveryReceiptId: 'r1', projectItemId: 'gone', itemNameSnapshot: 'محذوف', unitSnapshot: 'حبة', quantityDelivered: 2),
      ],
    );
    final cubit = build(DeliveryReceiptLaunch.edit(old));
    await cubit.init();

    expect(cubit.launch.isEdit, isTrue);
    expect(cubit.state.project, projectB);
    expect(cubit.state.quantities, {'i1': 4.0});
    expect(cubit.state.droppedFromOriginal, 1, reason: 'the line no longer in the quotation is reported');
    expect(cubit.state.canSubmit, isTrue);
  });

  test('defaults to today, and setDateMode switches between today/blank with no leftover custom date', () async {
    final cubit = build(const DeliveryReceiptLaunch(entity: entity, projectId: 'p2'));
    await cubit.init();
    expect(cubit.state.dateMode, ReceiptDateMode.today);

    cubit.setCustomDate(DateTime(2026, 5, 1));
    expect(cubit.state.dateMode, ReceiptDateMode.custom);
    expect(cubit.state.customDate, DateTime(2026, 5, 1));

    cubit.setDateMode(ReceiptDateMode.blank);
    expect(cubit.state.dateMode, ReceiptDateMode.blank);
    expect(cubit.state.customDate, isNull, reason: 'switching away from custom must drop the picked date');

    cubit.setDateMode(ReceiptDateMode.today);
    expect(cubit.state.dateMode, ReceiptDateMode.today);
  });

  test('setCustomDate sets the mode and the date together', () async {
    final cubit = build(const DeliveryReceiptLaunch(entity: entity, projectId: 'p2'));
    await cubit.init();

    cubit.setCustomDate(DateTime(2026, 1, 15));
    expect(cubit.state.dateMode, ReceiptDateMode.custom);
    expect(cubit.state.customDate, DateTime(2026, 1, 15));
  });

  test('setItemNote sets, trims, and clears a per-item note', () async {
    final cubit = build(const DeliveryReceiptLaunch(entity: entity, projectId: 'p2'));
    await cubit.init();

    cubit.setItemNote('i1', '  مكسور من الأعلى  ');
    expect(cubit.state.itemNotes['i1'], 'مكسور من الأعلى', reason: 'stored trimmed');

    cubit.setItemNote('i1', '   ');
    expect(cubit.state.itemNotes, isEmpty, reason: 'a blank note clears the entry rather than storing it');
  });

  test('editing pre-fills the old per-item notes onto lines that still exist', () async {
    const old = DeliveryReceipt(
      id: 'r1',
      entityId: 'e1',
      entity: entity,
      projectId: 'p2',
      repId: 'u1',
      items: [
        DeliveryReceiptItem(
          id: 'x', deliveryReceiptId: 'r1', projectItemId: 'i1', itemNameSnapshot: 'كرسي',
          unitSnapshot: 'حبة', quantityDelivered: 4, notes: 'مكسور من الأعلى',
        ),
        DeliveryReceiptItem(
          id: 'y', deliveryReceiptId: 'r1', projectItemId: 'gone', itemNameSnapshot: 'محذوف',
          unitSnapshot: 'حبة', quantityDelivered: 2, notes: 'ملاحظة على بند محذوف',
        ),
      ],
    );
    final cubit = build(DeliveryReceiptLaunch.edit(old));
    await cubit.init();

    expect(cubit.state.itemNotes, {'i1': 'مكسور من الأعلى'},
        reason: 'the note on the dropped line must not survive either');
  });

  group('groupItemsByCategory', () {
    const bread1 = ProjectItem(id: 'b1', projectId: 'p1', itemName: 'خبز', quantity: 1, unit: 'كيس', category: 'مخبوزات');
    const bread2 = ProjectItem(id: 'b2', projectId: 'p1', itemName: 'كرواسون', quantity: 1, unit: 'علبة', category: 'مخبوزات');
    const coal = ProjectItem(id: 'c1', projectId: 'p1', itemName: 'فحم', quantity: 1, unit: 'كيس', category: 'الفحم ومواد الاشعال');
    const plain = ProjectItem(id: 'p1i', projectId: 'p1', itemName: 'بند بلا فئة', quantity: 1, unit: 'قطعة');

    test('groups items by category, each category keeping its own item order', () {
      final groups = groupItemsByCategory([bread1, coal, bread2]);
      expect(groups, [
        [bread1, bread2],
        [coal],
      ]);
    });

    test('an empty category string is still its own group, not merged into another', () {
      final groups = groupItemsByCategory([bread1, plain]);
      expect(groups, [
        [bread1],
        [plain],
      ]);
    });

    test('a single category returns one group with everything in it', () {
      expect(groupItemsByCategory([bread1, bread2]), [
        [bread1, bread2],
      ]);
    });

    test('no items is no groups', () {
      expect(groupItemsByCategory(const []), isEmpty);
    });
  });

  test('splitByCategory files one سند per category, shown one at a time via advanceToNextReceipt',
      () async {
    const bread = ProjectItem(id: 'b1', projectId: 'p2', itemName: 'خبز', quantity: 5, unit: 'كيس', category: 'مخبوزات');
    const coal = ProjectItem(id: 'c1', projectId: 'p2', itemName: 'فحم', quantity: 5, unit: 'كيس', category: 'الفحم');
    when(() => projects.fetchProjectItems('p2')).thenAnswer((_) async => const AppSuccess([bread, coal]));

    final receiptRepo = MockDeliveryReceiptRepository();
    final storage = MockDeliveryReceiptStorageService();
    when(() => storage.uploadPdf(any())).thenAnswer((_) async => const AppSuccess('https://example.com/r.pdf'));
    var createdCount = 0;
    when(() => receiptRepo.createDeliveryReceipt(
          entityId: any(named: 'entityId'),
          projectId: any(named: 'projectId'),
          items: any(named: 'items'),
          orderId: any(named: 'orderId'),
          pdfUrl: any(named: 'pdfUrl'),
          notes: any(named: 'notes'),
          replacesReceiptId: any(named: 'replacesReceiptId'),
        )).thenAnswer((_) async {
      createdCount++;
      return AppSuccess('receipt-$createdCount');
    });

    final cubit = CreateDeliveryReceiptCubit(
      entities,
      projects,
      receiptRepo,
      storage,
      drafts,
      const DeliveryReceiptLaunch(entity: entity, projectId: 'p2'),
    );
    await cubit.init();
    cubit.setQuantity('b1', 5);
    cubit.setQuantity('c1', 5);
    cubit.setSplitByCategory(true);

    await cubit.submit();

    expect(createdCount, 2, reason: 'two categories picked -- two سندات created, not one');
    expect(cubit.state.totalReceiptsThisSubmit, 2);
    expect(cubit.state.remainingReceipts, hasLength(1));
    expect(cubit.state.receiptId, 'receipt-1');
    expect(cubit.state.currentCategoryLabel, 'مخبوزات', reason: 'the first-created سند is shown first');

    cubit.advanceToNextReceipt();

    expect(cubit.state.remainingReceipts, isEmpty);
    expect(cubit.state.receiptId, 'receipt-2');
    expect(cubit.state.currentCategoryLabel, 'الفحم');
  });

  test('splitByCategory off (the default) still files everything as a single سند', () async {
    const bread = ProjectItem(id: 'b1', projectId: 'p2', itemName: 'خبز', quantity: 5, unit: 'كيس', category: 'مخبوزات');
    const coal = ProjectItem(id: 'c1', projectId: 'p2', itemName: 'فحم', quantity: 5, unit: 'كيس', category: 'الفحم');
    when(() => projects.fetchProjectItems('p2')).thenAnswer((_) async => const AppSuccess([bread, coal]));

    final receiptRepo = MockDeliveryReceiptRepository();
    final storage = MockDeliveryReceiptStorageService();
    when(() => storage.uploadPdf(any())).thenAnswer((_) async => const AppSuccess('https://example.com/r.pdf'));
    when(() => receiptRepo.createDeliveryReceipt(
          entityId: any(named: 'entityId'),
          projectId: any(named: 'projectId'),
          items: any(named: 'items'),
          orderId: any(named: 'orderId'),
          pdfUrl: any(named: 'pdfUrl'),
          notes: any(named: 'notes'),
          replacesReceiptId: any(named: 'replacesReceiptId'),
        )).thenAnswer((_) async => const AppSuccess('receipt-1'));

    final cubit = CreateDeliveryReceiptCubit(
      entities,
      projects,
      receiptRepo,
      storage,
      drafts,
      const DeliveryReceiptLaunch(entity: entity, projectId: 'p2'),
    );
    await cubit.init();
    cubit.setQuantity('b1', 5);
    cubit.setQuantity('c1', 5);

    await cubit.submit();

    verify(() => receiptRepo.createDeliveryReceipt(
          entityId: any(named: 'entityId'),
          projectId: any(named: 'projectId'),
          items: any(named: 'items'),
          orderId: any(named: 'orderId'),
          pdfUrl: any(named: 'pdfUrl'),
          notes: any(named: 'notes'),
          replacesReceiptId: any(named: 'replacesReceiptId'),
        )).called(1);
    expect(cubit.state.totalReceiptsThisSubmit, 1);
    expect(cubit.state.remainingReceipts, isEmpty);
  });

  group('drafts', () {
    test('saveDraft does nothing without a project chosen or anything picked', () async {
      final cubit = build(const DeliveryReceiptLaunch(entity: entity, projectId: 'p2'));
      await cubit.init();

      await cubit.saveDraft();

      verifyNever(() => drafts.save(any()));
    });

    test('saveDraft persists current progress, and re-saving overwrites the same draft', () async {
      final cubit = build(const DeliveryReceiptLaunch(entity: entity, projectId: 'p2'));
      await cubit.init();
      cubit.setQuantity('i1', 4);
      cubit.setItemNote('i1', 'بحاجة فحص');
      cubit.setCustomDate(DateTime(2026, 7, 1));

      await cubit.saveDraft();
      final first = verify(() => drafts.save(captureAny())).captured.single as DeliveryReceiptDraft;
      expect(first.entityId, 'e1');
      expect(first.projectId, 'p2');
      expect(first.quantities, {'i1': 4.0});
      expect(first.itemNotes, {'i1': 'بحاجة فحص'});
      expect(first.dateMode, 'custom');
      expect(first.customDate, DateTime(2026, 7, 1));

      cubit.setQuantity('i1', 9);
      await cubit.saveDraft();
      final second = verify(() => drafts.save(captureAny())).captured.single as DeliveryReceiptDraft;
      expect(second.id, first.id, reason: 'same session, same draft -- not a second one');
      expect(second.quantities, {'i1': 9.0});
    });

    test('resuming a draft pre-fills its quantities, notes, date mode and split setting', () async {
      final savedDraft = DeliveryReceiptDraft(
        id: 'd1',
        entityId: 'e1',
        entityName: 'وزارة',
        projectId: 'p2',
        projectName: 'مشروع ب',
        quantities: const {'i1': 7},
        itemNotes: const {'i1': 'ملاحظة محفوظة'},
        dateMode: 'blank',
        splitByCategory: true,
        savedAt: DateTime(2026, 5, 1),
      );
      final cubit = build(DeliveryReceiptLaunch.resumeDraft(savedDraft));
      await cubit.init();

      expect(cubit.state.entity, entity);
      expect(cubit.state.project, projectB);
      expect(cubit.state.quantities, {'i1': 7.0});
      expect(cubit.state.itemNotes, {'i1': 'ملاحظة محفوظة'});
      expect(cubit.state.dateMode, ReceiptDateMode.blank);
      expect(cubit.state.splitByCategory, isTrue);
    });

    test('resuming a draft drops lines no longer in the quotation, same as editing does', () async {
      final savedDraft = DeliveryReceiptDraft(
        id: 'd1',
        entityId: 'e1',
        entityName: 'وزارة',
        projectId: 'p2',
        projectName: 'مشروع ب',
        quantities: const {'i1': 7, 'gone': 3},
        itemNotes: const {},
        dateMode: 'today',
        splitByCategory: false,
        savedAt: DateTime(2026, 5, 1),
      );
      final cubit = build(DeliveryReceiptLaunch.resumeDraft(savedDraft));
      await cubit.init();

      expect(cubit.state.quantities, {'i1': 7.0}, reason: '"gone" is not in the quotation anymore');
    });

    test('a successful submit deletes the draft it resumed from', () async {
      final savedDraft = DeliveryReceiptDraft(
        id: 'd1',
        entityId: 'e1',
        entityName: 'وزارة',
        projectId: 'p2',
        projectName: 'مشروع ب',
        quantities: const {'i1': 7},
        itemNotes: const {},
        dateMode: 'today',
        splitByCategory: false,
        savedAt: DateTime(2026, 5, 1),
      );
      final receiptRepo = MockDeliveryReceiptRepository();
      final storage = MockDeliveryReceiptStorageService();
      when(() => storage.uploadPdf(any())).thenAnswer((_) async => const AppSuccess('https://example.com/r.pdf'));
      when(() => receiptRepo.createDeliveryReceipt(
            entityId: any(named: 'entityId'),
            projectId: any(named: 'projectId'),
            items: any(named: 'items'),
            orderId: any(named: 'orderId'),
            pdfUrl: any(named: 'pdfUrl'),
            notes: any(named: 'notes'),
            replacesReceiptId: any(named: 'replacesReceiptId'),
          )).thenAnswer((_) async => const AppSuccess('receipt-1'));

      final cubit = CreateDeliveryReceiptCubit(
        entities,
        projects,
        receiptRepo,
        storage,
        drafts,
        DeliveryReceiptLaunch.resumeDraft(savedDraft),
      );
      await cubit.init();

      await cubit.submit();

      verify(() => drafts.delete('d1')).called(1);
    });
  });

  test('switching entity clears the previous project and quantities', () async {
    final cubit = build(const DeliveryReceiptLaunch(entity: entity, projectId: 'p2'));
    await cubit.init();
    cubit.setQuantity('i1', 3);

    const other = Entity(id: 'e2', name: 'بلدية', category: EntityCategory.outgoing);
    when(() => projects.fetchProjectsForEntity('e2')).thenAnswer((_) async => const AppSuccess([]));
    await cubit.selectEntity(other);

    expect(cubit.state.project, isNull);
    expect(cubit.state.quantities, isEmpty);
    expect(cubit.state.canSubmit, isFalse);
  });
}
