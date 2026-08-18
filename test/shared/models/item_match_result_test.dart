import 'package:flutter_test/flutter_test.dart';
import 'package:ura_core/shared/models/item_match_result.dart';

void main() {
  group('MatchedItem', () {
    test('fromMap parses all fields', () {
      final match = MatchedItem.fromMap({
        'item_id': 'item-1',
        'quantity': 3,
        'confidence': 0.92,
      });
      expect(match.itemId, 'item-1');
      expect(match.quantity, 3.0);
      expect(match.confidence, 0.92);
    });

    test('missing confidence defaults to 0', () {
      final match = MatchedItem.fromMap({'item_id': 'item-1', 'quantity': 1});
      expect(match.confidence, 0);
    });
  });

  group('UnmatchedItem', () {
    test('fromMap parses all fields', () {
      final item = UnmatchedItem.fromMap({
        'text': 'صابون فاخر',
        'quantity': 2,
        'unit': 'علبة',
      });
      expect(item.text, 'صابون فاخر');
      expect(item.quantity, 2.0);
      expect(item.unit, 'علبة');
    });

    test('missing quantity and unit are null', () {
      final item = UnmatchedItem.fromMap({'text': 'شيء غامض'});
      expect(item.quantity, isNull);
      expect(item.unit, isNull);
    });
  });

  group('AmbiguousItem', () {
    test('fromMap parses all fields', () {
      final item = AmbiguousItem.fromMap({
        'text': 'مياه نوفا',
        'quantity': 2,
        'unit': 'كرتونة',
        'candidate_item_ids': ['item-330ml', 'item-500ml'],
      });
      expect(item.text, 'مياه نوفا');
      expect(item.quantity, 2.0);
      expect(item.unit, 'كرتونة');
      expect(item.candidateItemIds, ['item-330ml', 'item-500ml']);
    });

    test('missing candidate_item_ids defaults to empty list', () {
      final item = AmbiguousItem.fromMap({'text': 'مياه نوفا'});
      expect(item.candidateItemIds, isEmpty);
    });
  });

  group('ItemMatchResult', () {
    test('fromMap parses matches and unmatched lists', () {
      final result = ItemMatchResult.fromMap({
        'matches': [
          {'item_id': 'item-1', 'quantity': 3, 'confidence': 0.9},
        ],
        'unmatched': [
          {'text': 'شيء غامض', 'quantity': 1, 'unit': 'قطعة'},
        ],
      });
      expect(result.matches, hasLength(1));
      expect(result.unmatched, hasLength(1));
      expect(result.matches.first.itemId, 'item-1');
      expect(result.unmatched.first.text, 'شيء غامض');
    });

    test('fromMap parses ambiguous list', () {
      final result = ItemMatchResult.fromMap({
        'matches': [],
        'unmatched': [],
        'ambiguous': [
          {
            'text': 'مياه نوفا',
            'quantity': 2,
            'unit': 'كرتونة',
            'candidate_item_ids': ['item-330ml', 'item-500ml'],
          },
        ],
      });
      expect(result.ambiguous, hasLength(1));
      expect(result.ambiguous.first.candidateItemIds, hasLength(2));
    });

    test('missing matches/unmatched/ambiguous default to empty lists', () {
      final result = ItemMatchResult.fromMap({});
      expect(result.matches, isEmpty);
      expect(result.unmatched, isEmpty);
      expect(result.ambiguous, isEmpty);
    });

    test('parses heard_summary when present', () {
      final result = ItemMatchResult.fromMap({
        'matches': [],
        'unmatched': [],
        'heard_summary': 'سمعت طلب ٣ كراتين مياه',
      });
      expect(result.heardSummary, 'سمعت طلب ٣ كراتين مياه');
    });

    test('heard_summary is null when missing', () {
      final result = ItemMatchResult.fromMap({});
      expect(result.heardSummary, isNull);
    });
  });
}
