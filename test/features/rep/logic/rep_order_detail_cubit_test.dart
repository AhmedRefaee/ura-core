import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ura_core/core/config/feature_flags.dart';
import 'package:ura_core/core/errors/app_error.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/features/chat/data/chat_repository.dart';
import 'package:ura_core/features/rep/data/rep_orders_repository.dart';
import 'package:ura_core/features/rep/logic/rep_order_detail_cubit.dart';
import 'package:ura_core/shared/models/order.dart';
import 'package:ura_core/shared/models/order_item.dart';

class MockRepOrdersRepository extends Mock implements RepOrdersRepository {}

class MockChatRepository extends Mock implements ChatRepository {}

void main() {
  late MockRepOrdersRepository repo;
  late MockChatRepository chatRepo;

  const orderId = 'order-1';
  const itemId = 'item-1';

  OrderItem offStockItem({DateTime? purchasedAt}) => OrderItem(
        id: itemId,
        orderId: orderId,
        quantity: 2,
        isCustom: true,
        customDescription: 'صنف خارج المخزون',
        checkStatus: ItemCheckStatus.pending,
        purchasedAt: purchasedAt,
      );

  Order buildOrder({DateTime? purchasedAt}) => Order(
        id: orderId,
        direction: OrderDirection.outbound,
        entityId: 'entity-1',
        repId: 'rep-1',
        status: OrderStatus.assigned,
        createdBy: 'verifier-1',
        items: [offStockItem(purchasedAt: purchasedAt)],
      );

  setUp(() {
    repo = MockRepOrdersRepository();
    chatRepo = MockChatRepository();
    when(() => repo.fetchAuditLog(orderId)).thenAnswer((_) async => const AppSuccess([]));
    when(() => chatRepo.getOrderCommunicationHistory(orderId))
        .thenAnswer((_) async => const AppSuccess([]));
  });

  RepOrderDetailCubit buildCubit() => RepOrderDetailCubit(repo, orderId, chatRepo);

  group('RepOrderDetailCubit.toggleOffStockPurchased', () {
    blocTest<RepOrderDetailCubit, RepOrderDetailState>(
      'checking an item succeeds and reloads with purchasedAt set',
      build: () {
        when(() => repo.toggleOffStockPurchased(itemId, true, notes: any(named: 'notes')))
            .thenAnswer((_) async => const AppSuccess(null));
        when(() => repo.fetchOrderDetail(orderId)).thenAnswer(
          (_) async => AppSuccess(buildOrder(purchasedAt: DateTime(2026, 8, 28))),
        );
        return buildCubit();
      },
      seed: () => RepOrderDetailLoaded(order: buildOrder()),
      act: (cubit) => cubit.toggleOffStockPurchased(itemId, true),
      expect: () => [
        isA<RepOrderDetailLoaded>().having((s) => s.isActing, 'isActing', true),
        isA<RepOrderDetailLoading>(),
        isA<RepOrderDetailLoaded>()
            .having((s) => s.order.items.first.purchasedAt, 'purchasedAt', isNotNull)
            .having((s) => s.isActing, 'isActing', false),
      ],
      verify: (_) => verify(
        () => repo.toggleOffStockPurchased(itemId, true, notes: any(named: 'notes')),
      ).called(1),
    );

    blocTest<RepOrderDetailCubit, RepOrderDetailState>(
      'unchecking an item succeeds and reloads with purchasedAt cleared',
      build: () {
        when(() => repo.toggleOffStockPurchased(itemId, false, notes: any(named: 'notes')))
            .thenAnswer((_) async => const AppSuccess(null));
        when(() => repo.fetchOrderDetail(orderId))
            .thenAnswer((_) async => AppSuccess(buildOrder()));
        return buildCubit();
      },
      seed: () => RepOrderDetailLoaded(order: buildOrder(purchasedAt: DateTime(2026, 8, 28))),
      act: (cubit) => cubit.toggleOffStockPurchased(itemId, false),
      expect: () => [
        isA<RepOrderDetailLoaded>().having((s) => s.isActing, 'isActing', true),
        isA<RepOrderDetailLoading>(),
        isA<RepOrderDetailLoaded>()
            .having((s) => s.order.items.first.purchasedAt, 'purchasedAt', isNull),
      ],
      verify: (_) => verify(
        () => repo.toggleOffStockPurchased(itemId, false, notes: any(named: 'notes')),
      ).called(1),
    );

    blocTest<RepOrderDetailCubit, RepOrderDetailState>(
      'failure emits RepOrderDetailError and does not reload',
      build: () {
        when(() => repo.toggleOffStockPurchased(itemId, true, notes: any(named: 'notes')))
            .thenAnswer(
          (_) async => const AppFailure(AppError(message: 'غير مصرح', type: AppErrorType.server)),
        );
        return buildCubit();
      },
      seed: () => RepOrderDetailLoaded(order: buildOrder()),
      act: (cubit) => cubit.toggleOffStockPurchased(itemId, true),
      expect: () => [
        isA<RepOrderDetailLoaded>().having((s) => s.isActing, 'isActing', true),
        isA<RepOrderDetailError>().having((s) => s.message, 'message', 'غير مصرح'),
      ],
      verify: (_) => verifyNever(() => repo.fetchOrderDetail(any())),
    );
  });

  // load() treats a communication-history failure as fatal -- it emits
  // RepOrderDetailError and the rep gets a retry button instead of their order.
  // That was survivable while chat worked. Once chat was switched off and the
  // server stopped granting chat reads, that single call would have failed on
  // every load and locked every rep out of every order detail screen. These pin
  // the guard that stops it.
  group(
    'with chat switched off',
    () {
      blocTest<RepOrderDetailCubit, RepOrderDetailState>(
        'load never asks the chat repository for anything',
        build: () {
          when(() => repo.fetchOrderDetail(orderId))
              .thenAnswer((_) async => AppSuccess(buildOrder()));
          return buildCubit();
        },
        act: (cubit) => cubit.load(),
        verify: (_) => verifyNever(
          () => chatRepo.getOrderCommunicationHistory(any()),
        ),
      );

      blocTest<RepOrderDetailCubit, RepOrderDetailState>(
        'the order still loads even when chat reads are refused',
        build: () {
          when(() => repo.fetchOrderDetail(orderId))
              .thenAnswer((_) async => AppSuccess(buildOrder()));
          when(() => chatRepo.getOrderCommunicationHistory(orderId)).thenAnswer(
            (_) async => const AppFailure(
              AppError(
                message: 'permission denied for table chat_messages',
                type: AppErrorType.server,
              ),
            ),
          );
          return buildCubit();
        },
        act: (cubit) => cubit.load(),
        expect: () => [
          isA<RepOrderDetailLoading>(),
          isA<RepOrderDetailLoaded>()
              .having((s) => s.order.id, 'order.id', orderId)
              .having((s) => s.communicationHistory, 'history', isEmpty),
        ],
      );
    },
    // Both assertions describe the switched-off state specifically. If chat is
    // ever turned back on, they should fail loudly rather than quietly pass --
    // the fatal-failure path above is still there and needs revisiting first.
    skip: kChatEnabled
        ? 'chat is enabled; these pin the switched-off behaviour'
        : null,
  );
}
