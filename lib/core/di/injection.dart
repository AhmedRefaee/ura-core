import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../cache/local_profile_source.dart';
import '../notifications/notification_service.dart';
import '../../features/notifications/data/notifications_repository.dart';
import '../../features/notifications/logic/chat_badge_cubit.dart';
import '../../features/notifications/logic/notifications_badge_cubit.dart';
import '../../features/notifications/logic/notifications_cubit.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/logic/auth_cubit.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../features/settings/logic/theme_cubit.dart';
import '../../features/verifier/data/entity_repository.dart';
import '../../features/verifier/data/inventory_repository.dart';
import '../../features/verifier/data/order_repository.dart';
import '../../features/verifier/data/order_template_repository.dart';
import '../../features/verifier/data/local_item_match_repository.dart';
import '../../features/verifier/data/item_match_repository.dart';
import '../../features/verifier/logic/create_order_cubit.dart';
import '../../features/verifier/logic/order_templates_cubit.dart';
import '../../features/verifier/logic/edit_order_cubit.dart';
import '../../features/verifier/logic/orders_cubit.dart';
import '../../features/verifier/logic/ai_add_item_cubit.dart';
import '../../features/templates/logic/template_editor_cubit.dart';
import '../../features/templates/logic/template_management_cubit.dart';
import '../../features/rep/data/rep_orders_repository.dart';
import '../../features/rep/logic/rep_orders_cubit.dart';
import '../../features/rep/logic/rep_order_detail_cubit.dart';
import '../../features/storage/data/storage_repository.dart';
import '../../features/storage/logic/storage_order_detail_cubit.dart';
import '../../features/storage/logic/storage_orders_cubit.dart';
import '../../features/manager/data/manager_repository.dart';
import '../../features/manager/data/stats_repository.dart';
import '../../features/manager/logic/manager_pending_users_cubit.dart';
import '../../features/manager/logic/monitor_orders_cubit.dart';
import '../../features/manager/logic/rep_list_cubit.dart';
import '../../features/manager/logic/stats_cubit.dart';
import '../../features/manager/logic/task_detail_cubit.dart';
import '../../features/manager/logic/user_orders_cubit.dart';
import '../../features/manager/logic/user_type_cubit.dart';
import '../../features/inventory/data/inventory_management_repository.dart';
import '../../features/inventory/logic/bulk_edit_excel_cubit.dart';
import '../../features/inventory/logic/import_items_cubit.dart';
import '../../features/inventory/logic/inventory_bulk_cubit.dart';
import '../../features/inventory/logic/inventory_detail_cubit.dart';
import '../../features/inventory/logic/inventory_form_cubit.dart';
import '../../features/inventory/logic/inventory_list_cubit.dart';
import '../../features/chat/data/chat_repository.dart';
import '../../features/chat/logic/chat_directory_cubit.dart';
import '../../features/chat/logic/chat_threads_cubit.dart';
import '../../features/chat/logic/order_chat_badge_cubit.dart';
import '../../features/entities/logic/entities_cubit.dart';
import '../../features/entities/logic/import_entities_cubit.dart';
import '../../features/admin/data/admin_repository.dart';
import '../../features/admin/logic/admin_cubit.dart';
import '../../shared/models/inventory_item.dart';
import '../../shared/models/order_template.dart';

final sl = GetIt.instance;

