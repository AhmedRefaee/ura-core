import 'dart:typed_data';
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
import 'package:ura_core/features/project_share/data/project_share_repository.dart';
import 'package:ura_core/features/project_share/models/shared_project.dart';
import 'package:ura_core/features/projects/data/project_repository.dart';
import 'package:ura_core/features/verifier/data/entity_repository.dart';
import 'package:ura_core/shared/models/delivery_receipt.dart';

class MockProjectShareRepository extends Mock implements ProjectShareRepository {}

class MockEntityRepository extends Mock implements EntityRepository {}

class MockProjectRepository extends Mock implements ProjectRepository {}

class MockDeliveryReceiptRepository extends Mock implements DeliveryReceiptRepository {}

class MockDeliveryReceiptStorageService extends Mock implements DeliveryReceiptStorageService {}

class MockDeliveryReceiptDraftRepository extends Mock implements DeliveryReceiptDraftRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(Uint8List(0)));

  final shared = SharedProject.fromMap({
    'project_name': 'مشروع الإعاشة',
    'entity_name': 'وزارة الصحة',
    'letterhead_path': null,
    'can_submit': true,
    'items': [
      {
        'id': 'i1',
        'category': 'الألبان',
        'item_name': 'لبنة',
        'description': 'جودة عالية / كرتون 2.75*4كيلو جرام',
        'unit': 'كرتون',
        'packaging_unit_size': 2.75,
        'packaging_unit_count': 4,
        'packaging_base_unit': 'kilogram',
      },
      {'id': 'i2', 'category': 'المخبوزات', 'item_name': 'خبز', 'description': null, 'unit': 'كيس'},
    ],
  });

  late MockProjectShareRepository share;
  late MockEntityRepository entities;
  late MockProjectRepository projects;
  late MockDeliveryReceiptRepository receipts;
  late MockDeliveryReceiptStorageService storage;

  CreateDeliveryReceiptCubit build() => CreateDeliveryReceiptCubit(
        entities,
        projects,
        receipts,
        storage,
        MockDeliveryReceiptDraftRepository(),
        DeliveryReceiptLaunch.portal(
          PortalLaunch(token: 'tok', project: shared, submitterName: 'سالم', submitterPhone: '0500000000'),
        ),
        share: share,
      );

  setUp(() {
    share = MockProjectShareRepository();
    entities = MockEntityRepository();
    projects = MockProjectRepository();
    receipts = MockDeliveryReceiptRepository();
    storage = MockDeliveryReceiptStorageService();
  });

  group('SharedProject → سند screen shapes', () {
    test('items carry ids, packaging and category but never a quantity', () {
      final items = shared.asProjectItems;
      expect(items.map((i) => i.id), ['i1', 'i2']);
      expect(items.every((i) => i.quantity == 0), isTrue);
      expect(items.every((i) => i.unitPrice == null && i.totalPrice == null), isTrue);
      expect(items.first.packagingUnitSize, 2.75);
      expect(items.first.packagingBaseUnit, 'kilogram');
      expect(items.first.category, 'الألبان');
    });

    test('parses the submitter\'s own list with status, meta and lines', () {
      final r = SharedReceipt.fromMap({
        'id': 'r1',
        'status': 'pending',
        'created_at': '2026-10-19T08:00:00Z',
        'submitter_name': 'سالم',
        'notes': null,
        'meta': {'date_mode': 'custom', 'custom_date': '2026-10-25', 'full_description': true},
        'items': [
          {'project_item_id': 'i1', 'item_name': 'لبنة', 'unit': 'كرتون', 'quantity': 3, 'notes': 'تالف'},
        ],
      });
      expect(r.status, ReceiptStatus.pending);
      expect(r.dateMode, 'custom');
      expect(r.customDate, DateTime(2026, 10, 25));
      expect(r.fullDescription, isTrue);
      expect(r.lines.single.quantity, 3);
      expect(r.lines.single.notes, 'تالف');
    });

    test('a portal DeliveryReceipt has no rep and is recognised as a submission', () {
      final r = DeliveryReceipt.fromMap({
        'id': 'r1',
        'entity_id': 'e',
        'project_id': 'p',
        'rep_id': null,
        'status': 'pending',
        'source_link_id': 'l1',
        'submitter_name': 'سالم',
        'submitter_phone': '050',
      });
      expect(r.repId, isNull);
      expect(r.status, ReceiptStatus.pending);
      expect(r.isPortalSubmission, isTrue);
    });
  });

  group('portal mode cubit', () {
    test('starts on the items step with no server round-trips', () async {
      final cubit = build();
      await cubit.init();

      expect(cubit.state.entity?.name, 'وزارة الصحة');
      expect(cubit.state.project?.name, 'مشروع الإعاشة');
      expect(cubit.state.items.map((i) => i.id), ['i1', 'i2']);
      expect(cubit.state.loading, isFalse);
      verifyNever(() => entities.fetchEntities());
      verifyNever(() => projects.fetchProjectItems(any()));
    });

    test('submit files a pending submission through the link -- no upload, no staff RPC', () async {
      when(() => share.submitReceipt(
            token: any(named: 'token'),
            submitterName: any(named: 'submitterName'),
            submitterPhone: any(named: 'submitterPhone'),
            items: any(named: 'items'),
            notes: any(named: 'notes'),
            meta: any(named: 'meta'),
          )).thenAnswer((_) async => const AppSuccess('r1'));

      final cubit = build();
      await cubit.init();
      cubit.setQuantity('i1', 3);
      cubit.setItemNote('i1', 'تالف');
      cubit.setCustomDate(DateTime(2026, 10, 25));
      cubit.setFullDescription(true);
      await cubit.submit();

      expect(cubit.state.error, isNull);
      expect(cubit.state.receiptId, 'r1');
      expect(cubit.state.pdfBytes, isA<Uint8List>());

      verify(() => share.submitReceipt(
            token: 'tok',
            submitterName: 'سالم',
            submitterPhone: '0500000000',
            items: [
              {'project_item_id': 'i1', 'quantity_delivered': 3.0, 'notes': 'تالف'},
            ],
            notes: any(named: 'notes'),
            meta: {'date_mode': 'custom', 'custom_date': '2026-10-25', 'full_description': true},
          )).called(1);
      verifyNever(() => storage.uploadPdf(any()));
      verifyNever(() => receipts.createDeliveryReceipt(
            entityId: any(named: 'entityId'),
            projectId: any(named: 'projectId'),
            items: any(named: 'items'),
          ));
    });

    test('split by category files one submission per category', () async {
      when(() => share.submitReceipt(
            token: any(named: 'token'),
            submitterName: any(named: 'submitterName'),
            submitterPhone: any(named: 'submitterPhone'),
            items: any(named: 'items'),
            notes: any(named: 'notes'),
            meta: any(named: 'meta'),
          )).thenAnswer((_) async => const AppSuccess('r'));

      final cubit = build();
      await cubit.init();
      cubit.setQuantity('i1', 1);
      cubit.setQuantity('i2', 2);
      cubit.setSplitByCategory(true);
      await cubit.submit();

      verify(() => share.submitReceipt(
            token: any(named: 'token'),
            submitterName: any(named: 'submitterName'),
            submitterPhone: any(named: 'submitterPhone'),
            items: any(named: 'items'),
            notes: any(named: 'notes'),
            meta: any(named: 'meta'),
          )).called(2);
      expect(cubit.state.totalReceiptsThisSubmit, 2);
    });
  });

  group('portal mode screen', () {
    testWidgets('lands on the items, offers calculator/notes UI, hides entity navigation and AI paste',
        (tester) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final cubit = build();
      await cubit.init();
      await tester.pumpWidget(MaterialApp(
        home: BlocProvider.value(value: cubit, child: const CreateDeliveryReceiptScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('لبنة', findRichText: true), findsOneWidget);
      expect(find.textContaining('خبز', findRichText: true), findsOneWidget);
      // Category filter chips are there.
      expect(find.text('الألبان'), findsWidgets);
      // No entity picker / AI paste in portal mode.
      expect(find.byIcon(Icons.content_paste_go), findsNothing);
      // The breadcrumb chips are not tappable.
      final chip = tester.widget<ActionChip>(find.widgetWithText(ActionChip, 'وزارة الصحة'));
      expect(chip.onPressed, isNull);
      // Submit bar says it goes for approval.
      cubit.setQuantity('i1', 1);
      await tester.pumpAndSettle();
      expect(find.text('إرسال للاعتماد'), findsOneWidget);
    });
  });
}
