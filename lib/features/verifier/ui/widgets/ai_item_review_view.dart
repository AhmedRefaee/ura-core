import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/design_system/theme/theme.dart';
import '../../../../shared/models/inventory_item.dart';
import '../../logic/ai_add_item_cubit.dart';

/// The wording around the shared review list that depends on how the request
/// arrived. The list itself is identical either way — only the way it refers
/// back to the input changes: a recording was heard, a message was read.
class AiReviewCopy {
  final IconData summaryIcon;
  final String summaryPrefix;
  final IconData emptyIcon;
  final String emptyMessage;
  final IconData retryIcon;
  final String retryLabel;

  const AiReviewCopy({
    required this.summaryIcon,
    required this.summaryPrefix,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.retryIcon,
    required this.retryLabel,
  });

  static const voice = AiReviewCopy(
    summaryIcon: Icons.hearing,
    summaryPrefix: 'سمعت',
    emptyIcon: Icons.mic_off,
    emptyMessage: 'لم يتم التعرف على أي كلام، حاول مرة أخرى',
    retryIcon: Icons.mic,
    retryLabel: 'إعادة المحاولة',
  );

  static const text = AiReviewCopy(
    summaryIcon: Icons.chat_bubble_outline,
    summaryPrefix: 'فهمت',
    emptyIcon: Icons.search_off,
    emptyMessage: 'لم يتم التعرف على أي صنف في الرسالة، راجع النص وحاول مجدداً',
    retryIcon: Icons.edit,
    retryLabel: 'تعديل النص',
  );
}

/// The review step both AI entry paths end at: inventory matches with editable
/// quantities, entries that need a choice before anything can be confirmed,
/// and phrases that matched nothing, which stay opted out of the order unless
/// the user checks them in.
class AiItemReviewView extends StatelessWidget {
  final AiAddItemReviewing state;
  final AiReviewCopy copy;
  final VoidCallback onConfirm;
  final VoidCallback onRetry;

  const AiItemReviewView({
    super.key,
    required this.state,
    required this.copy,
    required this.onConfirm,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AiAddItemCubit>();
    final theme = Theme.of(context);

    if (state.matches.isEmpty && state.unmatched.isEmpty && state.ambiguous.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(copy.emptyIcon, size: 48, color: Colors.grey),
            SizedBox(height: AppSpacing.verticalMedium),
            Text(copy.emptyMessage, textAlign: TextAlign.center),
            SizedBox(height: AppSpacing.verticalLarge),
            FilledButton.icon(
              onPressed: onRetry,
              icon: Icon(copy.retryIcon),
              label: Text(copy.retryLabel),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.heardSummary != null && state.heardSummary!.trim().isNotEmpty)
          Container(
            margin: EdgeInsets.only(bottom: AppSpacing.verticalMedium),
            padding: AppSpacing.allMedium,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(copy.summaryIcon, size: 18, color: theme.colorScheme.primary),
                SizedBox(width: AppSpacing.horizontalSmall),
                Expanded(
                  child: Text('${copy.summaryPrefix}: ${state.heardSummary}',
                      style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            children: [
              if (state.ambiguous.isNotEmpty) ...[
                Text('بحاجة إلى تحديد', style: theme.textTheme.titleMedium?.copyWith(color: Colors.orange)),
                SizedBox(height: AppSpacing.verticalSmall),
                for (var i = 0; i < state.ambiguous.length; i++)
                  _AmbiguousTile(
                    ambiguous: state.ambiguous[i],
                    onChoose: (item) => cubit.resolveAmbiguous(i, item),
                    onDismiss: () => cubit.dismissAmbiguous(i),
                  ),
                SizedBox(height: AppSpacing.verticalLarge),
              ],
              if (state.matches.isNotEmpty) ...[
                Text('أصناف من المخزون', style: theme.textTheme.titleMedium),
                SizedBox(height: AppSpacing.verticalSmall),
                for (var i = 0; i < state.matches.length; i++)
                  _MatchTile(
                    match: state.matches[i],
                    onQuantityChanged: (q) => cubit.updateMatchQuantity(i, q),
                    onRemove: () => cubit.removeMatch(i),
                  ),
              ],
              if (state.unmatched.isNotEmpty) ...[
                SizedBox(height: AppSpacing.verticalLarge),
                Text('غير متوفرة في المخزون', style: theme.textTheme.titleMedium),
                SizedBox(height: AppSpacing.verticalSmall),
                for (var i = 0; i < state.unmatched.length; i++)
                  _UnmatchedTile(
                    unmatched: state.unmatched[i],
                    onToggle: (v) => cubit.updateUnmatched(i, includeAsCustom: v),
                    onQuantityChanged: (q) => cubit.updateUnmatched(i, quantity: q),
                  ),
              ],
            ],
          ),
        ),
        if (state.ambiguous.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.verticalSmall),
            child: Text(
              'يرجى تحديد الصنف المقصود أو تجاهله لكل الأصناف غير الواضحة أولاً',
              style: const TextStyle(fontSize: 12, color: Colors.orange),
              textAlign: TextAlign.center,
            ),
          ),
        FilledButton(
          onPressed: state.canConfirm ? onConfirm : null,
          child: Text(
            'تأكيد وإضافة ${state.matches.length + state.unmatched.where((u) => u.includeAsCustom).length} صنف',
          ),
        ),
      ],
    );
  }
}

