import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ura_core/core/errors/app_error.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/features/verifier/data/hybrid_item_match_repository.dart';
import 'package:ura_core/features/verifier/data/item_match_repository.dart';
import 'package:ura_core/shared/models/inventory_item.dart';
import 'package:ura_core/shared/models/item_match_result.dart';

class MockItemMatchRepository extends Mock implements ItemMatchRepository {}

void main() {
  late MockItemMatchRepository mockLocal;
  late MockItemMatchRepository mockAi;
  late HybridItemMatchRepository hybrid;

  const water = InventoryItem(id: 'item-water', itemName: 'مياه نوفا', quantity: 50, unit: 'كرتونة');
  final inventory = [water];

  setUpAll(() {
    registerFallbackValue(<InventoryItem>[]);
  });

  setUp(() {
    mockLocal = MockItemMatchRepository();
    mockAi = MockItemMatchRepository();
    hybrid = HybridItemMatchRepository(local: mockLocal, ai: mockAi);
  });

  test('zero failed lines never calls AI', () async {
    const localSuccess = AppSuccess(
      ItemMatchResult(
        matches: [MatchedItem(itemId: 'item-water', quantity: 2, confidence: 0.9)],
        unmatched: [],
        ambiguous: [],
      ),
    );
    when(() => mockLocal.matchText(any(), any())).thenAnswer((_) async => localSuccess);

    final result = await hybrid.matchText('3 مياه نوفا', inventory);

    expect(result, localSuccess);
    verifyNever(() => mockAi.matchText(any(), any()));
  });

  test('failed lines trigger exactly one AI call with unmatched-then-ambiguous texts joined', () async {
    when(() => mockLocal.matchText(any(), any())).thenAnswer(
      (_) async => const AppSuccess(
        ItemMatchResult(
          matches: [],
          unmatched: [UnmatchedItem(text: 'صابون فاخر')],
          ambiguous: [AmbiguousItem(text: 'مياه نوفا', candidateItemIds: ['item-water', 'item-water-500'])],
        ),
      ),
    );
    when(() => mockAi.matchText(any(), any())).thenAnswer(
      (_) async => const AppSuccess(ItemMatchResult(matches: [], unmatched: [], ambiguous: [])),
    );

    await hybrid.matchText('صابون فاخر\nمياه نوفا', inventory);

    verify(() => mockAi.matchText('صابون فاخر\nمياه نوفا', inventory)).called(1);
  });

  test('AI success merges: local matches survive alongside AI matches, AI owns unmatched/ambiguous/summary', () async {
    when(() => mockLocal.matchText(any(), any())).thenAnswer(
      (_) async => const AppSuccess(
        ItemMatchResult(
          matches: [MatchedItem(itemId: 'item-water', quantity: 3, confidence: 0.9)],
          unmatched: [UnmatchedItem(text: 'صابون فاخر')],
          ambiguous: [],
        ),
      ),
    );
    when(() => mockAi.matchText(any(), any())).thenAnswer(
      (_) async => const AppSuccess(
        ItemMatchResult(
          matches: [MatchedItem(itemId: 'item-soap', quantity: 1, confidence: 0.8)],
          unmatched: [UnmatchedItem(text: 'شيء غريب')],
          ambiguous: [],
          understoodSummary: 'فهمت طلب صابون فاخر',
        ),
      ),
    );

    final result = await hybrid.matchText('3 مياه نوفا\nصابون فاخر', inventory);

    // AppSuccess/AppFailure use plain identity equality (no == override), and
    // this branch constructs a new ItemMatchResult at runtime -- unwrap and
    // compare the inner value, which is Equatable, rather than the wrapper.
    expect(result, isA<AppSuccess<ItemMatchResult>>());
    expect(
      (result as AppSuccess<ItemMatchResult>).data,
      const ItemMatchResult(
        matches: [
          MatchedItem(itemId: 'item-water', quantity: 3, confidence: 0.9),
          MatchedItem(itemId: 'item-soap', quantity: 1, confidence: 0.8),
        ],
        unmatched: [UnmatchedItem(text: 'شيء غريب')],
        ambiguous: [],
        understoodSummary: 'فهمت طلب صابون فاخر',
      ),
    );
  });

  test('AI failure degrades to exactly the local-only result', () async {
    const localSuccess = AppSuccess(
      ItemMatchResult(
        matches: [MatchedItem(itemId: 'item-water', quantity: 3, confidence: 0.9)],
        unmatched: [UnmatchedItem(text: 'صابون فاخر')],
        ambiguous: [],
      ),
    );
    when(() => mockLocal.matchText(any(), any())).thenAnswer((_) async => localSuccess);
    when(() => mockAi.matchText(any(), any())).thenAnswer(
      (_) async => const AppFailure(AppError(message: 'الخدمة مزدحمة حالياً', type: AppErrorType.server)),
    );

    final result = await hybrid.matchText('3 مياه نوفا\nصابون فاخر', inventory);

    expect(result, localSuccess);
  });

  test('local failure short-circuits without ever calling AI', () async {
    const localFailure = AppFailure<ItemMatchResult>(
      AppError(message: 'تعذر المعالجة', type: AppErrorType.unknown),
    );
    when(() => mockLocal.matchText(any(), any())).thenAnswer((_) async => localFailure);

    final result = await hybrid.matchText('3 مياه نوفا', inventory);

    expect(result, localFailure);
    verifyNever(() => mockAi.matchText(any(), any()));
  });

  test('warmUp delegates to local only', () async {
    when(() => mockLocal.warmUp()).thenAnswer((_) async {});

    await hybrid.warmUp();

    verify(() => mockLocal.warmUp()).called(1);
    verifyNever(() => mockAi.warmUp());
  });
}
