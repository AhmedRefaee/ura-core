// The review list is shared by the voice screen and the paste screen, so
// these tests pin the parts that must look identical for both inputs, plus
// the wording that must not.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ura_core/features/verifier/data/item_match_repository.dart';
import 'package:ura_core/features/verifier/logic/ai_add_item_cubit.dart';
import 'package:ura_core/features/verifier/ui/widgets/ai_item_review_view.dart';
import 'package:ura_core/shared/models/inventory_item.dart';

class MockItemMatchRepository extends Mock implements ItemMatchRepository {}

void main() {
  const water = InventoryItem(id: 'item-water', itemName: 'مياه نوفا 330 مل', quantity: 50, unit: 'كرتونة');
  const water500 = InventoryItem(id: 'item-water-500', itemName: 'مياه نوفا 500 مل', quantity: 30, unit: 'كرتونة');

  Widget wrap(AiAddItemReviewing state, {AiReviewCopy copy = AiReviewCopy.voice}) {
    return MaterialApp(
      home: Scaffold(
        body: BlocProvider(
          create: (_) => AiAddItemCubit(MockItemMatchRepository()),
          child: AiItemReviewView(
            state: state,
            copy: copy,
            onConfirm: () {},
            onRetry: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('renders a tile per matched, ambiguous, and unmatched entry', (tester) async {
    await tester.pumpWidget(wrap(AiAddItemReviewing(
      matches: const [ReviewMatch(item: water, quantity: 3, confidence: 0.9)],
      unmatched: const [ReviewUnmatched(name: 'صابون فاخر', quantity: 2, unit: 'علبة')],
      ambiguous: const [
        ReviewAmbiguous(text: 'مياه نوفا', quantity: 2, unit: 'كرتونة', candidates: [water, water500]),
      ],
    )));

    expect(find.text('مياه نوفا 330 مل'), findsWidgets);
    expect(find.text('صابون فاخر'), findsOneWidget);
    expect(find.text('أي صنف تقصد؟'), findsOneWidget);
  });

  testWidgets('confirm stays disabled while an ambiguous entry is unresolved', (tester) async {
    await tester.pumpWidget(wrap(AiAddItemReviewing(
      matches: const [ReviewMatch(item: water, quantity: 3, confidence: 0.9)],
      unmatched: const [],
      ambiguous: const [
        ReviewAmbiguous(text: 'مياه نوفا', quantity: 2, unit: 'كرتونة', candidates: [water, water500]),
      ],
    )));

    final button = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(button.onPressed, isNull);
  });

  testWidgets('confirm is enabled once nothing is ambiguous', (tester) async {
    await tester.pumpWidget(wrap(const AiAddItemReviewing(
      matches: [ReviewMatch(item: water, quantity: 3, confidence: 0.9)],
      unmatched: [],
    )));

    final button = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(button.onPressed, isNotNull);
  });

  testWidgets('the summary is introduced as heard for voice and understood for text', (tester) async {
    const state = AiAddItemReviewing(
      matches: [ReviewMatch(item: water, quantity: 3, confidence: 0.9)],
      unmatched: [],
      heardSummary: 'ثلاث كراتين مياه',
    );

    await tester.pumpWidget(wrap(state));
    expect(find.text('سمعت: ثلاث كراتين مياه'), findsOneWidget);

    await tester.pumpWidget(wrap(state, copy: AiReviewCopy.text));
    expect(find.text('فهمت: ثلاث كراتين مياه'), findsOneWidget);
  });

  group('applyAiReview', () {
    test('sends matched rows to the inventory callback and skips unchecked phrases', () {
      List<({InventoryItem item, double quantity})>? inventoryItems;
      var customCalls = 0;

      applyAiReview(
        const AiAddItemReviewing(
          matches: [ReviewMatch(item: water, quantity: 3, confidence: 0.9)],
          unmatched: [ReviewUnmatched(name: 'صابون فاخر', quantity: 2, unit: 'علبة')],
        ),
        onAddInventoryItems: (items) => inventoryItems = items,
        onAddCustomItem: (_, _, {sourceInventoryId}) => customCalls++,
      );

      expect(inventoryItems!.single.item, water);
      expect(inventoryItems!.single.quantity, 3);
      expect(customCalls, 0, reason: 'an unchecked phrase must not become a custom item');
    });

    test('encodes a checked phrase as the same JSON payload manual entry uses', () {
      String? payload;
      double? quantity;

      applyAiReview(
        const AiAddItemReviewing(
          matches: [],
          unmatched: [
            ReviewUnmatched(name: 'صابون فاخر', quantity: 2, unit: 'علبة', includeAsCustom: true),
          ],
        ),
        onAddInventoryItems: (_) {},
        onAddCustomItem: (description, qty, {sourceInventoryId}) {
          payload = description;
          quantity = qty;
        },
      );

      expect(quantity, 2);
      expect(jsonDecode(payload!), {'name': 'صابون فاخر', 'qty': 2.0, 'unit': 'علبة', 'minQty': 0});
    });
  });

  testWidgets('an empty result explains itself in terms of the input that produced it', (tester) async {
    await tester.pumpWidget(wrap(const AiAddItemReviewing(matches: [], unmatched: [])));
    expect(find.text(AiReviewCopy.voice.emptyMessage), findsOneWidget);

    await tester.pumpWidget(wrap(const AiAddItemReviewing(matches: [], unmatched: []), copy: AiReviewCopy.text));
    expect(find.text(AiReviewCopy.text.emptyMessage), findsOneWidget);
    expect(AiReviewCopy.text.emptyMessage, isNot(AiReviewCopy.voice.emptyMessage));
  });
}
