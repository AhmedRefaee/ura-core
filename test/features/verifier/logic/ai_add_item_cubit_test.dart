import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ura_core/core/errors/app_error.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/features/verifier/data/item_match_repository.dart';
import 'package:ura_core/features/verifier/logic/ai_add_item_cubit.dart';
import 'package:ura_core/shared/models/inventory_item.dart';
import 'package:ura_core/shared/models/item_match_result.dart';

class MockItemMatchRepository extends Mock implements ItemMatchRepository {}

void main() {
  late MockItemMatchRepository repository;

  const water = InventoryItem(id: 'item-water', itemName: 'مياه نوفا 330 مل', quantity: 50, unit: 'كرتونة');
  const water500 = InventoryItem(id: 'item-water-500', itemName: 'مياه نوفا 500 مل', quantity: 30, unit: 'كرتونة');
  const soap = InventoryItem(id: 'item-soap', itemName: 'صابون', quantity: 20, unit: 'علبة');
  final inventory = [water, water500, soap];
  final audioBytes = Uint8List.fromList([1, 2, 3]);

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    repository = MockItemMatchRepository();
  });

  group('AiAddItemCubit', () {
    test('initial state is idle', () {
      expect(AiAddItemCubit(repository).state, isA<AiAddItemIdle>());
    });

    blocTest<AiAddItemCubit, AiAddItemState>(
      'startRecording emits Recording',
      build: () => AiAddItemCubit(repository),
      act: (cubit) => cubit.startRecording(),
      expect: () => [isA<AiAddItemRecording>()],
    );

    blocTest<AiAddItemCubit, AiAddItemState>(
      'updateElapsed emits Recording with the elapsed seconds',
      build: () => AiAddItemCubit(repository),
      act: (cubit) => cubit.updateElapsed(12),
      expect: () => [
        isA<AiAddItemRecording>().having((s) => s.elapsedSeconds, 'elapsedSeconds', 12),
      ],
    );

    blocTest<AiAddItemCubit, AiAddItemState>(
      'finishRecording with empty audio emits empty Reviewing state directly',
      build: () => AiAddItemCubit(repository),
      act: (cubit) => cubit.finishRecording(Uint8List(0), 'audio/aac', inventory),
      expect: () => [
        isA<AiAddItemReviewing>()
            .having((s) => s.matches, 'matches', isEmpty)
            .having((s) => s.unmatched, 'unmatched', isEmpty),
      ],
      verify: (_) => verifyNever(() => repository.matchAudio(any(), any())),
    );

    blocTest<AiAddItemCubit, AiAddItemState>(
      'finishRecording resolves matches against inventory, drops unknown ids, and carries heardSummary',
      build: () {
        when(() => repository.matchAudio(any(), any())).thenAnswer(
          (_) async => AppSuccess(
            ItemMatchResult(
              matches: const [
                MatchedItem(itemId: 'item-water', quantity: 3, confidence: 0.9),
                MatchedItem(itemId: 'item-unknown', quantity: 1, confidence: 0.5),
              ],
              unmatched: const [
                UnmatchedItem(text: 'صابون فاخر', quantity: 2, unit: 'علبة'),
              ],
              heardSummary: 'سمعت طلب ٣ كراتين مياه وعلبتين صابون فاخر',
            ),
          ),
        );
        return AiAddItemCubit(repository);
      },
      act: (cubit) => cubit.finishRecording(audioBytes, 'audio/aac', inventory),
      expect: () => [
        isA<AiAddItemMatching>(),
        isA<AiAddItemReviewing>()
            .having((s) => s.matches, 'matches', hasLength(1))
            .having((s) => s.matches.first.item, 'matched item', water)
            .having((s) => s.unmatched, 'unmatched', hasLength(1))
            .having((s) => s.heardSummary, 'heardSummary', isNotNull),
      ],
    );

    blocTest<AiAddItemCubit, AiAddItemState>(
      'finishRecording emits Error on repository failure',
      build: () {
        when(() => repository.matchAudio(any(), any())).thenAnswer(
          (_) async => const AppFailure(AppError(message: 'فشل', type: AppErrorType.server)),
        );
        return AiAddItemCubit(repository);
      },
      act: (cubit) => cubit.finishRecording(audioBytes, 'audio/aac', inventory),
      expect: () => [
        isA<AiAddItemMatching>(),
        isA<AiAddItemError>().having((s) => s.message, 'message', 'فشل'),
      ],
    );

    blocTest<AiAddItemCubit, AiAddItemState>(
      'submitText with blank text emits an empty Reviewing state without calling the repository',
      build: () => AiAddItemCubit(repository),
      act: (cubit) => cubit.submitText('     ', inventory),
      expect: () => [
        isA<AiAddItemReviewing>()
            .having((s) => s.matches, 'matches', isEmpty)
            .having((s) => s.unmatched, 'unmatched', isEmpty),
      ],
      verify: (_) => verifyNever(() => repository.matchText(any())),
    );

    blocTest<AiAddItemCubit, AiAddItemState>(
      'submitText sends the trimmed message and resolves matches the same way audio does',
      build: () {
        when(() => repository.matchText(any())).thenAnswer(
          (_) async => AppSuccess(
            ItemMatchResult(
              matches: const [
                MatchedItem(itemId: 'item-water', quantity: 3, confidence: 0.9),
                MatchedItem(itemId: 'item-unknown', quantity: 1, confidence: 0.5),
              ],
              unmatched: const [
                UnmatchedItem(text: 'صابون فاخر', quantity: 2, unit: 'علبة'),
              ],
              heardSummary: 'فهمت طلب ٣ كراتين مياه وعلبتين صابون فاخر',
            ),
          ),
        );
        return AiAddItemCubit(repository);
      },
      act: (cubit) => cubit.submitText('  السلام عليكم، محتاج ٣ كراتين مياه نوفا  ', inventory),
      expect: () => [
        isA<AiAddItemMatching>(),
        isA<AiAddItemReviewing>()
            .having((s) => s.matches, 'matches', hasLength(1))
            .having((s) => s.matches.first.item, 'matched item', water)
            .having((s) => s.matches.first.quantity, 'quantity', 3)
            .having((s) => s.unmatched, 'unmatched', hasLength(1))
            .having((s) => s.heardSummary, 'heardSummary', isNotNull),
      ],
      verify: (_) =>
          verify(() => repository.matchText('السلام عليكم، محتاج ٣ كراتين مياه نوفا')).called(1),
    );

    blocTest<AiAddItemCubit, AiAddItemState>(
      'submitText keeps ambiguous entries ambiguous, exactly as the audio path does',
      build: () {
        when(() => repository.matchText(any())).thenAnswer(
          (_) async => AppSuccess(
            ItemMatchResult(
              matches: const [],
              unmatched: const [],
              ambiguous: [
                AmbiguousItem(
                  text: 'مياه نوفا',
                  quantity: 2,
                  unit: 'كرتونة',
                  candidateItemIds: [water.id, water500.id],
                ),
              ],
            ),
          ),
        );
        return AiAddItemCubit(repository);
      },
      act: (cubit) => cubit.submitText('محتاج كرتونتين مياه نوفا', inventory),
      expect: () => [
        isA<AiAddItemMatching>(),
        isA<AiAddItemReviewing>()
            .having((s) => s.matches, 'matches', isEmpty)
            .having((s) => s.ambiguous, 'ambiguous', hasLength(1))
            .having((s) => s.ambiguous.single.candidates, 'candidates', [water, water500]),
      ],
    );

    blocTest<AiAddItemCubit, AiAddItemState>(
      'submitText emits Error on repository failure',
      build: () {
        when(() => repository.matchText(any())).thenAnswer(
          (_) async => const AppFailure(AppError(message: 'فشل', type: AppErrorType.server)),
        );
        return AiAddItemCubit(repository);
      },
      act: (cubit) => cubit.submitText('محتاج مياه', inventory),
      expect: () => [
        isA<AiAddItemMatching>(),
        isA<AiAddItemError>().having((s) => s.message, 'message', 'فشل'),
      ],
    );

    blocTest<AiAddItemCubit, AiAddItemState>(
      'updateMatchQuantity and removeMatch mutate the reviewing state',
      build: () => AiAddItemCubit(repository),
      seed: () => const AiAddItemReviewing(
        matches: [ReviewMatch(item: water, quantity: 1, confidence: 0.9)],
        unmatched: [],
      ),
      act: (cubit) {
        cubit.updateMatchQuantity(0, 5);
        cubit.removeMatch(0);
      },
      expect: () => [
        isA<AiAddItemReviewing>()
            .having((s) => s.matches.single.quantity, 'quantity', 5),
        isA<AiAddItemReviewing>().having((s) => s.matches, 'matches', isEmpty),
      ],
    );

    blocTest<AiAddItemCubit, AiAddItemState>(
      'updateUnmatched toggles inclusion and edits quantity/unit',
      build: () => AiAddItemCubit(repository),
      seed: () => const AiAddItemReviewing(
        matches: [],
        unmatched: [ReviewUnmatched(name: 'شيء غامض', quantity: 1, unit: 'قطعة')],
      ),
      act: (cubit) => cubit.updateUnmatched(0, quantity: 4, includeAsCustom: false),
      expect: () => [
        isA<AiAddItemReviewing>()
            .having((s) => s.unmatched.single.quantity, 'quantity', 4)
            .having((s) => s.unmatched.single.includeAsCustom, 'includeAsCustom', false),
      ],
    );

    test('ReviewUnmatched defaults to excluded (opt-in, not opt-out)', () {
      const unmatched = ReviewUnmatched(name: 'شيء غامض', quantity: 1, unit: 'قطعة');
      expect(unmatched.includeAsCustom, false);
    });

    blocTest<AiAddItemCubit, AiAddItemState>(
      'finishRecording keeps ambiguous entries with 2+ valid candidates ambiguous',
      build: () {
        when(() => repository.matchAudio(any(), any())).thenAnswer(
          (_) async => AppSuccess(
            ItemMatchResult(
              matches: const [],
              unmatched: const [],
              ambiguous: [
                AmbiguousItem(
                  text: 'مياه نوفا',
                  quantity: 2,
                  unit: 'كرتونة',
                  candidateItemIds: [water.id, water500.id],
                ),
              ],
            ),
          ),
        );
        return AiAddItemCubit(repository);
      },
      act: (cubit) => cubit.finishRecording(audioBytes, 'audio/aac', inventory),
      expect: () => [
        isA<AiAddItemMatching>(),
        isA<AiAddItemReviewing>()
            .having((s) => s.matches, 'matches', isEmpty)
            .having((s) => s.ambiguous, 'ambiguous', hasLength(1))
            .having((s) => s.ambiguous.single.candidates, 'candidates', [water, water500]),
      ],
    );

    blocTest<AiAddItemCubit, AiAddItemState>(
      'finishRecording auto-promotes an ambiguous entry to a match when only 1 candidate resolves',
      build: () {
        when(() => repository.matchAudio(any(), any())).thenAnswer(
          (_) async => AppSuccess(
            ItemMatchResult(
              matches: const [],
              unmatched: const [],
              ambiguous: [
                AmbiguousItem(
                  text: 'مياه نوفا',
                  quantity: 2,
                  unit: 'كرتونة',
                  candidateItemIds: [water.id, 'item-unknown'],
                ),
              ],
            ),
          ),
        );
        return AiAddItemCubit(repository);
      },
      act: (cubit) => cubit.finishRecording(audioBytes, 'audio/aac', inventory),
      expect: () => [
        isA<AiAddItemMatching>(),
        isA<AiAddItemReviewing>()
            .having((s) => s.ambiguous, 'ambiguous', isEmpty)
            .having((s) => s.matches, 'matches', hasLength(1))
            .having((s) => s.matches.single.item, 'item', water)
            .having((s) => s.matches.single.quantity, 'quantity', 2),
      ],
    );

    blocTest<AiAddItemCubit, AiAddItemState>(
      'finishRecording demotes an ambiguous entry to unmatched when no candidates resolve',
      build: () {
        when(() => repository.matchAudio(any(), any())).thenAnswer(
          (_) async => AppSuccess(
            ItemMatchResult(
              matches: const [],
              unmatched: const [],
              ambiguous: const [
                AmbiguousItem(
                  text: 'مياه نوفا',
                  quantity: 2,
                  unit: 'كرتونة',
                  candidateItemIds: ['item-unknown-1', 'item-unknown-2'],
                ),
              ],
            ),
          ),
        );
        return AiAddItemCubit(repository);
      },
      act: (cubit) => cubit.finishRecording(audioBytes, 'audio/aac', inventory),
      expect: () => [
        isA<AiAddItemMatching>(),
        isA<AiAddItemReviewing>()
            .having((s) => s.ambiguous, 'ambiguous', isEmpty)
            .having((s) => s.matches, 'matches', isEmpty)
            .having((s) => s.unmatched, 'unmatched', hasLength(1))
            .having((s) => s.unmatched.single.name, 'name', 'مياه نوفا'),
      ],
    );

    blocTest<AiAddItemCubit, AiAddItemState>(
      'resolveAmbiguous moves the chosen candidate into matches and clears the ambiguous entry',
      build: () => AiAddItemCubit(repository),
      seed: () => AiAddItemReviewing(
        matches: const [],
        unmatched: const [],
        ambiguous: [
          ReviewAmbiguous(text: 'مياه نوفا', quantity: 2, unit: 'كرتونة', candidates: [water, water500]),
        ],
      ),
      act: (cubit) => cubit.resolveAmbiguous(0, water500),
      expect: () => [
        isA<AiAddItemReviewing>()
            .having((s) => s.ambiguous, 'ambiguous', isEmpty)
            .having((s) => s.matches, 'matches', hasLength(1))
            .having((s) => s.matches.single.item, 'item', water500)
            .having((s) => s.matches.single.quantity, 'quantity', 2),
      ],
    );

    blocTest<AiAddItemCubit, AiAddItemState>(
      'dismissAmbiguous drops the choice into unmatched (unchecked) instead of forcing a pick',
      build: () => AiAddItemCubit(repository),
      seed: () => AiAddItemReviewing(
        matches: const [],
        unmatched: const [],
        ambiguous: [
          ReviewAmbiguous(text: 'مياه نوفا', quantity: 2, unit: 'كرتونة', candidates: [water, water500]),
        ],
      ),
      act: (cubit) => cubit.dismissAmbiguous(0),
      expect: () => [
        isA<AiAddItemReviewing>()
            .having((s) => s.ambiguous, 'ambiguous', isEmpty)
            .having((s) => s.matches, 'matches', isEmpty)
            .having((s) => s.unmatched, 'unmatched', hasLength(1))
            .having((s) => s.unmatched.single.name, 'name', 'مياه نوفا')
            .having((s) => s.unmatched.single.includeAsCustom, 'includeAsCustom', false),
      ],
    );

    group('AiAddItemReviewing.canConfirm', () {
      test('false when ambiguous items remain, even with ready matches', () {
        final state = AiAddItemReviewing(
          matches: const [ReviewMatch(item: water, quantity: 1, confidence: 0.9)],
          unmatched: const [],
          ambiguous: [
            ReviewAmbiguous(text: 'مياه نوفا', quantity: 2, unit: 'كرتونة', candidates: [water, water500]),
          ],
        );
        expect(state.canConfirm, false);
      });

      test('true when there are matches and no ambiguous items', () {
        const state = AiAddItemReviewing(
          matches: [ReviewMatch(item: water, quantity: 1, confidence: 0.9)],
          unmatched: [],
        );
        expect(state.canConfirm, true);
      });

      test('true when an unmatched item is checked for inclusion', () {
        const state = AiAddItemReviewing(
          matches: [],
          unmatched: [ReviewUnmatched(name: 'شيء غامض', quantity: 1, unit: 'قطعة', includeAsCustom: true)],
        );
        expect(state.canConfirm, true);
      });

      test('false when nothing is selected', () {
        const state = AiAddItemReviewing(matches: [], unmatched: []);
        expect(state.canConfirm, false);
      });
    });
  });
}
