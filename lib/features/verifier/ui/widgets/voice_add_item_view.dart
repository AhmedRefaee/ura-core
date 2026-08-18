import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../../../core/design_system/theme/theme.dart';
import '../../../../shared/models/inventory_item.dart';
import '../../logic/voice_add_item_cubit.dart';

const _maxRecordingSeconds = 5 * 60;
// 'audio/aac' is one of Gemini's officially documented inline-audio MIME
// types; 'audio/mp4' is not, so this stays audio/aac despite AudioEncoder.aacLc
// technically wrapping the AAC stream in an MP4/M4A container.
const _audioMimeType = 'audio/aac';

/// Voice capture + AI-narrowed review flow, pushed on top of AddItemSheet.
/// Records raw audio and sends it directly to a multimodal LLM (no on-device
/// speech-to-text — that approach produced poor Arabic transcription, wrong
/// language detection, and premature cutoffs in testing). Speaking "3 crates
/// of water and 2 boxes of soap" produces a review list of real inventory
/// matches (never invented items) plus anything the backend couldn't
/// confidently match, which routes to the existing custom-item flow.
/// Confirming pops this view with `true` and calls the same callbacks
/// AddItemSheet's manual submit uses, so the parent screen (create/edit
/// order) needs no changes.
class VoiceAddItemView extends StatefulWidget {
  final List<InventoryItem> inventory;
  final void Function(List<({InventoryItem item, double quantity})> items) onAddInventoryItems;
  final void Function(String description, double quantity, {String? sourceInventoryId}) onAddCustomItem;

  const VoiceAddItemView({
    super.key,
    required this.inventory,
    required this.onAddInventoryItems,
    required this.onAddCustomItem,
  });

  @override
  State<VoiceAddItemView> createState() => _VoiceAddItemViewState();
}

class _VoiceAddItemViewState extends State<VoiceAddItemView> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _ticker;
  int _elapsedSeconds = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startRecording());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    _finished = false;
    _elapsedSeconds = 0;
    final cubit = context.read<VoiceAddItemCubit>();

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      _showError('تعذر الوصول إلى الميكروفون، يرجى التحقق من الأذونات');
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 48000, sampleRate: 44100),
        path: path,
      );
    } catch (_) {
      if (!mounted) return;
      _showError('تعذر بدء التسجيل، يرجى المحاولة مجدداً');
      return;
    }

    cubit.startRecording();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _elapsedSeconds++;
      cubit.updateElapsed(_elapsedSeconds);
      if (_elapsedSeconds >= _maxRecordingSeconds) _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    if (_finished) return;
    _ticker?.cancel();
    final path = await _recorder.stop();
    await _finish(path);
  }

  Future<void> _finish(String? path) async {
    if (_finished || !mounted) return;
    _finished = true;
    final cubit = context.read<VoiceAddItemCubit>();
    final bytes = path == null ? Uint8List(0) : await File(path).readAsBytes();
    cubit.finishRecording(bytes, _audioMimeType, widget.inventory);
  }

  void _showError(String message) {
    context.read<VoiceAddItemCubit>().retry();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _confirm(VoiceAddItemReviewing state) {
    if (state.matches.isNotEmpty) {
      widget.onAddInventoryItems(
        state.matches.map((m) => (item: m.item, quantity: m.quantity)).toList(),
      );
    }
    for (final u in state.unmatched.where((u) => u.includeAsCustom)) {
      final payload = jsonEncode({
        'name': u.name,
        'qty': u.quantity,
        'unit': u.unit,
        'minQty': 0,
      });
      widget.onAddCustomItem(payload, u.quantity);
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة عن طريق الصوت'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.allLarge,
          child: BlocBuilder<VoiceAddItemCubit, VoiceAddItemState>(
            builder: (context, state) {
              return switch (state) {
                VoiceAddItemIdle() => const _CenteredMessage(text: 'جاري التحضير...'),
                VoiceAddItemRecording(:final elapsedSeconds) => _RecordingView(
                    elapsedSeconds: elapsedSeconds,
                    onStop: _stopRecording,
                  ),
                VoiceAddItemMatching() =>
                  const _CenteredMessage(text: 'جاري تحليل الصوت ومطابقته مع المخزون...'),
                VoiceAddItemReviewing() => _ReviewView(
                    state: state,
                    onConfirm: () => _confirm(state),
                    onRetry: _startRecording,
                  ),
                VoiceAddItemError() => _ErrorView(
                    message: state.message,
                    onRetry: _startRecording,
                  ),
              };
            },
          ),
        ),
      ),
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

class _RecordingView extends StatelessWidget {
  final int elapsedSeconds;
  final VoidCallback onStop;

  const _RecordingView({required this.elapsedSeconds, required this.onStop});

  String get _formatted {
    final m = elapsedSeconds ~/ 60;
    final s = elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
            ),
            child: Icon(Icons.mic, size: 48, color: theme.colorScheme.primary),
          ),
          SizedBox(height: AppSpacing.verticalLarge),
          const Text('تحدث الآن... مثال: ٣ كراتين مياه وعلبتين صابون', textAlign: TextAlign.center),
          SizedBox(height: AppSpacing.verticalMedium),
          Text(_formatted, style: theme.textTheme.headlineMedium),
          SizedBox(height: AppSpacing.verticalLarge),
          FilledButton.icon(
            onPressed: onStop,
            icon: const Icon(Icons.stop),
            label: const Text('إنهاء'),
          ),
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
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}

class _ReviewView extends StatelessWidget {
  final VoiceAddItemReviewing state;
  final VoidCallback onConfirm;
  final VoidCallback onRetry;

  const _ReviewView({required this.state, required this.onConfirm, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<VoiceAddItemCubit>();
    final theme = Theme.of(context);

    if (state.matches.isEmpty && state.unmatched.isEmpty && state.ambiguous.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic_off, size: 48, color: Colors.grey),
            SizedBox(height: AppSpacing.verticalMedium),
            const Text('لم يتم التعرف على أي كلام، حاول مرة أخرى'),
            SizedBox(height: AppSpacing.verticalLarge),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.mic),
              label: const Text('إعادة المحاولة'),
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
                Icon(Icons.hearing, size: 18, color: theme.colorScheme.primary),
                SizedBox(width: AppSpacing.horizontalSmall),
                Expanded(
                  child: Text('سمعت: ${state.heardSummary}', style: theme.textTheme.bodySmall),
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
  final VoiceReviewAmbiguous ambiguous;
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
  final VoiceReviewMatch match;
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
  final VoiceReviewUnmatched unmatched;
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
