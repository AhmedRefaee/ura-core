import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/features/chat/data/chat_repository.dart';
import 'package:ura_core/features/rep/data/rep_orders_repository.dart';
import 'package:ura_core/features/rep/logic/rep_order_detail_cubit.dart';
import 'package:ura_core/features/rep/ui/rep_order_detail_screen.dart';
import 'package:ura_core/shared/models/order.dart';
import 'package:ura_core/shared/models/order_item.dart';

class MockRepOrdersRepository extends Mock implements RepOrdersRepository {}

class MockChatRepository extends Mock implements ChatRepository {}

void main() {
  late MockRepOrdersRepository repo;
  late MockChatRepository chatRepo;
  const orderId = 'order-1';

  setUp(() {
    repo = MockRepOrdersRepository();
    chatRepo = MockChatRepository();
    when(() => repo.fetchAuditLog(orderId)).thenAnswer((_) async => const AppSuccess([]));
    when(() => chatRepo.getOrderCommunicationHistory(orderId))
        .thenAnswer((_) async => const AppSuccess([]));
  });

  OrderItem realItem() => const OrderItem(
        id: 'item-real',
        orderId: orderId,
        inventoryId: 'inv-1',
        inventoryName: 'مياه',
        quantity: 5,
        isCustom: false,
        checkStatus: ItemCheckStatus.pending,
      );

  OrderItem offStockItem({DateTime? purchasedAt}) => OrderItem(
        id: 'item-off',
        orderId: orderId,
        quantity: 2,
        isCustom: true,
        customDescription: 'صنف خارج المخزون',
        checkStatus: ItemCheckStatus.pending,
        purchasedAt: purchasedAt,
      );

  Order buildOrder({
    required List<OrderItem> items,
    OrderDirection direction = OrderDirection.outbound,
    OrderStatus status = OrderStatus.assigned,
  }) =>
      Order(
        id: orderId,
        direction: direction,
        entityId: 'entity-1',
        repId: 'rep-1',
        status: status,
        createdBy: 'verifier-1',
        items: items,
      );

  Future<RepOrderDetailCubit> loadedCubit(Order order) async {
    when(() => repo.fetchOrderDetail(orderId)).thenAnswer((_) async => AppSuccess(order));
    final cubit = RepOrderDetailCubit(repo, orderId, chatRepo);
    await cubit.load();
    return cubit;
  }

  Widget wrap(RepOrderDetailCubit cubit) => MaterialApp(
        home: BlocProvider.value(value: cubit, child: const RepOrderDetailScreen()),
      );

  // The screen's body is a plain ListView (SliverList), which only builds
  // children within the viewport extent -- the checklist section sits below
  // the stepper/timeline/items, well past the default 800x600 test surface.
  // Grow the surface instead of scrolling, so every section is actually
  // mounted and findable.
  Future<void> pumpTall(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
  }

  testWidgets(
    'Flow 2 (all off-stock) order at assigned status starts moving directly, no pickup step',
    (tester) async {
      final cubit = await loadedCubit(buildOrder(items: [offStockItem()]));
      when(() => repo.startMove(orderId, notes: any(named: 'notes')))
          .thenAnswer((_) async => const AppSuccess(null));

      await pumpTall(tester, wrap(cubit));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'ابدأ التنقل'), findsOneWidget);
      expect(find.text('تأكيد الاستلام'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'ابدأ التنقل'));
      await tester.pumpAndSettle();

      verify(() => repo.startMove(orderId, notes: any(named: 'notes'))).called(1);
      verifyNever(() => repo.markPickedUp(any(), notes: any(named: 'notes')));
    },
  );

  testWidgets(
    'inboundRep order at assigned status still shows تأكيد الاستلام (unaffected by the Flow 2 change)',
    (tester) async {
      final cubit = await loadedCubit(
        buildOrder(items: [offStockItem()], direction: OrderDirection.inboundRep),
      );
      await pumpTall(tester, wrap(cubit));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'تأكيد الاستلام'), findsOneWidget);
      expect(find.text('ابدأ التنقل'), findsNothing);
    },
  );

  testWidgets('hidden when the order has no off-stock items', (tester) async {
    final cubit = await loadedCubit(buildOrder(items: [realItem()]));
    await pumpTall(tester, wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('hidden for inbound directions even with off-stock items', (tester) async {
    final cubit = await loadedCubit(
      buildOrder(items: [offStockItem()], direction: OrderDirection.inboundRep),
    );
    await pumpTall(tester, wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('shown with one checkbox per off-stock item on a mixed order', (tester) async {
    final cubit = await loadedCubit(buildOrder(items: [realItem(), offStockItem()]));
    await pumpTall(tester, wrap(cubit));
    await tester.pumpAndSettle();

    expect(find.byType(CheckboxListTile), findsOneWidget);
    final tile = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(tile.value, isFalse);
  });

  testWidgets('checkbox reflects purchasedAt and toggling calls the cubit', (tester) async {
    final cubit = await loadedCubit(
      buildOrder(items: [offStockItem(purchasedAt: DateTime(2026, 8, 28))]),
    );
    when(() => repo.toggleOffStockPurchased('item-off', false, notes: any(named: 'notes')))
        .thenAnswer((_) async => const AppSuccess(null));

    await pumpTall(tester, wrap(cubit));
    await tester.pumpAndSettle();

    final tile = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(tile.value, isTrue);
    expect(tile.onChanged, isNotNull);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    verify(() => repo.toggleOffStockPurchased('item-off', false, notes: any(named: 'notes')))
        .called(1);
  });

  testWidgets('read-only with a note once the order is delivered', (tester) async {
    final cubit = await loadedCubit(
      buildOrder(items: [offStockItem()], status: OrderStatus.delivered),
    );
    await pumpTall(tester, wrap(cubit));
    await tester.pumpAndSettle();

    final tile = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(tile.onChanged, isNull);
    expect(find.text('تم تسليم الطلب — هذا السجل للعرض فقط'), findsOneWidget);
  });
}
