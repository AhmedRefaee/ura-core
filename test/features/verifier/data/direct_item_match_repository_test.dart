// Drives the real repository with the Firebase SDK replaced by a scripted fake.
// The point of the ItemMatchModel seam is exactly this: the ref mapping and the
// failure handling are what can put a wrong item into somebody's order, and
// neither should need a Firebase project to test.
import 'dart:async';
import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/features/verifier/data/direct_item_match_repository.dart';
import 'package:ura_core/features/verifier/data/item_match_model.dart';
import 'package:ura_core/shared/models/inventory_item.dart';
import 'package:ura_core/shared/models/item_match_result.dart';

/// Answers from a script: each entry is either a reply body or an error to
/// throw, so one test can say "fail, fail, then succeed".
///
/// Every answer is delivered in two pieces on purpose. A fake that only ever
/// hands over whole replies would not notice the repository forgetting to
/// accumulate the stream it is now reading.
class ScriptedModel implements ItemMatchModel {
  ScriptedModel(this.script);

  final List<Object> script;
  final List<String> catalogsSeen = [];
  final List<String> instructionsSeen = [];
  int calls = 0;

  @override
  Stream<ItemMatchModelChunk> generate({
    required String systemInstruction,
    required String catalogBlock,
    required String text,
  }) async* {
    calls++;
    catalogsSeen.add(catalogBlock);
    instructionsSeen.add(systemInstruction);
    final next = script.isEmpty ? script.last : script.removeAt(0);
    if (next is Exception) throw next;

    final json = next as String;
    final split = json.length ~/ 2;
    yield ItemMatchModelChunk(text: json.substring(0, split));
    yield ItemMatchModelChunk(
      text: json.substring(split),
      usage: const ItemMatchUsage(
        promptTokens: 900,
        outputTokens: 120,
        totalTokens: 1500,
      ),
    );
  }
}

/// Opens a stream and then says nothing, like a model that has accepted the
/// request and is still thinking about it. Records whether the repository
/// cancelled the subscription, which is the whole point of streaming: a
/// `Future.timeout` leaves the call running and billed.
class SilentModel implements ItemMatchModel {
  int calls = 0;
  bool cancelled = false;

  @override
  Stream<ItemMatchModelChunk> generate({
    required String systemInstruction,
    required String catalogBlock,
    required String text,
  }) {
    calls++;
    final controller = StreamController<ItemMatchModelChunk>();
    controller.onCancel = () => cancelled = true;
    return controller.stream;
  }
}

/// Emits a chunk every [gap] until [chunks] runs out, then closes -- a model
/// that is slow overall but never actually silent.
class DrippingModel implements ItemMatchModel {
  DrippingModel({required this.body, required this.chunks, required this.gap});

  final String body;
  final int chunks;
  final Duration gap;
  int calls = 0;

  @override
  Stream<ItemMatchModelChunk> generate({
    required String systemInstruction,
    required String catalogBlock,
    required String text,
  }) async* {
    calls++;
    final size = (body.length / chunks).ceil();
    for (var i = 0; i < chunks; i++) {
      await Future<void>.delayed(gap);
      final start = i * size;
      if (start >= body.length) break;
      final end = start + size > body.length ? body.length : start + size;
      yield ItemMatchModelChunk(text: body.substring(start, end));
    }
  }
}

/// Never stops talking. Nothing it says is ever a complete answer.
class EndlessModel implements ItemMatchModel {
  int calls = 0;

  @override
  Stream<ItemMatchModelChunk> generate({
    required String systemInstruction,
    required String catalogBlock,
    required String text,
  }) async* {
    calls++;
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      yield const ItemMatchModelChunk(text: 'x');
    }
  }
}