Future<void> setupDependencies() async {
  final prefs = await SharedPreferences.getInstance();

  sl.registerLazySingleton<LocalProfileSource>(() => LocalProfileSource(prefs));
  sl.registerLazySingleton<NotificationService>(() => NotificationService());
  sl.registerLazySingleton<SettingsRepository>(() => SettingsRepository(prefs));
  sl.registerLazySingleton<ThemeCubit>(() => ThemeCubit(sl<SettingsRepository>()));
  sl.registerLazySingleton<NotificationsRepository>(() => NotificationsRepository());
  sl.registerLazySingleton<NotificationsBadgeCubit>(
    () => NotificationsBadgeCubit(sl<NotificationsRepository>()),
  );
  sl.registerLazySingleton<ChatBadgeCubit>(
    () => ChatBadgeCubit(sl<NotificationsRepository>()),
  );
  sl.registerFactory<NotificationsCubit>(
    () => NotificationsCubit(sl<NotificationsRepository>()),
  );

  // Repositories
  sl.registerLazySingleton<AuthRepository>(() => AuthRepository());
  sl.registerLazySingleton<OrderRepository>(() => OrderRepository());
  sl.registerLazySingleton<EntityRepository>(() => EntityRepository());
  sl.registerLazySingleton<InventoryRepository>(() => InventoryRepository());
  sl.registerLazySingleton<OrderTemplateRepository>(() => OrderTemplateRepository());
  sl.registerLazySingleton<RepOrdersRepository>(() => RepOrdersRepository());
  sl.registerLazySingleton<ChatRepository>(() => ChatRepository());
  // Matches on the device against the inventory the screen already holds: no
  // network call, no quota, no waiting. Three implementations satisfy this one
  // interface, so switching is this single line:
  //
  //   LocalItemMatchRepository()  — on-device, instant, free (current)
  //   DirectItemMatchRepository() — Gemini via Firebase AI Logic
  //   EdgeItemMatchRepository()   — Gemini via the Supabase function
  //
  // The other two need their import added back; both files are still here.
  //
  // The Gemini paths read better on messy prose and on items phrased nothing
  // like their catalog names. They also cost a request each and answered in
  // roughly a minute on the free tier. Everything either path returns lands in
  // the same review step in front of the verifier before it becomes an order.
  sl.registerLazySingleton<ItemMatchRepository>(
    () => LocalItemMatchRepository(),
  );

  // Chat cubits (singleton badge cubit; factory threads + directory cubits)
  sl.registerLazySingleton<OrderChatBadgeCubit>(
    () => OrderChatBadgeCubit(sl<ChatRepository>()),
  );
  sl.registerFactory<ChatThreadsCubit>(
    () => ChatThreadsCubit(sl<ChatRepository>()),
  );
  sl.registerFactory<ChatDirectoryCubit>(
    () => ChatDirectoryCubit(sl<ChatRepository>()),
  );

  // Auth & Orders
  sl.registerFactory<AuthCubit>(
    () => AuthCubit(sl<AuthRepository>(), sl<LocalProfileSource>()),
  );
  sl.registerFactory<OrdersCubit>(() => OrdersCubit(sl<OrderRepository>()));
  sl.registerFactory<CreateOrderCubit>(() => CreateOrderCubit(
        sl<OrderRepository>(),
        sl<EntityRepository>(),
        sl<InventoryRepository>(),
        sl<OrderTemplateRepository>(),
      ));
  sl.registerFactory<OrderTemplatesCubit>(
    () => OrderTemplatesCubit(sl<OrderTemplateRepository>()),
  );
  sl.registerFactory<TemplateManagementCubit>(
    () => TemplateManagementCubit(
      sl<OrderTemplateRepository>(),
      sl<EntityRepository>(),
    ),
  );
  sl.registerFactoryParam<TemplateEditorCubit, OrderTemplate?, void>(
    (template, _) => TemplateEditorCubit(
      sl<EntityRepository>(),
      sl<OrderRepository>(),
      sl<InventoryRepository>(),
      sl<OrderTemplateRepository>(),
      template,
    ),
  );
  sl.registerFactoryParam<EditOrderCubit, String, void>(
    (orderId, _) => EditOrderCubit(
      sl<OrderRepository>(),
      sl<InventoryRepository>(),
      orderId,
    ),
  );
  sl.registerFactory<AiAddItemCubit>(
    () => AiAddItemCubit(sl<ItemMatchRepository>()),
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
  sl.registerFactory<ImportItemsCubit>(
    () => ImportItemsCubit(sl<InventoryManagementRepository>()),
  );
  sl.registerFactory<BulkEditExcelCubit>(
    () => BulkEditExcelCubit(sl<InventoryManagementRepository>()),
  );

  // Manager
  sl.registerLazySingleton<ManagerRepository>(() => ManagerRepository());
  sl.registerLazySingleton<StatsRepository>(() => StatsRepository());
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
  sl.registerFactoryParam<TaskDetailCubit, String, bool>(
    (orderId, useVerifierRepository) => TaskDetailCubit(
      sl<ManagerRepository>(),
      orderId,
      sl<OrderRepository>(),
      useVerifierRepository: useVerifierRepository,
    ),
  );
  sl.registerFactory<StatsCubit>(
    () => StatsCubit(sl<StatsRepository>()),
  );

  // Admin (platform-admin console)
  sl.registerLazySingleton<AdminRepository>(() => AdminRepository());
  sl.registerFactory<AdminCubit>(() => AdminCubit(sl<AdminRepository>()));

  // Entities
  sl.registerFactory<EntitiesCubit>(
    () => EntitiesCubit(sl<EntityRepository>()),
  );
  sl.registerFactory<ImportEntitiesCubit>(
    () => ImportEntitiesCubit(sl<EntityRepository>()),
  );
}
