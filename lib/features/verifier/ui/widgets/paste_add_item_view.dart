import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/design_system/theme/theme.dart';
import '../../../../shared/models/inventory_item.dart';
import '../../logic/ai_add_item_cubit.dart';
import 'ai_item_review_view.dart';

/// Mirrors the edge function's own cap, so a message too long to be accepted
/// is stopped at the keyboard rather than after a round trip.
const _maxMessageChars = 4000;

/// Paste-a-message item entry, pushed on top of AddItemSheet. Verifiers get
/// order requests as WhatsApp messages from people at outside entities;
/// pasting one here runs the same match against the org's inventory that the
/// voice screen runs, and ends at the same review list. Text skips the audio
/// recording and the audio-understanding pass, so it is the quicker of the
/// two ways in. Confirming pops this view with `true` and calls the same
/// callbacks AddItemSheet's manual submit uses, so the parent screen
/// (create/edit order) needs no changes.
class PasteAddItemView extends StatefulWidget {
  final List<InventoryItem> inventory;
  final void Function(List<({InventoryItem item, double quantity})> items) onAddInventoryItems;
  final void Function(String description, double quantity, {String? sourceInventoryId}) onAddCustomItem;

  const PasteAddItemView({
    super.key,
    required this.inventory,
    required this.onAddInventoryItems,
    required this.onAddCustomItem,
  });

  @override
  State<PasteAddItemView> createState() => _PasteAddItemViewState();
}

class _PasteAddItemViewState extends State<PasteAddItemView> {
  final _controller = TextEditingController();
  bool _hasMessage = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onMessageChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onMessageChanged);
    _controller.dispose();
    super.dispose();
  }

  /// Only rebuilds when the button's enabled state actually flips, rather
  /// than on every keystroke of a message that can run to 4000 characters.
  void _onMessageChanged() {
    final hasMessage = _controller.text.trim().isNotEmpty;
    if (hasMessage != _hasMessage) setState(() => _hasMessage = hasMessage);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الحافظة فارغة')),
      );
      return;
    }
    _controller.text = text.length > _maxMessageChars ? text.substring(0, _maxMessageChars) : text;
  }

  void _analyze() {
    context.read<AiAddItemCubit>().submitText(_controller.text, widget.inventory);
  }

  void _confirm(AiAddItemReviewing state) {
    applyAiReview(
      state,
      onAddInventoryItems: widget.onAddInventoryItems,
      onAddCustomItem: widget.onAddCustomItem,
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة من رسالة'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.allLarge,
          child: BlocBuilder<AiAddItemCubit, AiAddItemState>(
            builder: (context, state) {
              return switch (state) {
                // Recording never happens on this screen; it shares the cubit
                // with the voice path, so the compose step covers both idle
                // cases rather than pretending one is unreachable.
                AiAddItemIdle() || AiAddItemRecording() => _buildCompose(context),
                AiAddItemMatching() =>
                  const _CenteredMessage(text: 'جاري تحليل الرسالة ومطابقتها مع المخزون...'),
                AiAddItemReviewing() => AiItemReviewView(
                    state: state,
                    copy: AiReviewCopy.text,
                    onConfirm: () => _confirm(state),
                    onRetry: () => context.read<AiAddItemCubit>().retry(),
                  ),
                AiAddItemError() => _ErrorView(
                    message: state.message,
                    onRetry: () => context.read<AiAddItemCubit>().retry(),
                  ),
              };
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCompose(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'الصق رسالة الطلب كما وصلتك — التحية والتوقيع وأي كلام خارج الطلب سيتم تجاهله',
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton.icon(
              onPressed: _pasteFromClipboard,
              icon: const Icon(Icons.content_paste),
              label: const Text('لصق'),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.verticalSmall),
        Expanded(
          child: TextField(
            controller: _controller,
            maxLines: null,
            expands: true,
            maxLength: _maxMessageChars,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'مثال: السلام عليكم، محتاجين ٣ كراتين مياه وعلبتين صابون',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        ),
        SizedBox(height: AppSpacing.verticalMedium),
        ElevatedButton.icon(
          onPressed: _hasMessage ? _analyze : null,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('تحليل الرسالة'),
        ),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final String text;
  const _CenteredMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          SizedBox(height: AppSpacing.verticalLarge),
          Text(text, style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          SizedBox(height: AppSpacing.verticalMedium),
          Text(message, textAlign: TextAlign.center),
          SizedBox(height: AppSpacing.verticalLarge),
          FilledButton.icon(
            onPressed: onRetry,
            icon: Icon(AiReviewCopy.text.retryIcon),
            label: Text(AiReviewCopy.text.retryLabel),
          ),
        ],
      ),
    );
  }
}