void main() {
  const water330 = InventoryItem(
    id: 'id-water-330',
    itemName: 'مياه نوفا 330 مل',
    quantity: 50,
    unit: 'كرتونة',
  );
  const water500 = InventoryItem(
    id: 'id-water-500',
    itemName: 'مياه نوفا 500 مل',
    quantity: 20,
    unit: 'كرتونة',
  );
  const soap = InventoryItem(
    id: 'id-soap',
    itemName: 'صابون لوكس',
    quantity: 8,
    unit: 'علبة',
  );
  const inventory = [water330, water500, soap];

  String answer({
    List<Map<String, Object?>> matches = const [],
    List<Map<String, Object?>> unmatched = const [],
    List<Map<String, Object?>> ambiguous = const [],
    String? heard,
  }) =>
      jsonEncode({
        'matches': matches,
        'unmatched': unmatched,
        'ambiguous': ambiguous,
        'heard_summary': ?heard,
      });

  Future<ItemMatchResult> matchText(ScriptedModel model, {String text = 'محتاج مياه'}) async {
    final result = await DirectItemMatchRepository(model: model)
        .matchText(text, inventory);
    return (result as AppSuccess<ItemMatchResult>).data;
  }

  group('turning the model answer into items', () {
    test('a ref becomes the real inventory id', () async {
      final model = ScriptedModel([
        answer(
          matches: [
            {'item_ref': 1, 'quantity': 3, 'confidence': 0.9},
          ],
          heard: 'ثلاث كراتين مياه',
        ),
      ]);

      final result = await matchText(model);

      expect(result.matches.single.itemId, 'id-water-330');
      expect(result.matches.single.quantity, 3);
      expect(result.matches.single.confidence, 0.9);
      expect(result.heardSummary, 'ثلاث كراتين مياه');
    });

    test('an invented ref cannot reach the order', () async {
      final model = ScriptedModel([
        answer(matches: [
          {'item_ref': 99, 'quantity': 2, 'confidence': 1},
          {'item_ref': 3, 'quantity': 1, 'confidence': 1},
        ]),
      ]);

      final result = await matchText(model);

      expect(result.matches.single.itemId, 'id-soap');
    });

    test('a zero or negative quantity is dropped', () async {
      final model = ScriptedModel([
        answer(matches: [
          {'item_ref': 1, 'quantity': 0, 'confidence': 1},
          {'item_ref': 2, 'quantity': -4, 'confidence': 1},
        ]),
      ]);

      expect((await matchText(model)).matches, isEmpty);
    });

    test('a ref returned as a string still resolves', () async {
      final model = ScriptedModel([
        answer(matches: [
          {'item_ref': '2', 'quantity': 5, 'confidence': 0.8},
        ]),
      ]);

      expect((await matchText(model)).matches.single.itemId, 'id-water-500');
    });

    test('unmatched phrases come through for the custom-item flow', () async {
      final model = ScriptedModel([
        answer(unmatched: [
          {'text': 'شامبو', 'quantity': 2, 'unit': 'علبة'},
          {'text': '   '},
        ]),
      ]);

      final result = await matchText(model);

      expect(result.unmatched.single.text, 'شامبو');
      expect(result.unmatched.single.quantity, 2);
    });
  });

  group('ambiguous candidates', () {
    test('resolve to ids for the review sheet', () async {
      final model = ScriptedModel([
        answer(ambiguous: [
          {
            'text': 'مياه نوفا',
            'quantity': 2,
            'unit': 'كرتونة',
            'candidate_item_refs': [1, 2],
          },
        ]),
      ]);

      final result = await matchText(model);

      expect(result.ambiguous.single.candidateItemIds,
          ['id-water-330', 'id-water-500']);
      expect(result.matches, isEmpty);
    });

    test('a single surviving candidate is promoted to a match', () async {
      final model = ScriptedModel([
        answer(ambiguous: [
          {
            'text': 'مياه',
            'quantity': 2,
            'candidate_item_refs': [2, 99],
          },
        ]),
      ]);

      final result = await matchText(model);

      expect(result.ambiguous, isEmpty);
      expect(result.matches.single.itemId, 'id-water-500');
      expect(result.matches.single.quantity, 2);
    });

    test('no surviving candidate falls back to unmatched', () async {
      final model = ScriptedModel([
        answer(ambiguous: [
          {
            'text': 'شيء غريب',
            'quantity': 4,
            'unit': 'علبة',
            'candidate_item_refs': [99, 100],
          },
        ]),
      ]);

      final result = await matchText(model);

      expect(result.matches, isEmpty);
      expect(result.unmatched.single.text, 'شيء غريب');
      expect(result.unmatched.single.quantity, 4);
    });

    test('the same row offered twice is only offered once', () async {
      final model = ScriptedModel([
        answer(ambiguous: [
          {
            'text': 'مياه',
            'candidate_item_refs': [1, 1, 2],
          },
        ]),
      ]);

      expect((await matchText(model)).ambiguous.single.candidateItemIds,
          ['id-water-330', 'id-water-500']);
    });
  });

  group('what the model is given', () {
    test('the catalog, never the ids', () async {
      final model = ScriptedModel([answer()]);

      await matchText(model);

      expect(model.catalogsSeen.single, contains('1|مياه نوفا 330 مل|كرتونة'));
      expect(model.catalogsSeen.single, isNot(contains('id-water-330')));
    });

    test('the written-request instruction', () async {
      final model = ScriptedModel([answer()]);
      await matchText(model);
      expect(model.instructionsSeen.single, contains('written order request'));
    });

    test('an empty inventory is answered without calling the model at all', () async {
      final model = ScriptedModel([answer()]);

      final result = await DirectItemMatchRepository(model: model)
          .matchText('محتاج مياه', const []);

      expect(model.calls, 0);
      expect((result as AppSuccess<ItemMatchResult>).data.matches, isEmpty);
    });
  });

  group('when the call fails', () {
    test('a transient failure is retried and the verifier never sees it', () async {
      final model = ScriptedModel([
        ServerException('the model is overloaded'),
        answer(matches: [
          {'item_ref': 1, 'quantity': 1, 'confidence': 1},
        ]),
      ]);

      final result = await matchText(model);

      expect(model.calls, 2);
      expect(result.matches.single.itemId, 'id-water-330');
    });

    test('malformed JSON is retried — a re-roll can genuinely fix it', () async {
      final model = ScriptedModel([
        'not json at all',
        answer(matches: [
          {'item_ref': 3, 'quantity': 1, 'confidence': 1},
        ]),
      ]);

      final result = await matchText(model);

      expect(model.calls, 2);
      expect(result.matches.single.itemId, 'id-soap');
    });

    test('a bad key fails immediately instead of burning the budget', () async {
      final model = ScriptedModel([InvalidApiKey('bad key')]);

      final result = await DirectItemMatchRepository(model: model)
          .matchText('محتاج مياه', inventory);

      expect(model.calls, 1);
      expect(result, isA<AppFailure>());
      expect((result as AppFailure).error.message, contains('الدعم الفني'));
    });

    test('an unprovisioned project says so rather than "try again"', () async {
      final model = ScriptedModel([ServiceApiNotEnabled('projects/ura-core-9981c')]);

      final result = await DirectItemMatchRepository(model: model)
          .matchText('محتاج مياه', inventory);

      expect(model.calls, 1);
      expect((result as AppFailure).error.message, contains('غير مفعّلة'));
    });

    test('an exhausted quota fails on the first try, not the third', () async {
      // The failure that ended 2026-08-24: a 429 was classified as transient,
      // so every quota error spent two further requests against the quota that
      // had just refused it. Retrying cannot clear a limit -- it funds it.
      final model = ScriptedModel([
        QuotaExceeded('You exceeded your current quota'),
        QuotaExceeded('You exceeded your current quota'),
        QuotaExceeded('You exceeded your current quota'),
      ]);

      final result = await DirectItemMatchRepository(model: model)
          .matchText('محتاج مياه', inventory);

      expect(model.calls, 1);
      final failure = result as AppFailure;
      expect(failure.error.message, contains('حصة'));
      // Not the busy message: "try again shortly" is advice that costs money.
      expect(failure.error.message, isNot(contains('مزدحمة')));
    });

    test('sustained overload gives up with the busy message', () async {
      final model = ScriptedModel([
        ServerException('overloaded'),
        ServerException('overloaded'),
        ServerException('overloaded'),
      ]);

      final result = await DirectItemMatchRepository(model: model)
          .matchText('محتاج مياه', inventory);

      expect(model.calls, DirectItemMatchRepository.maxAttempts);
      expect((result as AppFailure).error.message, contains('مزدحمة'));
    });
  });

  // The device log from 2026-08-24 is the specification for this group: a
  // request that Gemini answered in about 60 s was cut off at 20 s, retried
  // twice more against a call that had never stopped running, and reported to
  // the verifier as a busy service -- five seconds before the real answer
  // arrived and was discarded.
  group('waiting on a slow model', () {
    test('a slow call is never retried into a second concurrent one', () async {
      final model = SilentModel();

      final result = await DirectItemMatchRepository(
        model: model,
        idleTimeout: const Duration(milliseconds: 80),
        ceiling: const Duration(seconds: 5),
      ).matchText('محتاج مياه', inventory);

      // One call, not three. A retry cannot cancel what it is retrying, so a
      // second attempt would only compete with the first for the same pipe.
      expect(model.calls, 1);
      expect((result as AppFailure).error.message, contains('تأخرت'));
    });

    test('giving up actually cancels the request', () async {
      final model = SilentModel();

      await DirectItemMatchRepository(
        model: model,
        idleTimeout: const Duration(milliseconds: 80),
        ceiling: const Duration(seconds: 5),
      ).matchText('محتاج مياه', inventory);

      expect(model.cancelled, isTrue);
    });

    test('the clock is silence, not total elapsed time', () async {
      final body = jsonEncode({
        'matches': [
          {'item_ref': 1, 'quantity': 2, 'confidence': 1},
        ],
        'unmatched': <Object>[],
        'ambiguous': <Object>[],
      });
      // Ten chunks 30 ms apart is 300 ms overall -- far past the 80 ms idle
      // timeout, but never 80 ms of quiet. The old total-elapsed cap failed
      // exactly this shape of call.
      final model = DrippingModel(
        body: body,
        chunks: 10,
        gap: const Duration(milliseconds: 30),
      );

      final result = await DirectItemMatchRepository(
        model: model,
        idleTimeout: const Duration(milliseconds: 80),
        ceiling: const Duration(seconds: 5),
      ).matchText('محتاج مياه', inventory);

      expect(model.calls, 1);
      expect((result as AppSuccess<ItemMatchResult>).data.matches.single.itemId,
          'id-water-330');
    });

    test('a stream that never ends is still cut off at the ceiling', () async {
      final model = EndlessModel();

      final result = await DirectItemMatchRepository(
        model: model,
        idleTimeout: const Duration(seconds: 5),
        ceiling: const Duration(milliseconds: 120),
      ).matchText('محتاج مياه', inventory);

      expect(model.calls, 1);
      expect((result as AppFailure).error.message, contains('تأخرت'));
    });

    test('an answer split across chunks is reassembled', () async {
      final model = ScriptedModel([
        answer(matches: [
          {'item_ref': 2, 'quantity': 7, 'confidence': 0.5},
        ], heard: 'سبع كراتين'),
      ]);

      final result = await matchText(model);

      expect(result.matches.single.itemId, 'id-water-500');
      expect(result.matches.single.quantity, 7);
      expect(result.heardSummary, 'سبع كراتين');
    });
  });
}
