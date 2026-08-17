import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ura_core/core/errors/app_error.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/features/verifier/data/voice_match_repository.dart';
import 'package:ura_core/features/verifier/logic/voice_add_item_cubit.dart';
import 'package:ura_core/shared/models/inventory_item.dart';
import 'package:ura_core/shared/models/voice_match_result.dart';

class MockVoiceMatchRepository extends Mock implements VoiceMatchRepository {}

void main() {
  late MockVoiceMatchRepository repository;

  const water = InventoryItem(id: 'item-water', itemName: 'مياه نوفا 330 مل', quantity: 50, unit: 'كرتونة');
  const water500 = InventoryItem(id: 'item-water-500', itemName: 'مياه نوفا 500 مل', quantity: 30, unit: 'كرتونة');
  const soap = InventoryItem(id: 'item-soap', itemName: 'صابون', quantity: 20, unit: 'علبة');
  final inventory = [water, water500, soap];
  final audioBytes = Uint8List.fromList([1, 2, 3]);

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    repository = MockVoiceMatchRepository();
  });

  group('VoiceAddItemCubit', () {
    test('initial state is idle', () {
      expect(VoiceAddItemCubit(repository).state, isA<VoiceAddItemIdle>());
    });

    blocTest<VoiceAddItemCubit, VoiceAddItemState>(
      'startRecording emits Recording',
      build: () => VoiceAddItemCubit(repository),
      act: (cubit) => cubit.startRecording(),
      expect: () => [isA<VoiceAddItemRecording>()],
    );

    blocTest<VoiceAddItemCubit, VoiceAddItemState>(
      'updateElapsed emits Recording with the elapsed seconds',
      build: () => VoiceAddItemCubit(repository),
      act: (cubit) => cubit.updateElapsed(12),
      expect: () => [
        isA<VoiceAddItemRecording>().having((s) => s.elapsedSeconds, 'elapsedSeconds', 12),
      ],
    );

    blocTest<VoiceAddItemCubit, VoiceAddItemState>(
      'finishRecording with empty audio emits empty Reviewing state directly',
      build: () => VoiceAddItemCubit(repository),
      act: (cubit) => cubit.finishRecording(Uint8List(0), 'audio/aac', inventory),
      expect: () => [
        isA<VoiceAddItemReviewing>()
            .having((s) => s.matches, 'matches', isEmpty)
            .having((s) => s.unmatched, 'unmatched', isEmpty),
      ],
      verify: (_) => verifyNever(() => repository.matchVoiceAudio(any(), any())),
    );

    blocTest<VoiceAddItemCubit, VoiceAddItemState>(
      'finishRecording resolves matches against inventory, drops unknown ids, and carries heardSummary',
      build: () {
        when(() => repository.matchVoiceAudio(any(), any())).thenAnswer(
          (_) async => AppSuccess(
            VoiceMatchResult(
              matches: const [
                VoiceItemMatch(itemId: 'item-water', quantity: 3, confidence: 0.9),
                VoiceItemMatch(itemId: 'item-unknown', quantity: 1, confidence: 0.5),
              ],
              unmatched: const [
                VoiceUnmatchedItem(text: 'صابون فاخر', quantity: 2, unit: 'علبة'),
              ],
              heardSummary: 'سمعت طلب ٣ كراتين مياه وعلبتين صابون فاخر',
            ),
          ),
        );
        return VoiceAddItemCubit(repository);
      },
      act: (cubit) => cubit.finishRecording(audioBytes, 'audio/aac', inventory),
      expect: () => [
        isA<VoiceAddItemMatching>(),
        isA<VoiceAddItemReviewing>()
            .having((s) => s.matches, 'matches', hasLength(1))
            .having((s) => s.matches.first.item, 'matched item', water)
            .having((s) => s.unmatched, 'unmatched', hasLength(1))
            .having((s) => s.heardSummary, 'heardSummary', isNotNull),
      ],
    );

    blocTest<VoiceAddItemCubit, VoiceAddItemState>(
      'finishRecording emits Error on repository failure',
      build: () {
        when(() => repository.matchVoiceAudio(any(), any())).thenAnswer(
          (_) async => const AppFailure(AppError(message: 'فشل', type: AppErrorType.server)),
        );
        return VoiceAddItemCubit(repository);
      },
      act: (cubit) => cubit.finishRecording(audioBytes, 'audio/aac', inventory),
      expect: () => [
        isA<VoiceAddItemMatching>(),
        isA<VoiceAddItemError>().having((s) => s.message, 'message', 'فشل'),
      ],
    );

    blocTest<VoiceAddItemCubit, VoiceAddItemState>(
      'updateMatchQuantity and removeMatch mutate the reviewing state',
      build: () => VoiceAddItemCubit(repository),
      seed: () => const VoiceAddItemReviewing(
        matches: [VoiceReviewMatch(item: water, quantity: 1, confidence: 0.9)],
        unmatched: [],
      ),
      act: (cubit) {
        cubit.updateMatchQuantity(0, 5);
        cubit.removeMatch(0);
      },
      expect: () => [
        isA<VoiceAddItemReviewing>()
            .having((s) => s.matches.single.quantity, 'quantity', 5),
        isA<VoiceAddItemReviewing>().having((s) => s.matches, 'matches', isEmpty),
      ],
    );

    blocTest<VoiceAddItemCubit, VoiceAddItemState>(
      'updateUnmatched toggles inclusion and edits quantity/unit',
      build: () => VoiceAddItemCubit(repository),
      seed: () => const VoiceAddItemReviewing(
        matches: [],
        unmatched: [VoiceReviewUnmatched(name: 'شيء غامض', quantity: 1, unit: 'قطعة')],
      ),
      act: (cubit) => cubit.updateUnmatched(0, quantity: 4, includeAsCustom: false),
      expect: () => [
        isA<VoiceAddItemReviewing>()
            .having((s) => s.unmatched.single.quantity, 'quantity', 4)
            .having((s) => s.unmatched.single.includeAsCustom, 'includeAsCustom', false),
      ],
    );

    test('VoiceReviewUnmatched defaults to excluded (opt-in, not opt-out)', () {
      const unmatched = VoiceReviewUnmatched(name: 'شيء غامض', quantity: 1, unit: 'قطعة');
      expect(unmatched.includeAsCustom, false);
    });

    blocTest<VoiceAddItemCubit, VoiceAddItemState>(
      'finishRecording keeps ambiguous entries with 2+ valid candidates ambiguous',
      build: () {
        when(() => repository.matchVoiceAudio(any(), any())).thenAnswer(
          (_) async => AppSuccess(
            VoiceMatchResult(
              matches: const [],
              unmatched: const [],
              ambiguous: [
                VoiceAmbiguousItem(
                  text: 'مياه نوفا',
                  quantity: 2,
                  unit: 'كرتونة',
                  candidateItemIds: [water.id, water500.id],
                ),
              ],
            ),
          ),
        );
        return VoiceAddItemCubit(repository);
      },
      act: (cubit) => cubit.finishRecording(audioBytes, 'audio/aac', inventory),
      expect: () => [
        isA<VoiceAddItemMatching>(),
        isA<VoiceAddItemReviewing>()
            .having((s) => s.matches, 'matches', isEmpty)
            .having((s) => s.ambiguous, 'ambiguous', hasLength(1))
            .having((s) => s.ambiguous.single.candidates, 'candidates', [water, water500]),
      ],
    );

    blocTest<VoiceAddItemCubit, VoiceAddItemState>(
      'finishRecording auto-promotes an ambiguous entry to a match when only 1 candidate resolves',
      build: () {
        when(() => repository.matchVoiceAudio(any(), any())).thenAnswer(
          (_) async => AppSuccess(
            VoiceMatchResult(
              matches: const [],
              unmatched: const [],
              ambiguous: [
                VoiceAmbiguousItem(
                  text: 'مياه نوفا',
                  quantity: 2,
                  unit: 'كرتونة',
                  candidateItemIds: [water.id, 'item-unknown'],
                ),
              ],
            ),
          ),
        );
        return VoiceAddItemCubit(repository);
      },
      act: (cubit) => cubit.finishRecording(audioBytes, 'audio/aac', inventory),
      expect: () => [
        isA<VoiceAddItemMatching>(),
        isA<VoiceAddItemReviewing>()
            .having((s) => s.ambiguous, 'ambiguous', isEmpty)
            .having((s) => s.matches, 'matches', hasLength(1))
            .having((s) => s.matches.single.item, 'item', water)
            .having((s) => s.matches.single.quantity, 'quantity', 2),
      ],
    );

    blocTest<VoiceAddItemCubit, VoiceAddItemState>(
      'finishRecording demotes an ambiguous entry to unmatched when no candidates resolve',
      build: () {
        when(() => repository.matchVoiceAudio(any(), any())).thenAnswer(
          (_) async => AppSuccess(
            VoiceMatchResult(
              matches: const [],
              unmatched: const [],
              ambiguous: const [
                VoiceAmbiguousItem(
                  text: 'مياه نوفا',
                  quantity: 2,
                  unit: 'كرتونة',
                  candidateItemIds: ['item-unknown-1', 'item-unknown-2'],
                ),
              ],
            ),
          ),
        );
        return VoiceAddItemCubit(repository);
      },
      act: (cubit) => cubit.finishRecording(audioBytes, 'audio/aac', inventory),
      expect: () => [
        isA<VoiceAddItemMatching>(),
        isA<VoiceAddItemReviewing>()
            .having((s) => s.ambiguous, 'ambiguous', isEmpty)
            .having((s) => s.matches, 'matches', isEmpty)
            .having((s) => s.unmatched, 'unmatched', hasLength(1))
            .having((s) => s.unmatched.single.name, 'name', 'مياه نوفا'),
      ],
    );

    blocTest<VoiceAddItemCubit, VoiceAddItemState>(
      'resolveAmbiguous moves the chosen candidate into matches and clears the ambiguous entry',
      build: () => VoiceAddItemCubit(repository),
      seed: () => VoiceAddItemReviewing(
        matches: const [],
        unmatched: const [],
        ambiguous: [
          VoiceReviewAmbiguous(text: 'مياه نوفا', quantity: 2, unit: 'كرتونة', candidates: [water, water500]),
        ],
      ),
      act: (cubit) => cubit.resolveAmbiguous(0, water500),
      expect: () => [
        isA<VoiceAddItemReviewing>()
            .having((s) => s.ambiguous, 'ambiguous', isEmpty)
            .having((s) => s.matches, 'matches', hasLength(1))
            .having((s) => s.matches.single.item, 'item', water500)
            .having((s) => s.matches.single.quantity, 'quantity', 2),
      ],
    );

    blocTest<VoiceAddItemCubit, VoiceAddItemState>(
      'dismissAmbiguous drops the choice into unmatched (unchecked) instead of forcing a pick',
      build: () => VoiceAddItemCubit(repository),
      seed: () => VoiceAddItemReviewing(
        matches: const [],
        unmatched: const [],
        ambiguous: [
          VoiceReviewAmbiguous(text: 'مياه نوفا', quantity: 2, unit: 'كرتونة', candidates: [water, water500]),
        ],
      ),
      act: (cubit) => cubit.dismissAmbiguous(0),
      expect: () => [
        isA<VoiceAddItemReviewing>()
            .having((s) => s.ambiguous, 'ambiguous', isEmpty)
            .having((s) => s.matches, 'matches', isEmpty)
            .having((s) => s.unmatched, 'unmatched', hasLength(1))
            .having((s) => s.unmatched.single.name, 'name', 'مياه نوفا')
            .having((s) => s.unmatched.single.includeAsCustom, 'includeAsCustom', false),
      ],
    );

    group('VoiceAddItemReviewing.canConfirm', () {
      test('false when ambiguous items remain, even with ready matches', () {
        final state = VoiceAddItemReviewing(
          matches: const [VoiceReviewMatch(item: water, quantity: 1, confidence: 0.9)],
          unmatched: const [],
          ambiguous: [
            VoiceReviewAmbiguous(text: 'مياه نوفا', quantity: 2, unit: 'كرتونة', candidates: [water, water500]),
          ],
        );
        expect(state.canConfirm, false);
      });

      test('true when there are matches and no ambiguous items', () {
        const state = VoiceAddItemReviewing(
          matches: [VoiceReviewMatch(item: water, quantity: 1, confidence: 0.9)],
          unmatched: [],
        );
        expect(state.canConfirm, true);
      });

      test('true when an unmatched item is checked for inclusion', () {
        const state = VoiceAddItemReviewing(
          matches: [],
          unmatched: [VoiceReviewUnmatched(name: 'شيء غامض', quantity: 1, unit: 'قطعة', includeAsCustom: true)],
        );
        expect(state.canConfirm, true);
      });

      test('false when nothing is selected', () {
        const state = VoiceAddItemReviewing(matches: [], unmatched: []);
        expect(state.canConfirm, false);
      });
    });
  });
}
