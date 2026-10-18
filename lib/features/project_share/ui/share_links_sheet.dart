import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../../../shared/models/project.dart';
import '../data/project_share_repository.dart';
import '../models/shared_project.dart';

/// Create, send and revoke read-only links to a project's بنود for the
/// outside entity. The server decides who may (verifier/manager/admin).
Future<void> showShareLinksSheet(BuildContext context, Project project) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ShareLinksSheet(project: project),
  );
}

class ShareLinksSheet extends StatefulWidget {
  final Project project;
  const ShareLinksSheet({super.key, required this.project});

  @override
  State<ShareLinksSheet> createState() => _ShareLinksSheetState();
}

enum _Expiry {
  never('بدون انتهاء', null),
  week('7 أيام', Duration(days: 7)),
  month('30 يوم', Duration(days: 30));

  final String label;
  final Duration? duration;
  const _Expiry(this.label, this.duration);
}

class _ShareLinksSheetState extends State<ShareLinksSheet> {
  final _repo = sl<ProjectShareRepository>();
  List<ProjectShareLink>? _links;
  String? _error;
  bool _busy = false;
  _Expiry _expiry = _Expiry.never;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await _repo.listLinks(widget.project.id);
    if (!mounted) return;
    setState(() {
      switch (result) {
        case AppSuccess(:final data):
          _links = data.where((l) => l.isActive()).toList();
          _error = null;
        case AppFailure(:final error):
          _error = error.message;
      }
    });
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    final d = _expiry.duration;
    final result = await _repo.createLink(
      widget.project.id,
      expiresAt: d == null ? null : DateTime.now().add(d),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case AppSuccess(:final data):
        await _load();
        if (mounted) await _send(data);
      case AppFailure(:final error):
        _snack(error.message);
    }
  }

  Future<void> _send(String token) async {
    final url = shareLinkUrl(token);
    final box = context.findRenderObject() as RenderBox?;
    final bounds = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          text: 'بنود مشروع ${widget.project.name}\n$url',
          sharePositionOrigin: bounds,
        ),
      );
      if (result.status == ShareResultStatus.unavailable) await _copy(token);
    } catch (_) {
      await _copy(token);
    }
  }

  Future<void> _copy(String token) async {
    await Clipboard.setData(ClipboardData(text: shareLinkUrl(token)));
    _snack('تم نسخ الرابط');
  }

  Future<void> _revoke(ProjectShareLink link) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الرابط؟'),
        content: const Text('لن يتمكن أي شخص لديه هذا الرابط من فتحه بعد الآن.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إلغاء الرابط')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final result = await _repo.revokeLink(link.id);
    if (!mounted) return;
    switch (result) {
      case AppSuccess():
        _snack('تم إلغاء الرابط');
        await _load();
      case AppFailure(:final error):
        _snack(error.message);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.day}/${l.month}/${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final links = _links;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('مشاركة البنود مع الجهة', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'من يفتح الرابط يرى اسم البند ووصفه ووحدته فقط — بدون كميات أو أسعار، وبدون تسجيل دخول.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text('مدة الصلاحية', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _Expiry.values)
                  ChoiceChip(
                    label: Text(e.label),
                    selected: _expiry == e,
                    onSelected: _busy ? null : (_) => setState(() => _expiry = e),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: _busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_link),
              label: const Text('إنشاء رابط وإرساله'),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text('الروابط الفعالة', style: theme.textTheme.labelLarge),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              )
            else if (links == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (links.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('لا توجد روابط فعالة'),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final link in links)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.link),
                        title: Text('أُنشئ ${_date(link.createdAt)}'),
                        subtitle: Text(
                          link.expiresAt == null ? 'بدون انتهاء' : 'ينتهي ${_date(link.expiresAt!)}',
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: 'نسخ',
                              icon: const Icon(Icons.copy),
                              onPressed: () => _copy(link.token),
                            ),
                            IconButton(
                              tooltip: 'إرسال',
                              icon: const Icon(Icons.share_outlined),
                              onPressed: () => _send(link.token),
                            ),
                            IconButton(
                              tooltip: 'إلغاء الرابط',
                              icon: Icon(Icons.link_off, color: theme.colorScheme.error),
                              onPressed: () => _revoke(link),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
