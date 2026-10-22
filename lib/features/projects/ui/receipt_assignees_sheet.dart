import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/models/project.dart';
import '../../verifier/data/order_repository.dart';
import '../data/project_repository.dart';

/// Which reps may file سندات for [project]. Each tick saves at once; the
/// server decides who may change it (verifier/manager/admin) and who can be
/// ticked (approved reps of the project's organization).
Future<void> showReceiptAssigneesSheet(BuildContext context, Project project) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ReceiptAssigneesSheet(project: project),
  );
}

class ReceiptAssigneesSheet extends StatefulWidget {
  final Project project;
  const ReceiptAssigneesSheet({super.key, required this.project});

  @override
  State<ReceiptAssigneesSheet> createState() => _ReceiptAssigneesSheetState();
}

class _ReceiptAssigneesSheetState extends State<ReceiptAssigneesSheet> {
  final _projects = sl<ProjectRepository>();
  List<Profile>? _reps;
  Set<String> _assigned = {};
  final Set<String> _saving = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (reps, assigned) = await (
      sl<OrderRepository>().fetchReps(),
      _projects.fetchReceiptAssignees(widget.project.id),
    ).wait;
    if (!mounted) return;
    setState(() {
      switch ((reps, assigned)) {
        case (AppSuccess(data: final r), AppSuccess(data: final a)):
          _reps = r;
          _assigned = a;
          _error = null;
        case (AppFailure(:final error), _) || (_, AppFailure(:final error)):
          _error = error.message;
      }
    });
  }

  Future<void> _toggle(Profile rep, bool assign) async {
    setState(() {
      _saving.add(rep.id);
      assign ? _assigned.add(rep.id) : _assigned.remove(rep.id);
    });
    final result = await _projects.setReceiptAssignee(widget.project.id, rep.id, assigned: assign);
    if (!mounted) return;
    setState(() {
      _saving.remove(rep.id);
      if (result case AppFailure(:final error)) {
        assign ? _assigned.remove(rep.id) : _assigned.add(rep.id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reps = _reps;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('إسناد السندات للمناديب', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'المندوب المُسند فقط يستطيع إنشاء سند لهذا المشروع. يرى اسم البند ووصفه ووحدته — بدون كميات العقد أو الأسعار.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              )
            else if (reps == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (reps.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('لا يوجد مناديب معتمدون'),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final rep in reps)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _assigned.contains(rep.id),
                        onChanged: _saving.contains(rep.id) ? null : (v) => _toggle(rep, v ?? false),
                        title: Text(rep.fullName),
                        subtitle: rep.phone == null || rep.phone!.isEmpty ? null : Text(rep.phone!),
                        secondary: _saving.contains(rep.id)
                            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.person_outline),
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