class _AmbiguousTile extends StatelessWidget {
  final ReviewAmbiguous ambiguous;
  final ValueChanged<InventoryItem> onChoose;
  final VoidCallback onDismiss;

  const _AmbiguousTile({required this.ambiguous, required this.onChoose, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: AppSpacing.verticalSmall),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: AppSpacing.allMedium,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${ambiguous.text} · الكمية: ${ambiguous.quantity.toString()} ${ambiguous.unit}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'تجاهل، لا يوجد صنف مطابق',
                  onPressed: onDismiss,
                ),
              ],
            ),
            const Text('أي صنف تقصد؟', style: TextStyle(fontSize: 12, color: Colors.grey)),
            SizedBox(height: AppSpacing.verticalSmall),
            Wrap(
              spacing: AppSpacing.horizontalSmall,
              runSpacing: AppSpacing.verticalSmall,
              children: [
                for (final candidate in ambiguous.candidates)
                  OutlinedButton(
                    onPressed: () => onChoose(candidate),
                    child: Text(candidate.itemName),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  final ReviewMatch match;
  final ValueChanged<double> onQuantityChanged;
  final VoidCallback onRemove;

  const _MatchTile({required this.match, required this.onQuantityChanged, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final confidencePercent = (match.confidence * 100).round();
    return Card(
      margin: EdgeInsets.only(bottom: AppSpacing.verticalSmall),
      child: Padding(
        padding: AppSpacing.allMedium,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(match.item.itemName, style: const TextStyle(fontWeight: FontWeight.w500)),
                  SizedBox(height: AppSpacing.verticalXSmall),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.horizontalXSmall, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'تطابق $confidencePercent%',
                      style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 72,
              child: TextFormField(
                initialValue: match.quantity.toString(),
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                onChanged: (v) => onQuantityChanged(double.tryParse(v) ?? match.quantity),
              ),
            ),
            IconButton(icon: const Icon(Icons.close), onPressed: onRemove),
          ],
        ),
      ),
    );
  }
}

class _UnmatchedTile extends StatelessWidget {
  final ReviewUnmatched unmatched;
  final ValueChanged<bool> onToggle;
  final ValueChanged<double> onQuantityChanged;

  const _UnmatchedTile({
    required this.unmatched,
    required this.onToggle,
    required this.onQuantityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: AppSpacing.verticalSmall),
      child: Padding(
        padding: AppSpacing.allMedium,
        child: Row(
          children: [
            Checkbox(value: unmatched.includeAsCustom, onChanged: (v) => onToggle(v ?? false)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(unmatched.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text('إضافة كصنف مخصص · ${unmatched.unit}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            SizedBox(
              width: 72,
              child: TextFormField(
                initialValue: unmatched.quantity.toString(),
                textAlign: TextAlign.center,
                enabled: unmatched.includeAsCustom,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                onChanged: (v) => onQuantityChanged(double.tryParse(v) ?? unmatched.quantity),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
