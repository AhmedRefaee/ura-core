import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ura_core/core/errors/app_error.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/features/projects/data/project_repository.dart';
import 'package:ura_core/features/projects/data/project_storage_service.dart';
import 'package:ura_core/features/projects/logic/projects_cubit.dart';
import 'package:ura_core/shared/models/project.dart';

class MockProjectRepository extends Mock implements ProjectRepository {}

class MockProjectStorageService extends Mock implements ProjectStorageService {}

void main() {
  const a = Project(id: 'p1', entityId: 'e1', name: 'أ');
  const b = Project(id: 'p2', entityId: 'e1', name: 'ب');

  late MockProjectRepository repo;
  late ProjectsCubit cubit;

  setUp(() async {
    repo = MockProjectRepository();
    cubit = ProjectsCubit(repo, MockProjectStorageService());
    when(() => repo.fetchProjectsForEntity('e1')).thenAnswer((_) async => const AppSuccess([a, b]));
    await cubit.loadProjects('e1');
  });

  test('a deleted project leaves the list', () async {
    when(() => repo.deleteProject('p1')).thenAnswer((_) async => const AppSuccess(null));

    expect(await cubit.deleteProject(a), isNull);
    expect((cubit.state as ProjectsLoaded).projects, [b]);
  });

  test('a refused delete keeps the project and returns the reason', () async {
    when(() => repo.deleteProject('p1')).thenAnswer((_) async => const AppFailure(
          AppError(message: 'لا يمكن حذف المشروع لأن عليه سندات أو طلبات', type: AppErrorType.validation),
        ));

    expect(await cubit.deleteProject(a), contains('سندات'));
    expect((cubit.state as ProjectsLoaded).projects, [a, b]);
  });
}
