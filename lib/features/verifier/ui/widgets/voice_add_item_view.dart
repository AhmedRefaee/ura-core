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
import '../../logic/ai_add_item_cubit.dart';
import 'ai_item_review_view.dart';

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
    final cubit = context.read<AiAddItemCubit>();

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
    final cubit = context.read<AiAddItemCubit>();
    final bytes = path == null ? Uint8List(0) : await File(path).readAsBytes();
    cubit.finishRecording(bytes, _audioMimeType, widget.inventory);
  }

  void _showError(String message) {
    context.read<AiAddItemCubit>().retry();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _confirm(AiAddItemReviewing state) {
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
          child: BlocBuilder<AiAddItemCubit, AiAddItemState>(
            builder: (context, state) {
              return switch (state) {
                AiAddItemIdle() => const _CenteredMessage(text: 'جاري التحضير...'),
                AiAddItemRecording(:final elapsedSeconds) => _RecordingView(
                    elapsedSeconds: elapsedSeconds,
                    onStop: _stopRecording,
                  ),
                AiAddItemMatching() =>
                  const _CenteredMessage(text: 'جاري تحليل الصوت ومطابقته مع المخزون...'),
                AiAddItemReviewing() => AiItemReviewView(
                    state: state,
                    copy: AiReviewCopy.voice,
                    onConfirm: () => _confirm(state),
                    onRetry: _startRecording,
                  ),
                AiAddItemError() => _ErrorView(
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
