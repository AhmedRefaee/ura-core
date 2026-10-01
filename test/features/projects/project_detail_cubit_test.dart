import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ura_core/core/errors/app_error.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/features/projects/data/project_repository.dart';
import 'package:ura_core/features/projects/data/project_storage_service.dart';
import 'package:ura_core/features/projects/logic/project_detail_cubit.dart';
import 'package:ura_core/shared/models/project.dart';

class MockProjectRepository extends Mock implements ProjectRepository {}

class MockProjectStorageService extends Mock implements ProjectStorageService {}

void main() {
  const project = Project(
    id: 'p1',
    entityId: 'e1',
    name: 'مشروع',
    letterheadImageUrl: 'org1/p1/123.png',
  );

  late MockProjectRepository repo;
  late MockProjectStorageService storage;
  late ProjectDetailCubit cubit;

  setUp(() {
    repo = MockProjectRepository();
    storage = MockProjectStorageService();
    cubit = ProjectDetailCubit(repo, storage, project);
  });

  test('removeLetterhead clears it via clearLetterhead, not a value', () async {
    when(() => repo.updateProject(id: 'p1', clearLetterhead: true))
        .thenAnswer((_) async => const AppSuccess(Project(id: 'p1', entityId: 'e1', name: 'مشروع')));

    final error = await cubit.removeLetterhead();

    expect(error, isNull);
    expect(cubit.state.project.letterheadImageUrl, isNull);
    verify(() => repo.updateProject(id: 'p1', clearLetterhead: true)).called(1);
  });

  test('removeLetterhead surfaces a repository error without changing state', () async {
    when(() => repo.updateProject(id: 'p1', clearLetterhead: true)).thenAnswer(
      (_) async => const AppFailure(AppError(message: 'فشل', type: AppErrorType.server)),
    );

    final error = await cubit.removeLetterhead();

    expect(error, isNotNull);
    expect(cubit.state.project.letterheadImageUrl, 'org1/p1/123.png', reason: 'state must not change on failure');
  });
}
