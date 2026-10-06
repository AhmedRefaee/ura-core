// Ahmed reported that the unit-conversion calculator button is nowhere to be
// found on a real سند screen. The cubit/pdf/logic tests all pass in
// isolation, but nothing actually pumps CreateDeliveryReceiptScreen and
// looks at the rendered widget tree -- so a wiring mistake between the
// cubit's state and the screen's build() method would pass every existing
// test while still being invisible on-device. This file closes that gap.
//
// The calculator is fully manual on both sides -- no contract-text
// detection. Every بند gets the button regardless of its unit/description;
// the rep fills in "من العقد" (what one registered unit is) and "من
// الفاتورة" (what was actually delivered) by hand, every time, since the
// same بند can arrive in a different شد from one سند to the next.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/features/delivery_receipts/data/delivery_receipt_draft_repository.dart';
import 'package:ura_core/features/delivery_receipts/data/delivery_receipt_repository.dart';
import 'package:ura_core/features/delivery_receipts/data/delivery_receipt_storage_service.dart';
import 'package:ura_core/features/delivery_receipts/logic/create_delivery_receipt_cubit.dart';
import 'package:ura_core/features/delivery_receipts/ui/create_delivery_receipt_screen.dart';
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
  setUpAll(() => registerFallbackValue(DeliveryReceiptDraft(
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
      )));

  const entity = Entity(id: 'e1', name: 'وزارة', category: EntityCategory.outgoing);
  const project = Project(id: 'p1', entityId: 'e1', name: 'توريد مواد غذائية');

  // Real wording from Ahmed's contract -- packagingOf() strips everything
  // but the tail after the last "/", the same way it does for the سند PDF.
  const lebna = ProjectItem(
    id: 'i1',
    projectId: 'p1',
    itemName: 'لبنة',
    quantity: 1100,
    unit: 'كرتون',
    description: 'جودة عالية مصنوعه من 100 % دسم الحليب الابقار / كرتون 2.75*4كيلو جرام',
  );
  const rice = ProjectItem(id: 'i3', projectId: 'p1', itemName: 'ارز بسمتي سيلا', quantity: 200, unit: '40 كجم');
  const qishta = ProjectItem(id: 'i2', projectId: 'p1', itemName: 'قشطة', quantity: 12, unit: 'كرتون');

  late MockEntityRepository entities;
  late MockProjectRepository projects;
  late MockDeliveryReceiptDraftRepository drafts;
  late CreateDeliveryReceiptCubit cubit;

  Future<Widget> buildScreen(
    List<ProjectItem> items, {
    DeliveryReceiptLaunch launch = const DeliveryReceiptLaunch(entity: entity, projectId: 'p1'),
  }) async {
    entities = MockEntityRepository();
    projects = MockProjectRepository();
    drafts = MockDeliveryReceiptDraftRepository();
    when(() => entities.fetchEntities()).thenAnswer((_) async => const AppSuccess([entity]));
    when(() => projects.fetchProjectsForEntity('e1')).thenAnswer((_) async => const AppSuccess([project]));
    when(() => projects.fetchProjectItems(any())).thenAnswer((_) async => AppSuccess(items));
    when(() => projects.fetchEntityIdsWithProjects()).thenAnswer((_) async => const AppSuccess({'e1'}));
    when(() => drafts.save(any())).thenAnswer((_) async {});

    cubit = CreateDeliveryReceiptCubit(
      entities,
      projects,
      MockDeliveryReceiptRepository(),
      MockDeliveryReceiptStorageService(),
      drafts,
      launch,
    );
    await cubit.init();

    return MaterialApp(
      home: BlocProvider.value(value: cubit, child: const CreateDeliveryReceiptScreen()),
    );
  }

  testWidgets('stepping back with quantities picked offers to save a draft instead of silently losing them',
      (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildScreen([qishta]));
    await tester.pumpAndSettle();
    cubit.setQuantity('i2', 5);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('سيتم فقدان البنود المختارة'), findsOneWidget);

    await tester.tap(find.text('حفظ كمسودة'));
    await tester.pumpAndSettle();

    final saved = verify(() => drafts.save(captureAny())).captured.single as DeliveryReceiptDraft;
    expect(saved.projectId, 'p1');
    expect(saved.quantities, {'i2': 5.0});
  });

  testWidgets('discarding from the leave-confirm dialog proceeds without saving anything', (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildScreen([qishta]));
    await tester.pumpAndSettle();
    cubit.setQuantity('i2', 5);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تجاهل'));
    await tester.pumpAndSettle();

    verifyNever(() => drafts.save(any()));
  });

  testWidgets('the settings menu can save a draft on the spot, without leaving the screen', (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildScreen([qishta]));
    await tester.pumpAndSettle();
    cubit.setQuantity('i2', 5);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ كمسودة الآن'));
    await tester.pumpAndSettle();

    verify(() => drafts.save(any())).called(1);
    expect(find.text('تم حفظ المسودة'), findsOneWidget);
    // Still on the settings dialog -- a spot-save doesn't leave the screen.
    expect(find.text('إعدادات السند'), findsOneWidget);
  });

  testWidgets('the tile title shows the item name plus the exact packaging text the سند PDF would print',
      (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildScreen([lebna, qishta]));
    await tester.pumpAndSettle();

    // لبنة's description has a packaging tail after the last "/" -- shown
    // right next to the name, same text packagingOf() hands the PDF.
    expect(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == 'لبنة  —  كرتون 2.75*4كيلو جرام',
      ),
      findsOneWidget,
    );

    // قشطة has no description at all -- just the bare name, no dangling
    // "  —  " with nothing after it.
    expect(
      find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == 'قشطة'),
      findsOneWidget,
    );
  });

  testWidgets('date mode lives only in the settings menu, not stuck at the bottom of the items step',
      (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildScreen([qishta]));
    await tester.pumpAndSettle();

    // Not on the main screen -- that's just search, items, and إلغاء/تأكيد.
    expect(find.text('تاريخ السند'), findsNothing);
    expect(find.text('اليوم'), findsNothing);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.text('تاريخ السند'), findsOneWidget);
    expect(find.text('اليوم'), findsOneWidget);
    expect(find.text('يدوي عند التسليم'), findsOneWidget);

    await tester.tap(find.text('يدوي عند التسليم'));
    await tester.pumpAndSettle();

    expect(cubit.state.dateMode, ReceiptDateMode.blank);
  });

  testWidgets('the settings menu toggles splitByCategory and previews how many سندات it will make',
      (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const bread = ProjectItem(id: 'b1', projectId: 'p1', itemName: 'خبز', quantity: 5, unit: 'كيس', category: 'مخبوزات');
    const coal = ProjectItem(id: 'c1', projectId: 'p1', itemName: 'فحم', quantity: 5, unit: 'كيس', category: 'الفحم');
    await tester.pumpWidget(await buildScreen([bread, coal]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('سند منفصل لكل فئة'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('سيتم إنشاء'), findsNothing, reason: 'nothing picked yet, so no preview count');
    expect(cubit.state.splitByCategory, isTrue);

    await tester.tap(find.text('تم'));
    await tester.pumpAndSettle();

    // Pick both items, then reopen settings -- the preview should now say 2.
    cubit.setQuantity('b1', 5);
    cubit.setQuantity('c1', 5);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.textContaining('سيتم إنشاء 2 سند منفصل'), findsOneWidget);
  });

  testWidgets('the settings icon is hidden while editing an existing سند -- a replace can\'t split',
      (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const old = DeliveryReceipt(id: 'r1', entityId: 'e1', entity: entity, projectId: 'p1', repId: 'u1');
    await tester.pumpWidget(await buildScreen([qishta], launch: DeliveryReceiptLaunch.edit(old)));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.tune), findsNothing);
  });

  testWidgets('the paste-from-message button sits beside the search field', (tester) async {
    await tester.pumpWidget(await buildScreen([lebna, qishta]));
    await tester.pumpAndSettle();

    expect(find.byTooltip('تحديد البنود من رسالة'), findsOneWidget);
  });

  testWidgets('the calculator button shows on every item, no matter its unit or description', (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildScreen([lebna, rice, qishta]));
    await tester.pumpAndSettle();

    expect(find.byTooltip('حساب الكمية من التسليم الفعلي'), findsNWidgets(3));
    expect(find.byIcon(Icons.calculate_outlined), findsNWidgets(3));
  });

  testWidgets('both packs are described the same way, and the rate appears before the count is typed',
      (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildScreen([qishta]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.calculate_outlined));
    await tester.pumpAndSettle();

    expect(find.text('من العقد'), findsOneWidget);
    expect(find.text('من الفاتورة'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'شد'), findsNWidgets(2),
        reason: 'a pack is a unit size + شد on both sides');

    // عقد: 1 كرتون = 170 جم × 48. Both wheels default to كجم, so type the
    // sizes in kilograms: 0.17 × 48 = 8.16 كجم per registered كرتون.
    await tester.enterText(find.widgetWithText(TextField, '1 كرتون ='), '0.17');
    await tester.enterText(find.widgetWithText(TextField, 'شد').first, '48');
    // فاتورة: the pack actually bought is 0.25 كجم × 48 = 12 كجم.
    await tester.enterText(find.widgetWithText(TextField, '1 عبوة مشتراة ='), '0.25');
    await tester.enterText(find.widgetWithText(TextField, 'شد').last, '48');
    await tester.pumpAndSettle();

    // 12 / 8.16 ≈ 1.4706 -- shown before any count is entered.
    expect(find.textContaining('معدل التحويل: 1 عبوة مشتراة = 1.4706'), findsOneWidget);
    expect(find.text('أدخل عدد العبوات المشتراة لمعاينة الناتج'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'كم عبوة اشتريت؟'), '10');
    await tester.pumpAndSettle();

    // 1.4706 × 10 ≈ 14.71 registered كرتون.
    expect(find.textContaining('= 14.71'), findsOneWidget);
  });

  testWidgets("a registered unit whose name is already a size isn't echoed twice in the result",
      (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildScreen([rice]));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.calculate_outlined));
    await tester.pumpAndSettle();

    // Ahmed's own example: the عقد's bag is 40 كجم, the bags actually
    // bought are 60 كجم, and 8 of them were bought -- (60/40) × 8 = 12,
    // shown bare, not "12 40 كجم".
    await tester.enterText(find.widgetWithText(TextField, '1 40 كجم ='), '40');
    await tester.enterText(find.widgetWithText(TextField, '1 عبوة مشتراة ='), '60');
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'كم عبوة اشتريت؟'), '8');
    await tester.pumpAndSettle();

    expect(find.text('= 12'), findsOneWidget);
  });
}
