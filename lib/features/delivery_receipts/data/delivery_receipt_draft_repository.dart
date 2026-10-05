import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/models/delivery_receipt_draft.dart';

/// سند drafts live only on this device -- see CreateDeliveryReceiptCubit.
/// saveDraft()'s doc for why that's the right tradeoff for a "pause and
/// continue later" convenience rather than a server table.
class DeliveryReceiptDraftRepository {
  static const _key = 'delivery_receipt_drafts';

  final SharedPreferences _prefs;
  DeliveryReceiptDraftRepository(this._prefs);

  /// Newest first.
  List<DeliveryReceiptDraft> list() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      final drafts = decoded
          .map((e) => DeliveryReceiptDraft.fromJson(e as Map<String, dynamic>))
          .toList();
      drafts.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return drafts;
    } catch (_) {
      // Corrupt/old-shape local data must never crash the drafts list --
      // just behave as if there were none.
      return [];
    }
  }

  /// Upserts by id: saving a draft already shown in the list replaces it
  /// rather than piling up a duplicate.
  Future<void> save(DeliveryReceiptDraft draft) async {
    final drafts = list().where((d) => d.id != draft.id).toList()..add(draft);
    await _prefs.setString(_key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }

  Future<void> delete(String id) async {
    final drafts = list().where((d) => d.id != id).toList();
    await _prefs.setString(_key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }
}
