// These drive the paste screen through a real AiAddItemCubit with only the
// network edge mocked, so the compose -> analyze -> review -> confirm path is
// exercised end to end the way a verifier walks it.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ura_core/core/errors/app_error.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/features/verifier/data/item_match_repository.dart';
import 'package:ura_core/features/verifier/logic/ai_add_item_cubit.dart';
import 'package:ura_core/features/verifier/ui/widgets/paste_add_item_view.dart';
import 'package:ura_core/shared/models/inventory_item.dart';
import 'package:ura_core/shared/models/item_match_result.dart';

class MockItemMatchRepository extends Mock implements ItemMatchRepository {}

void main() {
  const water = InventoryItem(id: 'item-water', itemName: 'مياه نوفا 330 مل', quantity: 50, unit: 'كرتونة');
  late MockItemMatchRepository repository;

  setUp(() {
    repository = MockItemMatchRepository();
    // The screen wakes the edge function as it opens; unstubbed, the mock
    // answers null and the post-frame callback dies on it.
    when(() => repository.warmUp()).thenAnswer((_) async {});
  });

  void stubOneMatch() {
    when(() => repository.matchText(any(), any())).thenAnswer(
      (_) async => const AppSuccess(
        ItemMatchResult(
          matches: [MatchedItem(itemId: 'item-water', quantity: 3, confidence: 0.95)],
          unmatched: [],
          heardSummary: 'ثلاث كراتين مياه نوفا',
        ),
      ),
    );
  }

  Widget wrap({
    void Function(List<({InventoryItem item, double quantity})> items)? onAddInventoryItems,
  }) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            child: const Text('open'),
            onPressed: () => Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => BlocProvider(
                  create: (_) => AiAddItemCubit(repository),
                  child: PasteAddItemView(
                    inventory: const [water],
                    onAddInventoryItems: onAddInventoryItems ?? (_) {},
                    onAddCustomItem: (_, _, {sourceInventoryId}) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('opening the screen wakes the function before there is anything to send',
      (tester) async {
    await tester.pumpWidget(wrap());
    await open(tester);

    // The point is the ordering: the warm-up goes out while the person is
    // still pasting and reading, so the real request doesn't pay a cold start.
    verify(() => repository.warmUp()).called(1);
    verifyNever(() => repository.matchText(any(), any()));
  });

  testWidgets('the analyze button stays disabled until the message has content', (tester) async {
    await tester.pumpWidget(wrap());
    await open(tester);

    ElevatedButton analyze() => tester.widget<ElevatedButton>(
          find.ancestor(of: find.text('تحليل الرسالة'), matching: find.byType(ElevatedButton)),
        );

    expect(analyze().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'محتاج ٣ كراتين مياه نوفا');
    await tester.pump();

    expect(analyze().onPressed, isNotNull);
  });

  testWidgets('whitespace alone does not enable analysis', (tester) async {
    await tester.pumpWidget(wrap());
    await open(tester);

    await tester.enterText(find.byType(TextField), '      ');
    await tester.pump();

    final analyze = tester.widget<ElevatedButton>(
      find.ancestor(of: find.text('تحليل الرسالة'), matching: find.byType(ElevatedButton)),
    );
    expect(analyze.onPressed, isNull);
    verifyNever(() => repository.matchText(any(), any()));
  });

  testWidgets('analyzing a pasted message shows the matched items for review', (tester) async {
    stubOneMatch();
    await tester.pumpWidget(wrap());
    await open(tester);

    await tester.enterText(find.byType(TextField), 'السلام عليكم، محتاج ٣ كراتين مياه نوفا');
    await tester.pump();
    await tester.tap(find.text('تحليل الرسالة'));
    await tester.pumpAndSettle();

    expect(find.text('مياه نوفا 330 مل'), findsOneWidget);
    expect(find.text('فهمت: ثلاث كراتين مياه نوفا'), findsOneWidget);
    verify(() => repository.matchText('السلام عليكم، محتاج ٣ كراتين مياه نوفا', any())).called(1);
  });

  testWidgets('confirming hands the reviewed items to the caller and closes the screen', (tester) async {
    stubOneMatch();
    List<({InventoryItem item, double quantity})>? added;

    await tester.pumpWidget(wrap(onAddInventoryItems: (items) => added = items));
    await open(tester);

    await tester.enterText(find.byType(TextField), 'محتاج ٣ كراتين مياه نوفا');
    await tester.pump();
    await tester.tap(find.text('تحليل الرسالة'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('تأكيد وإضافة'));
    await tester.pumpAndSettle();

    expect(added, isNotNull);
    expect(added!.single.item, water);
    expect(added!.single.quantity, 3);
    expect(find.text('open'), findsOneWidget, reason: 'the paste screen should have closed');
  });

  testWidgets('a failed analysis offers a way back to the message', (tester) async {
    when(() => repository.matchText(any(), any())).thenAnswer(
      (_) async => const AppFailure(AppError(message: 'فشل الاتصال', type: AppErrorType.server)),
    );

    await tester.pumpWidget(wrap());
    await open(tester);

    await tester.enterText(find.byType(TextField), 'محتاج مياه');
    await tester.pump();
    await tester.tap(find.text('تحليل الرسالة'));
    await tester.pumpAndSettle();

    expect(find.text('فشل الاتصال'), findsOneWidget);

    await tester.tap(find.text('تعديل النص'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.text('محتاج مياه'),
      findsOneWidget,
      reason: 'the pasted message should survive a failed attempt',
    );
  });
}
