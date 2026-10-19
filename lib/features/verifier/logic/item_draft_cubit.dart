import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logic/safe_emit.dart';
import '../../../shared/models/inventory_item.dart';
import '../data/item_match_repository.dart';
import '../data/local_item_matcher.dart';

/// One line of the verifier's draft: what they typed (or what a paste was
/// read as), and -- only if they asked for it -- catalog rows it might be.
class DraftRow extends Equatable {
  final int id;
  final String name;
  final String unit;
  final String quantityText;

  /// Catalog rows offered for this line after "مطابقة مع المخزن". Empty until
  /// then, and empty when nothing came close.
  final List<InventoryItem> suggestions;

  /// The catalog row the verifier picked, or null to keep the line exactly as
  /// typed. Never set by the matcher itself -- matches are often wrong, so a
  /// suggestion is only ever a suggestion.
  final InventoryItem? chosen;

  const DraftRow({
    required this.id,
    this.name = '',
    this.unit = '',
    this.quantityText = '',
    this.suggestions = const [],
    this.chosen,
  });

  double? get quantity => double.tryParse(quantityText.replaceAll(',', '.'));

  bool get isValid => name.trim().isNotEmpty && (quantity ?? 0) > 0;

  DraftRow copyWith({
    String? name,
    String? unit,
    String? quantityText,
    List<InventoryItem>? suggestions,
    InventoryItem? Function()? chosen,
  }) =>
      DraftRow(
        id: id,
        name: name ?? this.name,
        unit: unit ?? this.unit,
        quantityText: quantityText ?? this.quantityText,
        suggestions: suggestions ?? this.suggestions,
        chosen: chosen != null ? chosen() : this.chosen,
      );

  @override
  List<Object?> get props => [id, name, unit, quantityText, suggestions, chosen];
}

class ItemDraftState extends Equatable {
  final List<DraftRow> rows;
  final bool matching;

  /// Set after a matching run where the AI fallback failed for some rows;
  /// the screen shows it once and clears it.
  final String? notice;

  const ItemDraftState({this.rows = const [], this.matching = false, this.notice});

  ItemDraftState copyWith({List<DraftRow>? rows, bool? matching, String? Function()? notice}) =>
      ItemDraftState(
        rows: rows ?? this.rows,
        matching: matching ?? this.matching,
        notice: notice != null ? notice() : this.notice,
      );

  @override
  List<Object?> get props => [rows, matching, notice];
}

/// The draft the verifier builds an order's items in: typed row by row or
/// filled from a pasted list, optionally checked against the catalog, and
/// only handed to the order when they say so.
class ItemDraftCubit extends Cubit<ItemDraftState> with SafeEmit<ItemDraftState> {
  /// Gemini, for rows the on-device matcher could not place at all.
  final ItemMatchRepository _ai;

  ItemDraftCubit(this._ai) : super(const ItemDraftState());

  /// Offered as a choice from this score up -- the same floor
  /// LocalItemMatchRepository uses for its own choices.
  static const _suggestAbove = 0.25;
  static const _maxSuggestions = 4;

  /// One AI call per row (a batched answer can't be mapped back to its row:
  /// a match carries no source text), so both are capped.
  static const _maxAiRows = 15;
  static const _aiConcurrency = 4;

  int _nextId = 0;

  void addRow({String name = '', String unit = '', String quantityText = ''}) {
    safeEmit(state.copyWith(rows: [
      ...state.rows,
      DraftRow(id: _nextId++, name: name, unit: unit, quantityText: quantityText),
    ]));
  }

  void updateRow(int id, {String? name, String? unit, String? quantityText}) {
    safeEmit(state.copyWith(rows: [
      for (final r in state.rows)
        if (r.id == id)
          // Editing the name makes old suggestions stale.
          r.copyWith(
            name: name,
            unit: unit,
            quantityText: quantityText,
            suggestions: name != null && name != r.name ? const [] : null,
            chosen: name != null && name != r.name ? () => null : null,
          )
        else
          r,
    ]));
  }

  void removeRow(int id) =>
      safeEmit(state.copyWith(rows: state.rows.where((r) => r.id != id).toList()));

  /// Appends one row per item read from [text]; returns how many.
  int appendPasted(String text) {
    final parsed = LocalItemMatcher.parseRequest(text);
    safeEmit(state.copyWith(rows: [
      ...state.rows,
      for (final p in parsed)
        DraftRow(
          id: _nextId++,
          name: p.name,
          unit: p.unit ?? '',
          quantityText: _fmt(p.quantity),
        ),
    ]));
    return parsed.length;
  }

  void choose(int id, InventoryItem? item) {
    safeEmit(state.copyWith(rows: [
      for (final r in state.rows) r.id == id ? r.copyWith(chosen: () => item) : r,
    ]));
  }

  void clearNotice() => safeEmit(state.copyWith(notice: () => null));

  /// Fills [DraftRow.suggestions] for every named row: on-device first, then
  /// Gemini for the rows that got nothing. Picks nothing.
  Future<void> checkMatches(List<InventoryItem> inventory) async {
    if (state.matching) return;
    final named = state.rows.where((r) => r.name.trim().isNotEmpty).toList();
    if (named.isEmpty) return;
    safeEmit(state.copyWith(matching: true, notice: () => null));

    final matcher = LocalItemMatcher(inventory);
    final found = <int, List<InventoryItem>>{};
    for (final row in named) {
      final lines = matcher.match(row.name);
      found[row.id] = <InventoryItem>{
        for (final line in lines)
          for (final c in line.candidates)
            if (c.score >= _suggestAbove) c.item,
      }.take(_maxSuggestions).toList();
    }

    final leftovers = named.where((r) => found[r.id]!.isEmpty).take(_maxAiRows).toList();
    var aiFailed = false;
    final byId = {for (final i in inventory) i.id: i};
    for (var start = 0; start < leftovers.length; start += _aiConcurrency) {
      final batch = leftovers.skip(start).take(_aiConcurrency);
      await Future.wait(batch.map((row) async {
        final result = await _ai.matchText(row.name, inventory);
        switch (result) {
          case AppSuccess(:final data):
            found[row.id] = <InventoryItem>{
              for (final m in data.matches) ?byId[m.itemId],
              for (final a in data.ambiguous)
                for (final id in a.candidateItemIds) ?byId[id],
            }.take(_maxSuggestions).toList();
          case AppFailure(:final error):
            logger.w('ItemDraftCubit → AI match failed for "${row.name}": ${error.message}');
            aiFailed = true;
        }
      }));
    }

    safeEmit(state.copyWith(
      matching: false,
      rows: [
        for (final r in state.rows)
          found.containsKey(r.id) ? r.copyWith(suggestions: found[r.id]) : r,
      ],
      notice: aiFailed ? () => 'تعذرت المطابقة الذكية لبعض الأصناف' : null,
    ));
  }

  /// Removes and returns every complete row (a name and a quantity above 0);
  /// incomplete ones stay in the draft to be fixed.
  List<DraftRow> takeValidRows() {
    final valid = state.rows.where((r) => r.isValid).toList();
    safeEmit(state.copyWith(rows: state.rows.where((r) => !r.isValid).toList()));
    return valid;
  }

  static String _fmt(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();
}
