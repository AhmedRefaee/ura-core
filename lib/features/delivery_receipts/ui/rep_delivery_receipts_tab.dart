import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../../../shared/models/delivery_receipt.dart';
import '../data/delivery_receipt_repository.dart';
import 'create_delivery_receipt_screen.dart';
import 'delivery_receipts_section.dart';

/// The rep's standalone path: file a سند later in the day, detached from any
/// order, and see the ones already filed.
class RepDeliveryReceiptsTab extends StatefulWidget {
  const RepDeliveryReceiptsTab({super.key});

  @override
  State<RepDeliveryReceiptsTab> createState() => _RepDeliveryReceiptsTabState();
}

class _RepDeliveryReceiptsTabState extends State<RepDeliveryReceiptsTab> {
  late Future<AppResult<List<DeliveryReceipt>>> _future = _load();

  Future<AppResult<List<DeliveryReceipt>>> _load() => sl<DeliveryReceiptRepository>().fetchMyReceipts();

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  Future<void> _create() async {
    if (await openCreateDeliveryReceipt(context)) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سندات الاستلام')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('سند جديد'),
      ),
      body: FutureBuilder<AppResult<List<DeliveryReceipt>>>(
        future: _future,
        builder: (context, snap) {
          final result = snap.data;
          if (result == null) return const Center(child: CircularProgressIndicator());
          return RefreshIndicator(
            onRefresh: _refresh,
            child: switch (result) {
              AppFailure(:final error) => ListView(children: [
                  Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(error.message))),
                ]),
              AppSuccess(:final data) when data.isEmpty => ListView(children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('لم تنشئ أي سند بعد')),
                  ),
                ]),
              AppSuccess(:final data) => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
                  itemCount: data.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => DeliveryReceiptTile(receipt: data[i]),
                ),
            },
          );
        },
      ),
    );
  }
}
