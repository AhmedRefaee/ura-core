import 'package:get_it/get_it.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/logic/auth_cubit.dart';
import '../../features/verifier/data/entity_repository.dart';
import '../../features/verifier/data/inventory_repository.dart';
import '../../features/verifier/data/order_repository.dart';
import '../../features/verifier/logic/create_order_cubit.dart';
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
import '../../features/manager/logic/task_detail_cubit.dart';
import '../../features/manager/logic/user_orders_cubit.dart';
import '../../features/manager/logic/user_type_cubit.dart';

final sl = GetIt.instance;

Future<void> setupDependencies() async {
  // Repositories
  sl.registerLazySingleton<AuthRepository>(() => AuthRepository());
  sl.registerLazySingleton<OrderRepository>(() => OrderRepository());
  sl.registerLazySingleton<EntityRepository>(() => EntityRepository());
  sl.registerLazySingleton<InventoryRepository>(() => InventoryRepository());
  sl.registerLazySingleton<RepOrdersRepository>(() => RepOrdersRepository());

  // Cubits
  sl.registerFactory<AuthCubit>(() => AuthCubit(sl<AuthRepository>()));
  sl.registerFactory<OrdersCubit>(() => OrdersCubit(sl<OrderRepository>()));
  sl.registerFactory<CreateOrderCubit>(() => CreateOrderCubit(
        sl<OrderRepository>(),
        sl<EntityRepository>(),
        sl<InventoryRepository>(),
      ));
  sl.registerFactory<RepOrdersCubit>(() => RepOrdersCubit(sl<RepOrdersRepository>()));
  sl.registerFactoryParam<RepOrderDetailCubit, String, void>(
    (orderId, _) => RepOrderDetailCubit(sl<RepOrdersRepository>(), orderId),
  );

  sl.registerLazySingleton<StorageRepository>(() => StorageRepository());
  sl.registerFactory<StorageOrdersCubit>(
    () => StorageOrdersCubit(sl<StorageRepository>()),
  );
  sl.registerFactoryParam<StorageOrderDetailCubit, String, void>(
    (orderId, _) => StorageOrderDetailCubit(sl<StorageRepository>(), orderId),
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
  sl.registerFactory<UserOrdersCubit>(
    () => UserOrdersCubit(sl<ManagerRepository>()),
  );
  sl.registerFactoryParam<TaskDetailCubit, String, void>(
    (orderId, _) => TaskDetailCubit(sl<ManagerRepository>(), orderId),
  );
}
