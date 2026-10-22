import '../../../shared/models/delivery_receipt.dart';

/// Whose سندات the سندات tab lists, for users who can see everyone's
/// (verifiers/admins). Everyone else only ever sees their own.
sealed class ReceiptCreatorFilter {
  const ReceiptCreatorFilter();
}

/// The signed-in user's own -- the default.
class MineFilter extends ReceiptCreatorFilter {
  const MineFilter();
}

class EveryoneFilter extends ReceiptCreatorFilter {
  const EveryoneFilter();
}

/// One person who filed سندات.
class PersonFilter extends ReceiptCreatorFilter {
  final String userId;
  const PersonFilter(this.userId);

  @override
  bool operator ==(Object other) => other is PersonFilter && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;
}

/// Filed by an outside entity through a share link (no account).
class ShareLinkFilter extends ReceiptCreatorFilter {
  const ShareLinkFilter();
}

/// A person a verifier can filter by: everyone else who filed a سند in
/// [receipts], sorted by name. [myId] is left out (that's [MineFilter]).
List<({String id, String name})> receiptCreators(List<DeliveryReceipt> receipts, String? myId) {
  final byId = <String, String>{};
  for (final r in receipts) {
    final id = r.repId;
    if (id != null && id != myId) byId[id] = r.rep?.fullName ?? 'مستخدم';
  }
  return [for (final e in byId.entries) (id: e.key, name: e.value)]..sort((a, b) => a.name.compareTo(b.name));
}

/// The entities in [receipts], once each, by name -- what the entity
/// filter offers.
List<({String id, String name})> receiptEntities(List<DeliveryReceipt> receipts) {
  final byId = <String, String>{};
  for (final r in receipts) {
    byId[r.entityId] = r.entity?.name ?? 'جهة';
  }
  return [for (final e in byId.entries) (id: e.key, name: e.value)]..sort((a, b) => a.name.compareTo(b.name));
}

/// The day a سند is listed under: delivery if known, else filing.
DateTime? receiptDay(DeliveryReceipt r) {
  final when = (r.deliveredAt ?? r.createdAt)?.toLocal();
  return when == null ? null : DateTime(when.year, when.month, when.day);
}

/// [entityId] null = every entity. [from]/[to] are whole days, inclusive;
/// either may be null for an open end. A سند with no date only passes when
/// no date range is set.
List<DeliveryReceipt> filterReceiptsByEntityAndDate(
  List<DeliveryReceipt> receipts, {
  String? entityId,
  DateTime? from,
  DateTime? to,
}) {
  final start = from == null ? null : DateTime(from.year, from.month, from.day);
  final end = to == null ? null : DateTime(to.year, to.month, to.day);
  return [
    for (final r in receipts)
      if ((entityId == null || r.entityId == entityId) &&
          (start == null && end == null ||
              switch (receiptDay(r)) {
                null => false,
                final d => (start == null || !d.isBefore(start)) && (end == null || !d.isAfter(end)),
              }))
        r,
  ];
}

List<DeliveryReceipt> filterReceiptsByCreator(
  List<DeliveryReceipt> receipts,
  ReceiptCreatorFilter filter,
  String? myId,
) =>
    switch (filter) {
      EveryoneFilter() => receipts,
      MineFilter() => [for (final r in receipts) if (r.repId != null && r.repId == myId) r],
      PersonFilter(:final userId) => [for (final r in receipts) if (r.repId == userId) r],
      ShareLinkFilter() => [for (final r in receipts) if (r.isPortalSubmission) r],
    };
