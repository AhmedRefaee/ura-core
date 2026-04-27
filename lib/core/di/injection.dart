import 'package:get_it/get_it.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/logic/auth_cubit.dart';
import '../../features/verifier/data/entity_repository.dart';
import '../../features/verifier/data/inventory_repository.dart';
import '../../features/verifier/data/order_repository.dart';
import '../../features/verifier/logic/create_order_cubit.dart';
import '../../features/verifier/logic/edit_order_cubit.dart';
import '../../features/verifier/logic/orders_cubit.dart';
import '../../features/rep/data/rep_orders_repository.dart';
import '../../features/rep/logic/rep_orders_cubit.dart';
import '../../features/rep/logic/rep_order_detail_cubit.dart';
import '../../features/storage/data/storage_repository.dart';
import '../../features/storage/logic/storage_order_detail_cubit.dart';
import '../../features/storage/logic/storage_orders_cubit.dart';
import '../../features/manager/data/manager_repository.dart';
import '../../features/manager/logic/manager_pending_users_cubit.dart';
import '../../features/manager/logic/monitor_orders_cubit.dart';
import '../../features/manager/logic/rep_list_cubit.dart';
import '../../features/manager/logic/task_detail_cubit.dart';
import '../../features/manager/logic/user_orders_cubit.dart';
import '../../features/manager/logic/user_type_cubit.dart';
import '../../features/inventory/data/inventory_management_repository.dart';
import '../../features/inventory/logic/inventory_bulk_cubit.dart';
import '../../features/inventory/logic/inventory_detail_cubit.dart';
import '../../features/inventory/logic/inventory_form_cubit.dart';
import '../../features/inventory/logic/inventory_list_cubit.dart';
import '../../features/chat/data/chat_repository.dart';
import '../../features/chat/logic/chat_threads_cubit.dart';
import '../../features/chat/logic/order_chat_badge_cubit.dart';
import '../../shared/models/inventory_item.dart';

final sl = GetIt.instance;

Future<void> setupDependencies() async {
  // Repositories
  sl.registerLazySingleton<AuthRepository>(() => AuthRepository());
  sl.registerLazySingleton<OrderRepository>(() => OrderRepository());
  sl.registerLazySingleton<EntityRepository>(() => EntityRepository());
  sl.registerLazySingleton<InventoryRepository>(() => InventoryRepository());
  sl.registerLazySingleton<RepOrdersRepository>(() => RepOrdersRepository());
  sl.registerLazySingleton<ChatRepository>(() => ChatRepository());

  // Chat cubits (singleton badge cubit; factory threads cubit)
  sl.registerLazySingleton<OrderChatBadgeCubit>(
    () => OrderChatBadgeCubit(sl<ChatRepository>()),
  );
  sl.registerFactory<ChatThreadsCubit>(
    () => ChatThreadsCubit(sl<ChatRepository>()),
  );

  // Auth & Orders
  sl.registerFactory<AuthCubit>(() => AuthCubit(sl<AuthRepository>()));
  sl.registerFactory<OrdersCubit>(() => OrdersCubit(sl<OrderRepository>()));
  sl.registerFactory<CreateOrderCubit>(() => CreateOrderCubit(
        sl<OrderRepository>(),
        sl<EntityRepository>(),
        sl<InventoryRepository>(),
      ));
  sl.registerFactoryParam<EditOrderCubit, String, void>(
    (orderId, _) => EditOrderCubit(
      sl<OrderRepository>(),
      sl<InventoryRepository>(),
      orderId,
    ),
  );

  // Rep
  sl.registerFactory<RepOrdersCubit>(() => RepOrdersCubit(sl<RepOrdersRepository>()));
  sl.registerFactoryParam<RepOrderDetailCubit, String, void>(
    (orderId, _) => RepOrderDetailCubit(
      sl<RepOrdersRepository>(),
      orderId,
      sl<ChatRepository>(),
    ),
  );

  // Storage
  sl.registerLazySingleton<StorageRepository>(() => StorageRepository());
  sl.registerFactory<StorageOrdersCubit>(
    () => StorageOrdersCubit(sl<StorageRepository>()),
  );
  sl.registerFactoryParam<StorageOrderDetailCubit, String, void>(
    (orderId, _) => StorageOrderDetailCubit(sl<StorageRepository>(), orderId),
  );

  // Inventory
  sl.registerLazySingleton<InventoryManagementRepository>(
    () => InventoryManagementRepository(),
  );
  sl.registerFactory<InventoryListCubit>(
    () => InventoryListCubit(sl<InventoryManagementRepository>()),
  );
  sl.registerFactoryParam<InventoryDetailCubit, String, void>(
    (itemId, _) => InventoryDetailCubit(sl<InventoryManagementRepository>(), itemId),
  );
  sl.registerFactoryParam<InventoryFormCubit, InventoryItem?, void>(
    (item, _) => InventoryFormCubit(sl<InventoryManagementRepository>(), initialItem: item),
  );
  sl.registerFactory<InventoryBulkCubit>(
    () => InventoryBulkCubit(sl<InventoryManagementRepository>()),
  );

  // Manager
  sl.registerLazySingleton<ManagerRepository>(() => ManagerRepository());
  sl.registerFactory<MonitorOrdersCubit>(
    () => MonitorOrdersCubit(sl<ManagerRepository>()),
  );
  sl.registerFactory<ManagerPendingUsersCubit>(
    () => ManagerPendingUsersCubit(sl<ManagerRepository>()),
  );
  sl.registerFactory<UserTypeCubit>(
    () => UserTypeCubit(sl<ManagerRepository>()),
  );
  sl.registerFactory<RepListCubit>(
    () => RepListCubit(sl<ManagerRepository>()),
  );
  sl.registerFactory<UserOrdersCubit>(
    () => UserOrdersCubit(sl<ManagerRepository>()),
  );
  sl.registerFactoryParam<TaskDetailCubit, String, void>(
    (orderId, _) => TaskDetailCubit(sl<ManagerRepository>(), orderId),
  );
}
