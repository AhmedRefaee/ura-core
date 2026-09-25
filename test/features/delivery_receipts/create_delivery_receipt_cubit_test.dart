import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/features/delivery_receipts/data/delivery_receipt_repository.dart';
import 'package:ura_core/features/delivery_receipts/data/delivery_receipt_storage_service.dart';
import 'package:ura_core/features/delivery_receipts/logic/create_delivery_receipt_cubit.dart';
import 'package:ura_core/features/projects/data/project_repository.dart';
import 'package:ura_core/features/verifier/data/entity_repository.dart';
import 'package:ura_core/shared/models/entity.dart';
import 'package:ura_core/shared/models/project.dart';
import 'package:ura_core/shared/models/project_item.dart';

class MockEntityRepository extends Mock implements EntityRepository {}

class MockProjectRepository extends Mock implements ProjectRepository {}

class MockDeliveryReceiptRepository extends Mock implements DeliveryReceiptRepository {}

class MockDeliveryReceiptStorageService extends Mock implements DeliveryReceiptStorageService {}

void main() {
  const entity = Entity(id: 'e1', name: 'وزارة', category: EntityCategory.outgoing);
  const projectA = Project(id: 'p1', entityId: 'e1', name: 'مشروع أ');
  const projectB = Project(id: 'p2', entityId: 'e1', name: 'مشروع ب');
  const item = ProjectItem(id: 'i1', projectId: 'p2', itemName: 'كرسي', quantity: 10, unit: 'حبة');

  late MockEntityRepository entities;
  late MockProjectRepository projects;

  CreateDeliveryReceiptCubit build(DeliveryReceiptLaunch launch) => CreateDeliveryReceiptCubit(
        entities,
        projects,
        MockDeliveryReceiptRepository(),
        MockDeliveryReceiptStorageService(),
        launch,
      );

  setUp(() {
    entities = MockEntityRepository();
    projects = MockProjectRepository();
    when(() => entities.fetchEntities()).thenAnswer((_) async => const AppSuccess([entity]));
    when(() => projects.fetchProjectsForEntity('e1'))
        .thenAnswer((_) async => const AppSuccess([projectA, projectB]));
    when(() => projects.fetchProjectItems(any())).thenAnswer((_) async => const AppSuccess([item]));
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
